#!/bin/bash

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: macos/build-app.sh [--open] [--dmg] [--guest-dir DIR] [--output-dir DIR]
                                  [--configuration development|production]
                                  [--sign-identity IDENTITY]
                                  [--notarize-profile PROFILE]
                                  [--download-disk-from URL]

Build a self-contained Apple Silicon app. Development builds select a stable
local signing certificate automatically. Production builds require an explicit
signing identity. --dmg requires --configuration production.
OMARCHY_CODESIGN_IDENTITY gives a default identity; OMARCHY_CODESIGN_KEYCHAIN
names the keychain of the local development identity (`make app`), which is
signed without the hardened runtime.
--notarize-profile implies --dmg and names a notarytool keychain profile.
--download-disk-from builds a release app without the compressed disk: it
downloads the disk's parts from URL (ending in /) on the first launch
(docs/releasing.md).
EOF
  exit 64
}

open_app=0
build_dmg=0
guest_dir=
configuration=development
output_dir=
sign_identity=${OMARCHY_CODESIGN_IDENTITY:-auto}
sign_keychain=${OMARCHY_CODESIGN_KEYCHAIN:-}
notarize_profile=
download_disk_from=
# GitHub release assets are limited to 2 GiB; parts stay safely below it.
disk_part_bytes=1992294400
while (($#)); do
  case "$1" in
    --open) open_app=1; shift ;;
    --dmg) build_dmg=1; shift ;;
    --configuration)
      (($# >= 2)) || usage
      configuration=$2
      shift 2
      ;;
    --guest-dir)
      (($# >= 2)) || usage
      guest_dir=$2
      shift 2
      ;;
    --output-dir)
      (($# >= 2)) || usage
      output_dir=$2
      shift 2
      ;;
    --sign-identity)
      (($# >= 2)) || usage
      sign_identity=$2
      shift 2
      ;;
    --notarize-profile)
      (($# >= 2)) || usage
      notarize_profile=$2
      build_dmg=1
      shift 2
      ;;
    --download-disk-from)
      (($# >= 2)) || usage
      download_disk_from=$2
      [[ $download_disk_from =~ ^https://[^[:space:]]+/$ ]] || usage
      shift 2
      ;;
    *) usage ;;
  esac
done

macos_major=$(sw_vers -productVersion | cut -d. -f1)
[[ $macos_major =~ ^[0-9]+$ ]] && (( macos_major >= 15 )) || {
  echo "build-app: macOS 15 or newer is required" >&2
  exit 1
}

macos_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(cd "$macos_dir/.." && pwd -P)
# The app's names and identifiers: macos/apps/try-omaguix.env, or the file
# APP_IDENTITY names (macos/README.md, "App identity").
app_identity=$(python3 "$macos_dir/apps/identity.py" shell)
eval "$app_identity"
case "$configuration" in
  development)
    bundle_identifier=$DEVELOPMENT_BUNDLE_IDENTIFIER
    app_display_name=$DEVELOPMENT_APP_NAME
    (( build_dmg == 0 )) || {
      echo 'build-app: --dmg requires --configuration production' >&2
      exit 1
    }
    sign_identity=$(python3 "$macos_dir/development-sign-identity.py" "$sign_identity")
    ;;
  production)
    bundle_identifier=$BUNDLE_IDENTIFIER
    app_display_name=$APP_NAME
    [[ $sign_identity != auto ]] || {
      echo 'build-app: production requires --sign-identity (use - for an explicit ad-hoc test build)' >&2
      exit 1
    }
    ;;
  *) usage ;;
esac
helper="$macos_dir/.build/release/omarchy-vm-helper"
# Development and release builds each get their own .noindex directory, so
# building one never rewrites a bundle that is running from the other.
if [[ -z $output_dir ]]; then
  output_dir="$repo_dir/build/dev.noindex"
  [[ $configuration != production ]] || output_dir="$repo_dir/build/release.noindex"
fi
mkdir -p "$output_dir" && output_dir=$(cd "$output_dir" && pwd -P) || {
  echo "build-app: cannot use output directory $output_dir" >&2
  exit 1
}
app="$output_dir/$APP_NAME.app"
contents="$app/Contents"
# QEMU owns the VM window, so it runs from a nested helper app: the window
# then has its own bundle identifier, and a Dock tile pinned while the VM ran
# launches the helper, which hands that launch to this app.
vm_app="$contents/Helpers/$APP_NAME.app"
vm_bundle_identifier="$bundle_identifier.vm"
bundled_qemu="$vm_app/Contents/MacOS/$APP_NAME"
module_cache="$macos_dir/.build/module-cache"
runtime_source="$macos_dir/.build/qemu-gpu-runtime"
guest_dir=${guest_dir:-"$repo_dir/build/guix"}
dependency_bundler="$macos_dir/bundle-macho-dependencies.sh"
compatibility_verifier="$macos_dir/verify-macos-compatibility.sh"
package_dmg="$macos_dir/package-dmg.sh"
# The identity's ICON, an SVG beside the identity file.
app_icon_source=$(python3 "$macos_dir/apps/identity.py" icon)
app_icon_name=${ICON%.svg}
app_icon_renderer_source="$macos_dir/render-app-icon.swift"
app_icon_packer="$macos_dir/pack-app-icon.py"
icon_renderer="$macos_dir/.build/app-icon-renderer"
iconset="$macos_dir/.build/$app_icon_name.iconset"
generated_icon="$macos_dir/.build/$app_icon_name.icns"

[[ -d $runtime_source && ! -L $runtime_source ]] || {
  echo "build-app: missing staged QEMU runtime; run build-qemu-gpu-runtime.sh first" >&2
  exit 1
}
[[ -d $guest_dir && ! -L $guest_dir ]] || {
  echo "build-app: missing factory guest directory: $guest_dir" >&2
  exit 1
}
guest_dir=$(cd "$guest_dir" && pwd -P)
[[ -x $dependency_bundler && ! -L $dependency_bundler ]] || {
  echo "build-app: dependency bundler is missing or unsafe" >&2
  exit 1
}
[[ -x $compatibility_verifier && ! -L $compatibility_verifier ]] || {
  echo "build-app: compatibility verifier is missing or unsafe" >&2
  exit 1
}
[[ -f $app_icon_source && ! -L $app_icon_source ]] || {
  echo "build-app: app icon source is missing or unsafe" >&2
  exit 1
}
[[ -f $app_icon_renderer_source && ! -L $app_icon_renderer_source ]] || {
  echo "build-app: app icon renderer is missing or unsafe" >&2
  exit 1
}
[[ -f $app_icon_packer && ! -L $app_icon_packer ]] || {
  echo "build-app: app icon packer is missing or unsafe" >&2
  exit 1
}
for tool in python3 sips xcrun; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "build-app: $tool is required to render the app icon" >&2
    exit 1
  }
done
if [[ -n $notarize_profile && $sign_identity == - ]]; then
  echo "build-app: notarization requires --sign-identity with a Developer ID Application identity" >&2
  exit 1
fi
[[ -x $runtime_source/bin/zstd && ! -L $runtime_source/bin/zstd ]] || {
  echo "build-app: staged runtime is missing pinned zstd" >&2
  exit 1
}

IFS=, read -r -a legacy_app_names <<<"$LEGACY_APP_NAMES"
for legacy_app_name in ${legacy_app_names[@]+"${legacy_app_names[@]}"}; do
  legacy_app="$repo_dir/dist/$legacy_app_name.app"
  if [[ -e $legacy_app || -L $legacy_app ]]; then
    lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    if [[ -x $lsregister ]]; then
      "$lsregister" -u "$legacy_app" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$legacy_app"
  fi
done
mkdir -p "$output_dir"
# A .noindex container is the supported per-directory Spotlight exclusion.
# Removing and unregistering the legacy bundle above also prevents a previously
# indexed build at the old path from surviving this migration.
cd "$macos_dir"
mkdir -p "$module_cache/swift" "$module_cache/clang" "$module_cache/icon"
export SWIFT_MODULECACHE_PATH="$module_cache/swift"
export CLANG_MODULE_CACHE_PATH="$module_cache/clang"
export MACOSX_DEPLOYMENT_TARGET=15.0
swift build --disable-sandbox -c release -debug-info-format none

rm -rf "$iconset"
rm -f "$generated_icon"
mkdir "$iconset"
xcrun swiftc \
  -module-cache-path "$module_cache/icon" \
  -framework AppKit \
  "$app_icon_renderer_source" \
  -o "$icon_renderer"
"$icon_renderer" "$app_icon_source" "$iconset/icon_512x512@2x.png"
while IFS=$'\t' read -r icon_name icon_pixels; do
  sips \
    -z "$icon_pixels" "$icon_pixels" \
    "$iconset/icon_512x512@2x.png" \
    --out "$iconset/$icon_name" >/dev/null
done <<'ICON_SIZES'
icon_16x16.png	16
icon_16x16@2x.png	32
icon_32x32.png	32
icon_32x32@2x.png	64
icon_128x128.png	128
icon_128x128@2x.png	256
icon_256x256.png	256
icon_256x256@2x.png	512
icon_512x512.png	512
ICON_SIZES
python3 "$app_icon_packer" "$iconset" "$generated_icon"
[[ -f $generated_icon && ! -L $generated_icon ]] || {
  echo "build-app: generated app icon is missing or unsafe" >&2
  exit 1
}

rm -rf "$app"
mkdir -p \
  "$contents/MacOS" \
  "$contents/Resources/guest" \
  "$contents/Resources/runtime/bin" \
  "$contents/Resources/scripts" \
  "$vm_app/Contents/MacOS" \
  "$vm_app/Contents/Resources"
# Bridged networking needs the privileged helper; an identity without
# NETWORK_HELPER_SERVICE ships none and offers only NAT.
if [[ -n $NETWORK_HELPER_SERVICE ]]; then
  bash "$macos_dir/network-helper/build.sh" "$contents/Resources/network" \
    "$NETWORK_HELPER_SERVICE"
  mkdir -p "$contents/Library/LaunchDaemons"
  python3 - "$macos_dir/network-helper/launch-daemon.plist" \
    "$contents/Library/LaunchDaemons/$NETWORK_HELPER_SERVICE.plist" \
    "$NETWORK_HELPER_SERVICE" <<'PYTHON'
import plistlib, sys
from pathlib import Path
value = plistlib.loads(Path(sys.argv[1]).read_bytes())
value["Label"] = sys.argv[3]
value["MachServices"] = {sys.argv[3]: True}
Path(sys.argv[2]).write_bytes(plistlib.dumps(value))
PYTHON
  chmod 0644 "$contents/Library/LaunchDaemons/$NETWORK_HELPER_SERVICE.plist"
  install -m 0644 "$macos_dir/network-helper/vendor/LICENSE" "$contents/Resources/network/LICENSE.socket_vmnet"
fi
install -m 0755 "$helper" "$contents/MacOS/omarchy-vm-helper"
install -m 0644 "$macos_dir/Info.plist" "$contents/Info.plist"
python3 - "$contents/Info.plist" "$bundle_identifier" "$app_display_name" \
  "$APPLICATION_SUPPORT_DIRECTORY" "$LOGS_DIRECTORY" "$APP_NAME" \
  "$DEVELOPMENT_APP_NAME" "$NETWORK_HELPER_SERVICE" "$app_icon_name.icns" \
  "$RELEASE_REPOSITORY" "$RELEASE_TAG_PREFIX" "$RELEASE_DMG" "$LEGACY_RELEASE_DMGS" <<'PYTHON'
import plistlib, sys
from pathlib import Path
path = Path(sys.argv[1])
value = plistlib.loads(path.read_bytes())
value["CFBundleIdentifier"] = sys.argv[2]
value["CFBundleName"] = value["CFBundleDisplayName"] = sys.argv[3]
value["CFBundleIconFile"] = sys.argv[9]
# The privacy descriptions name the app.
for key, text in value.items():
    if key.endswith("UsageDescription"):
        value[key] = text.replace("{APP_NAME}", sys.argv[6])
if "{APP_NAME}" in plistlib.dumps(value).decode():
    raise SystemExit("build-app: Info.plist has an unexpanded {APP_NAME}")
# The app identity the app and its launcher read at run time
# (macos/README.md, "App identity"): the directories under
# ~/Library/Application Support and ~/Library/Logs that hold this app's VM and
# logs, the app's names (the VM helper app is named after the production
# name), the bridged-networking helper's service, empty without one, and
# where the update check finds this app's releases.
value["RoguixApplicationSupportDirectory"] = sys.argv[4]
value["RoguixLogsDirectory"] = sys.argv[5]
value["RoguixApplicationName"] = sys.argv[6]
value["RoguixDevelopmentApplicationName"] = sys.argv[7]
value["RoguixNetworkHelperService"] = sys.argv[8]
value["RoguixReleaseRepository"] = sys.argv[10]
value["RoguixReleaseTagPrefix"] = sys.argv[11]
value["RoguixReleaseDMG"] = sys.argv[12]
value["RoguixLegacyReleaseDMGs"] = sys.argv[13]
path.write_bytes(plistlib.dumps(value))
PYTHON
python3 "$repo_dir/scripts/app_version.py" \
  --root "$repo_dir" --plist "$contents/Info.plist"
install -m 0644 "$macos_dir/Credits.rtf" "$contents/Resources/Credits.rtf"
install -m 0644 "$repo_dir/LICENSE" "$contents/Resources/LICENSE"
install -m 0644 "$generated_icon" "$contents/Resources/$app_icon_name.icns"
install -m 0644 "$generated_icon" "$vm_app/Contents/Resources/$app_icon_name.icns"
# The helper shares the app's version, icon and privacy descriptions; only its
# executable, identifier and name differ.
python3 - "$contents/Info.plist" "$vm_app/Contents/Info.plist" "$vm_bundle_identifier" \
  "$APP_NAME" <<'PYTHON'
import plistlib, sys
from pathlib import Path
value = plistlib.loads(Path(sys.argv[1]).read_bytes())
value["CFBundleExecutable"] = sys.argv[4]
value["CFBundleIdentifier"] = sys.argv[3]
value["CFBundleName"] = value["CFBundleDisplayName"] = sys.argv[4]
# QEMU makes itself a foreground app when it opens the VM window; a launch
# from a pinned Dock tile only opens the app and exits, without a Dock icon.
value["LSUIElement"] = True
Path(sys.argv[2]).write_bytes(plistlib.dumps(value))
PYTHON
ditto "$runtime_source" "$contents/Resources/runtime"
install -m 0755 "$macos_dir/run-qemu-gpu.sh" "$contents/Resources/scripts/run-qemu-gpu.sh"
install -m 0644 "$macos_dir/qemu-persistent-storage.sh" \
  "$contents/Resources/scripts/qemu-persistent-storage.sh"
install -m 0644 "$macos_dir/qemu-port-forwarding.sh" \
  "$contents/Resources/scripts/qemu-port-forwarding.sh"
install -m 0644 "$macos_dir/qemu-networking.sh" "$contents/Resources/scripts/qemu-networking.sh"
install -m 0644 "$macos_dir/network-identity.py" "$contents/Resources/scripts/network-identity.py"
# The Roguix guest directory (guest/guix/package.py) holds exactly its
# manifest, checksums and compressed UEFI disk.
guest_resources=(SHA256SUMS disk.raw.zst guix-manifest.json)
install -m 0644 "$repo_dir/guest/guix/artifact.py" \
  "$contents/Resources/scripts/guix-artifact.py"
for guest_resource in "${guest_resources[@]}"; do
  [[ -f $guest_dir/$guest_resource && ! -L $guest_dir/$guest_resource ]] || {
    echo "build-app: factory guest resource is missing or unsafe: $guest_resource" >&2
    exit 1
  }
  if [[ $guest_resource == *.zst ]]; then
    cp -c "$guest_dir/$guest_resource" "$contents/Resources/guest/$guest_resource"
  else
    cp "$guest_dir/$guest_resource" "$contents/Resources/guest/$guest_resource"
  fi
  chmod 0644 "$contents/Resources/guest/$guest_resource"
done

mv "$contents/Resources/runtime/bin/qemu-system-aarch64" "$bundled_qemu"
"$dependency_bundler" --verify-only "$contents/Resources/runtime"
# The helper's executable loads the runtime's libraries from the main bundle.
runtime_lib_from_qemu='@executable_path/../../../../Resources/runtime/lib'
while IFS= read -r dependency; do
  case "$dependency" in
    @executable_path/../lib/*)
      install_name_tool -change "$dependency" \
        "$runtime_lib_from_qemu/${dependency##*/}" "$bundled_qemu"
      ;;
  esac
done < <(otool -L "$bundled_qemu" | sed -n '2,$p' | \
  sed -E 's/^[[:space:]]+//; s/ \(compatibility version.*$//')
install_name_tool -rpath '@executable_path/../lib' "$runtime_lib_from_qemu" \
  "$bundled_qemu"
while IFS= read -r dependency; do
  case "$dependency" in
    /System/Library/*|/usr/lib/*) ;;
    "$runtime_lib_from_qemu"/*)
      [[ -f $contents/Resources/runtime/lib/${dependency##*/} ]] || {
        echo "build-app: QEMU needs a missing runtime library: $dependency" >&2
        exit 1
      }
      ;;
    *)
      echo "build-app: QEMU has an external dependency: $dependency" >&2
      exit 1
      ;;
  esac
done < <(otool -L "$bundled_qemu" | sed -n '2,$p' | \
  sed -E 's/^[[:space:]]+//; s/ \(compatibility version.*$//')

sign_options=(--force --sign "$sign_identity")
if [[ -n $sign_keychain ]]; then
  # The local self-signed identity has no Team ID, so the hardened runtime's
  # library validation would reject the bundled dylibs; it is never notarized,
  # which is what the hardened runtime and timestamp are for.
  sign_options+=(--keychain "$sign_keychain")
elif [[ $sign_identity != - ]]; then
  sign_options+=(--options runtime)
  if [[ $configuration == production ]]; then
    sign_options+=(--timestamp)
  else
    # Local rebuilds need a stable identity, not a distribution timestamp.
    # Explicitly disable it: Developer ID identities otherwise request one
    # by default, including when selected as a development fallback.
    sign_options+=(--timestamp=none)
  fi
fi
app_sign_options=("${sign_options[@]}" --identifier "$bundle_identifier")
for library in "$contents/Resources/runtime/lib"/*.dylib; do
  codesign "${sign_options[@]}" "$library"
done
codesign "${sign_options[@]}" "$contents/Resources/runtime/bin/zstd"
if [[ -n $NETWORK_HELPER_SERVICE ]]; then
  for network_binary in socket_vmnet omarchy-network-supervisor omarchy-network-client; do
    codesign "${sign_options[@]}" "$contents/Resources/network/$network_binary"
  done
fi
# QEMU's event tap uses the app's Accessibility grant. Its code identifier
# stays the app's, as it was before the helper bundle, so the code identity
# privacy grants see does not change; the bundle identifier (Dock, Command-Tab,
# key remappers) is the helper's own.
codesign "${sign_options[@]}" --identifier "$bundle_identifier" \
  --entitlements "$macos_dir/qemu-hvf.entitlements" \
  "$vm_app"

if [[ -n $NETWORK_HELPER_SERVICE ]]; then
  bash "$macos_dir/network-helper/build-daemon.sh" "$contents" "$NETWORK_HELPER_SERVICE"
  codesign "${sign_options[@]}" "$contents/MacOS/omarchy-network-daemon"
fi
codesign "${app_sign_options[@]}" \
  --entitlements "$macos_dir/omarchy-vm-helper.entitlements" \
  "$contents/MacOS/omarchy-vm-helper"

launch_record=$(OMARCHY_QEMU_GPU_INSPECT_ONLY=1 \
  "$contents/Resources/scripts/run-qemu-gpu.sh")
IFS=$'\t' read -r bundle_identity source_disk_sha source_disk_bytes \
  compressed_disk_bytes working_disk_bytes guest_locales <<<"$launch_record"
launch_configuration="$contents/Resources/guest/launch.plist"
/usr/bin/plutil -create xml1 "$launch_configuration"
/usr/bin/plutil -insert bundleIdentity -string "$bundle_identity" "$launch_configuration"
/usr/bin/plutil -insert sourceDiskSHA256 -string "$source_disk_sha" "$launch_configuration"
/usr/bin/plutil -insert sourceDiskBytes -integer "$source_disk_bytes" "$launch_configuration"
/usr/bin/plutil -insert compressedDiskBytes -integer "$compressed_disk_bytes" "$launch_configuration"
/usr/bin/plutil -insert workingDiskBytes -integer "$working_disk_bytes" "$launch_configuration"
# Firmware boots the guest's own GRUB from the disk.
/usr/bin/plutil -insert bootABI -string uefi-gpt-v1 "$launch_configuration"
# Comma-separated optional guest languages, or "-" for none.
/usr/bin/plutil -insert guestLocales -string "$guest_locales" "$launch_configuration"
/usr/bin/plutil -insert compressedDiskSHA256 -string \
  "$(/usr/bin/plutil -extract disk.compressedSHA256 raw "$guest_dir/guix-manifest.json")" \
  "$launch_configuration"
if [[ -n $download_disk_from ]]; then
  /usr/bin/plutil -insert diskDownloadBase -string "$download_disk_from" "$launch_configuration"
  /usr/bin/plutil -insert diskDownloadPartBytes -integer "$disk_part_bytes" "$launch_configuration"
  rm -f "$contents/Resources/guest/disk.raw.zst"
fi

codesign "${app_sign_options[@]}" \
  --entitlements "$macos_dir/omarchy-vm-helper.entitlements" \
  "$app"
codesign --verify --deep --strict --verbose=2 "$app"
"$compatibility_verifier" "$app"

echo "[native] Built $app"
if (( build_dmg )); then
  app_version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$contents/Info.plist")
  dmg="$output_dir/${RELEASE_DMG%.dmg}-v${app_version}.dmg"
  rm -f "$dmg"
  package_options=()
  if [[ $sign_identity != - ]]; then
    package_options+=(--sign-identity "$sign_identity")
  fi
  if [[ -n $notarize_profile ]]; then
    package_options+=(--notarize-profile "$notarize_profile")
  fi
  if ((${#package_options[@]})); then
    "$package_dmg" "${package_options[@]}" "$app" "$dmg"
  else
    "$package_dmg" "$app" "$dmg"
  fi
fi
if (( open_app )); then
  open "$app"
fi
