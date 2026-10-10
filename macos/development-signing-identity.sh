#!/bin/bash

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: macos/development-signing-identity.sh [--create | --unlock]

--create (the default, `make signing-identity`) creates the self-signed
"Try Roguix Development" code-signing identity in its own keychain, once.
--unlock (`make app`) unlocks that keychain and prints the identity's SHA-1
and the keychain path, tab-separated, or nothing when it does not exist.
The login keychain and the keychain search list are never changed.
EOF
  exit 64
}

mode=create
case "${1:-}" in
  ''|--create) ;;
  --unlock) mode=unlock ;;
  *) usage ;;
esac

name="Try Roguix Development"
keychain="$HOME/Library/Keychains/try-roguix-development.keychain-db"
# The password only guards a local development key; it lives beside the
# keychain's own protection (the user's home), readable only by the user.
password_file="$HOME/.config/try-roguix/development-keychain-password"

identity_hash() {
  # Untrusted self-signed identities are listed without -v; codesign signs
  # with them by hash all the same.
  security find-identity -p codesigning "$keychain" 2>/dev/null |
    awk -v name="\"$name\"" '
      $1 ~ /^[0-9]+\)$/ && index($0, name) { print $2; exit }'
}

unlock() {
  security unlock-keychain -p "$(cat "$password_file")" "$keychain"
}

if [[ $mode == unlock ]]; then
  [[ -f $keychain && -f $password_file ]] || exit 0
  unlock
  hash=$(identity_hash)
  [[ -n $hash ]] && printf '%s\t%s\n' "$hash" "$keychain"
  exit 0
fi

if [[ -f $keychain ]]; then
  [[ -f $password_file ]] || {
    echo "signing-identity: $keychain exists without $password_file;" \
      "remove the keychain (security delete-keychain) and run this again" >&2
    exit 1
  }
  unlock
  hash=$(identity_hash)
  [[ -n $hash ]] || {
    echo "signing-identity: $keychain has no \"$name\" identity;" \
      "remove it (security delete-keychain) and run this again" >&2
    exit 1
  }
  echo "signing-identity: \"$name\" already exists ($hash) in $keychain"
  exit 0
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/try-roguix-signing.XXXXXX")
trap 'rm -rf "$work"' EXIT

mkdir -p "$(dirname "$password_file")"
chmod 700 "$(dirname "$password_file")"
(umask 077 && /usr/bin/openssl rand -hex 32 >"$password_file")
password=$(cat "$password_file")
transport=$(/usr/bin/openssl rand -hex 32)

cat >"$work/openssl.cnf" <<EOF
[req]
distinguished_name = subject
x509_extensions = codesigning
prompt = no
[subject]
CN = $name
[codesigning]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
(umask 077 && /usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -sha256 \
  -days 3650 -config "$work/openssl.cnf" \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null)
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
  -name "$name" -passout "pass:$transport" -out "$work/identity.p12"

security create-keychain -p "$password" "$keychain"
# No automatic lock: `make app` unlocks it again after a restart.
security set-keychain-settings "$keychain"
security import "$work/identity.p12" -k "$keychain" -f pkcs12 \
  -P "$transport" -T /usr/bin/codesign >/dev/null
# Let codesign use the key without asking.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$password" "$keychain" >/dev/null

hash=$(identity_hash)
[[ -n $hash ]] || {
  echo "signing-identity: the imported identity is not usable for code signing" >&2
  exit 1
}
echo "signing-identity: created \"$name\" ($hash) in $keychain"
