# Static substitutes at substitutes.omaguix.org

Supersedes [0002](0002-roguix-substitute-server.md) and
[0005](0005-who-builds-roguix-substitutes.md) on which server and key guests
trust.

## Context

Guests trusted `guix publish` on `roguix.frolow.dev`, which held its signing
key on the VPS. The owner decided on 2026-10-12 that CI signs substitutes with
a key kept only in a GitHub environment secret and the VPS serves a static
tree (omaguix/omaguix decision 0001), with a clean cutover and no backfill
because nobody uses the old server yet, and on 2026-10-14 that the domain is
`omaguix.org`. omaguix/omaguix 5cb6692 makes CI build, sign and release the
tree for the channel commit a release names.

## Decision

`%omaguix-trust` names only `https://substitutes.omaguix.org` and
`modules/omaguix/substitutes.omaguix.org.pub` (SHA-256
`5e9b4547f9a8409a42e658276deb6e3f4502f6715681a9617f8b105ea73b4f2a`), from the
first release through `guest/guix/release.py` on. That release's channel
commit carries the new record (the owner, 2026-10-25): the channel's `main`
moves only after CI signed with the key whose public half is this file, the
VPS imported the release and every package item was found served.
`roguix.frolow.dev.pub` leaves the repository.

## Alternatives

- A release that trusts both keys: rejected by the owner (2026-10-12),
  a clean cutover instead.
- A first release on the old record and a second one that switches: two
  multi-hour runs, and the first release's guests could not verify the new
  substitutes (the owner, 2026-10-25).

## Consequences

A guest made before this release keeps the old record in its running
daemon: `omaguix-update` across this release asks the old server, trusts only
the old key, and with `--max-jobs=0` refuses to build what it cannot
substitute, so the update fails (consult round 20261025-125554-cd3c). Such a
guest first authorizes the new key, `modules/omaguix/substitutes.omaguix.org.pub`
of the authenticated channel commit it updates to, with
`sudo guix archive --authorize`, or is made again from a new image. The builder VM builds
without `--max-jobs=0`, so it compiles what it cannot substitute. `server/` describes the
old `guix publish` host until roguix-vps switches it off. Guix has no key
revocation: the old key is erased on the VPS, not revoked.
