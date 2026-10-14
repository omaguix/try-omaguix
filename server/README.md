# roguix.frolow.dev

The Roguix substitute server (docs/decisions/0002-roguix-substitute-server.md),
kept here until the VPS runs from its own Guix System configuration
(docs/decisions/0005-who-builds-roguix-substitutes.md), then deleted:
`guix publish` on a Debian 13 VPS behind nginx. It only serves; `omaguix/omaguix`'s CI
and the aarch64 builder VM build. The host also serves other sites, so `guix-publish.service`
is capped (one worker, `zstd:3`, `Nice=19`, idle I/O, one CPU, 700 MB).

## Files

- `guix-publish.service`: `/etc/systemd/system/guix-publish.service`.
- `roguix.frolow.dev.conf`: `/etc/nginx/conf.d/roguix.frolow.dev.conf`, as
  certbot left it.
- `roguix-prebake.sh`: bakes the publish cache one item at a time, so no
  guest request starts compression.

## Setup

1. `apt-get install uidmap`, then Guix with `guix-install.sh`
   (`https://guix.gnu.org/guix-install.sh`; it checks the release's signature).
2. `guix archive --generate-key`. The public key is
   `guest/guix/modules/roguix/roguix.frolow.dev.pub`; the secret key never
   leaves `/etc/guix/signing-key.sec`.
3. Install the unit and the nginx site, `nginx -t && systemctl reload nginx`,
   `systemctl enable --now guix-publish`, then
   `certbot --nginx -d roguix.frolow.dev --redirect`.
4. Authorize the builder's key: `guix archive --authorize <
   builder-signing-key.pub`.

## Publishing

A release is one step from the Mac, `guest/guix/release.py`
(docs/decisions/0006-one-roguix-release-step.md): `publish-channel` pushes the
signed channel commit to `release/<commit>`, `omaguix/omaguix`'s CI builds that
commit for aarch64 and x86_64, the VPS imports CI's releases with roguix's
`scripts/vps-import` over SSH (`VPS_IMPORT` in `.env`), every package item is
checked on bordeaux or roguix.frolow.dev, and a signed `release.json` on top
of the commit moves the channel's `main`. `--dry-run` prints the steps.

Only ungrafted items are published: grafts are built with
`#:substitutable? #f` (`guix/grafts.scm`), so a guest never asks a server for
them and grafts locally, which copies without compiling.

When CI cannot build, `publish-system.sh` does CI's aarch64 half in the
builder VM: it builds the reference system with the pinned Guix, runs roguix's
licence collector and `scripts/desktop-split` (fetched at the commit it pins)
on its closure, exports `publish.txt` and has `publish.sh` import it.
`publish.sh` has the VPS substitute `vps-fetch.txt` from bordeaux (an import
needs every reference valid), import the archive, and bake the cache with
`roguix-prebake.sh`, all under `nice` and idle I/O. A release made this way
still moves the channel with `release.py` once CI builds again.
