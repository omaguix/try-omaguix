# Roguix signing keys

A Roguix VM trusts two keys beyond Guix's own (`%roguix-trust` in
`guest/guix/modules/roguix/trust.scm`): the roguix channel's OpenPGP key
(decision 0004) and the substitute server's `guix publish` key (decision
0002). This page is the owner's procedure for both; agents prepare the
repository side but never create or hold these keys.

## Channel recovery key

Every roguix channel commit must be signed by a key listed in the parent
commit's `.guix-authorizations`. Today that is only the channel key
(`7D1A 8B40 0C26 0998 097F  63E5 28B8 3B16 11FA 815E`), which has no
passphrase so `publish-channel` runs unattended. If it is lost, no new commit
can authenticate and every VM's `roguix-update` stops at the old head. A
second, offline key authorized now is the way back; it cannot be added after
the main key is gone.

### Create and keep the recovery key

1. On a machine with no network (for example a live system booted from USB),
   with the key's home on an encrypted USB drive:

   ```sh
   export GNUPGHOME=/media/<usb>/roguix-recovery/gnupg
   mkdir -p -m 700 "$GNUPGHOME"
   gpg --quick-generate-key 'Roguix channel recovery key' ed25519 sign never
   gpg --list-keys --with-fingerprint     # note the fingerprint, <RECOVERY>
   gpg --armor --export <RECOVERY> > /media/<usb>/roguix-recovery/recovery.key
   ```

   Give it a strong passphrase, unlike the channel key.
2. Copy `roguix-recovery/` to a second encrypted drive kept in another place,
   and optionally print the secret key with `paperkey`. Keep the passphrase
   in the owner's password manager. The secret key never goes onto the Mac's
   disk or into `~/.config/roguix-channel/gnupg`.
3. Take only `recovery.key` (the public key) back to the Mac.

### Authorize it in roguix-channel

In the roguix channel checkout (`ROGUIX_CHANNEL_DIR`, by default
`../roguix-channel`), with the current channel key:

```sh
export GNUPGHOME=~/.config/roguix-channel/gnupg
git switch keyring
cp <path>/recovery.key recovery.key
git add recovery.key
git commit -m "Add the recovery key"
git switch main
```

Add the recovery key to `.guix-authorizations`, next to the existing entry
(fingerprint with spaces, as `gpg` prints it):

```scheme
(authorizations
 (version 0)
 (("7D1A 8B40 0C26 0998 097F  63E5 28B8 3B16 11FA 815E"
   (name "roguix"))
  ("<RECOVERY>"
   (name "roguix-recovery"))))
```

Commit it signed with the channel key, check the chain, then push:

```sh
git commit --gpg-sign -m "Authorize the recovery key" .guix-authorizations
guix git authenticate --keyring=keyring \
  bcc938512706d19de86dd8c6f50853fa80b063b8 \
  '7D1A 8B40 0C26 0998 097F  63E5 28B8 3B16 11FA 815E'
git push origin main keyring
```

`publish-channel` only replaces `system.scm` and `modules/roguix/`, so later
releases keep this commit's `.guix-authorizations`.

### Use it when the channel key is lost

1. Make a new channel key on the Mac the way the current one was made
   (its own `GNUPGHOME`, no passphrase, ed25519, sign only), and add its
   public key to the `keyring` branch as above (`roguix-2.key`).
2. On `main`, edit `.guix-authorizations`: remove the lost key and add the
   new one; keep the recovery key.
3. Sign that commit with the recovery key: attach the recovery drive
   (network off), set `GNUPGHOME` to its `gnupg`, and run
   `git commit -S<RECOVERY> -m "Replace the lost channel key"`. The recovery
   key is authorized in the parent commit, so the commit authenticates.
   Detach the drive.
4. Run the `guix git authenticate` check above and push `main` and
   `keyring`. Point `publish-channel` at the new key with `GNUPGHOME`.

The channel introduction (`bcc93851…` signed by `7D1A…`) names who signed
the first commit, not who signs now, so `%roguix-trust` and every VM keep it
unchanged. If the key was stolen rather than lost, do the same at once, and
compare the channel's history with the release step's commits ("Roguix from
try-roguix <revision>", each followed by "Release <commit>" with
`release.json`) for any commit nobody made.

## Keeping the publish key off the serving host

### Today

`guix publish` on the VPS behind roguix.frolow.dev signs every `.narinfo`
with `/etc/guix/signing-key.sec`, so the key sits on a network-facing host
that also serves other sites. Whoever gets root there can sign code that
every Roguix VM installs.

### Options

1. **Sign on the builder, serve static files.** The aarch64 builder, which
   already builds every item, runs `guix publish` locally with its own
   signing key and `--cache`, bakes the cache for the release's items, and
   the release step copies the cache (`.narinfo` files and `nar/`) to the VPS,
   where nginx serves it as static files. The VPS holds no signing key and
   runs no Guix daemon for serving. Also removes on-demand compression on
   the VPS (the overload in decision 0002), and the same files can later sit
   behind a CDN unchanged.
2. **Keep `guix publish` on the VPS, harden the host.** A separate VM or
   container for `guix publish`, the key readable only by its user. Narrows
   the exposure but the key stays on the serving host.
3. **Remote signing service.** `guix publish` has no external-signer
   interface, so this means patching Guix. Rejected.
4. **Object storage or a CDN as origin.** Option 1 with another host for the
   files; the signing location is the same, so it is a later step of
   option 1, not an alternative.

### Recommendation: option 1

It is the only option that removes the key from the host, and it fits the
release step that already runs on the builder (`server/README.md`). Open
points before any host change:

- Check that `guix publish --cache`'s directory serves correctly as static
  files (URL layout, `Content-Type`, `nix-cache-info`) with
  `guix weather --substitute-urls=https://roguix.frolow.dev` from a guest.
- Choose the key: a new publish key held only in the builder VM (backed up
  offline like the channel recovery key) rather than the builder's existing
  archive key, so the two roles can be rotated separately.
- The key change reaches VMs through `%roguix-trust`: a channel release that
  authorizes both the old and the new key, the switch of what the VPS serves,
  then a release that drops the old key. Authorizing two keys for one
  transition is compatibility under the project's policy and needs the
  owner's approval with a removal date; new images carry only the new key.
- After the switch, delete `/etc/guix/signing-key.sec` from the VPS and
  disable its `guix-publish.service`.
