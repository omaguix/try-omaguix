# Move Omaguix VMs across Guix pins

Changes [0004](0004-roguix-channel.md)'s rule that `omaguix-update` refuses a
release on another Guix pin, and makes the VM check
[0006](0006-one-roguix-release-step.md)'s release commit.

## Context

An Omaguix VM reconfigures with the Guix that built its image, kept as the GC
root `/var/guix/gcroots/omaguix-guix`, so it reuses the image's derivations
and never compiles Guix. Its system pins that root again on every
reconfigure: `(omaguix system)`'s `pinned-guix` reads the root's own target.
So even when a newer Guix ran the reconfigure, the new system would point
the root back at the old Guix. `omaguix-update` therefore refused a release
whose `guix-commit` differed from the VM's and told the owner to reset the
VM, which erases it.

A test on 2026-10-12 moved a VM with `guix time-machine --commit=<new pin>`
run inside it. The move itself worked, but getting that Guix did not:
cloning Guix from `git.guix.gnu.org` (Codeberg) inside the VM broke off
twice with a connection reset while the same clone from the Mac succeeded,
a clone from a local mirror through libgit2 took 95 minutes, the checkout
takes 0.7 GiB, and no server had substitutes for the new commit's Guix, so
the VM had to compile it (about 2 hours).

## Decision

The release names the Guix it was built with, and the VM substitutes it.
That Guix is the pinned Guix G plus one small patch, so that the move needs
no Guix clone, and the VM's own descendant check replaces Guix's downgrade
check, which the patch lets it skip.

1. `modules/omaguix/guix-skip-forward-check.patch`, which travels in the
   channel commit, adds `--no-check-forward-update` to `guix system
   reconfigure`. Without the option nothing changes: `check-forward-update`
   runs and aborts a downgrade.
2. CI commits G plus that patch as G', pulls G' into a fresh profile P
   (`guix pull -p`), builds the reference system with `P/bin/guix`, and,
   for each architecture, publishes P (its canonical store path) and P's
   closure like the packages. Its artifact names P (`guix-profile.txt`), G'
   (`guix-patched-commit.txt`, what `P/bin/guix describe` reports) and the
   patch's SHA-256 (`guix-patch-sha256.txt`).
   While the channel's `modules/omaguix/guix-fork` names a commit F of a
   Guix fork (`URL COMMIT`), G' is F plus the patch: F carries a fix to
   Guix not yet released upstream, made in a fork under the maintainer's
   account with a regression test and offered upstream, as the
   maintainer's rule for bugs in code we do not own requires (decided
   2026-10-25 for Guix's builtin git download reading the host's Git
   configuration). CI checks that F's only parent is G; Guix's
   introduction authenticates G, and F is trusted because the signed
   channel commit names it. The runner's daemon is switched to P's, so its
   builtins run that fix. The file is removed once a pin that contains the
   fix upstream is adopted, which makes G' G plus the patch again.
3. `release.py` requires P to be a store item inside the package closure it
   checks is served, the patch's SHA-256 to be the channel's, and one G'
   for both architectures. `release.json` records P as
   `architectures.<system>.guix`, the patch (`guix-patch`: its file and
   SHA-256), F (`guix-fork`: its URL and commit, or null) and G'
   (`guix-patched-commit`). A release whose G does not
   descend from the previous release's G is refused: a newer channel
   release never names an older Guix. When the pin changed, a Guix clone
   on the maintainer's machine (`.env`'s `GUIX_CHECKOUT`) decides it with
   `git merge-base --is-ancestor`; the release step fetches nothing.
4. Every system records the commit of the channel's `main` it was built
   from as `/etc/omaguix/channel-commit`. Images are built from a published
   channel release: `build.py` refuses to build without
   `--channel-commit`, and `(omaguix system)` installs it from
   `OMAGUIX_CHANNEL_COMMIT`; `omaguix-update` sets that to the `main` it
   applies, and other reconfigures keep the running system's record.
5. `omaguix-update` authenticates the channel as before, then requires its
   `main` to be a release commit: one parent, the commit `release.json`
   names, a change to nothing but `release.json`, and the same Guix pin in
   both. It also requires `main` to descend (`git merge-base
   --is-ancestor` in the authenticated checkout) from the running system's
   own record, `/etc/omaguix/channel-commit`, which is the authority, and,
   when it exists, from the cursor `/var/lib/omaguix/channel-commit`, the
   newest `main` it applied; the cursor keeps `main` from going back to an
   older generation that `guix system roll-back` returned to. A missing or
   invalid record, or a `main` that is older or diverged, stops it without a
   change; an empty or garbled cursor is reported and ignored, so the record
   stands. After a successful reconfigure it moves the cursor forward (a
   unique temporary file in the same directory, flushed with `sync`, then a
   rename). A failed run keeps the cursor, and a crash between the
   activation and the cursor is harmless, because the new system's record
   already names its `main`. A lock (`flock` from util-linux on
   `/var/lib/omaguix/update.lock`) keeps a second run from starting
   meanwhile, and a missing `/etc/omaguix/modules/omaguix/guix-commit` or an
   unreadable free space stops it rather than counting as a move.
6. When the release's `guix-commit` differs from
   `/etc/omaguix/modules/omaguix/guix-commit`, it takes P for its own
   architecture (`uname -m`), checks it is a store item and that the store
   has a minimum of free space, roots it temporarily, realizes it from
   substitutes only (`ensure-path` through the VM's `guix repl`; a store
   path cannot be built, and `build-things` reports success for an item no
   server has), checks that `P/bin/guix describe` names G', and runs
   `P/bin/guix system reconfigure --no-check-forward-update` with
   `OMAGUIX_GUIX=P`. On the same pin it passes no such option.
   `pinned-guix` pins `OMAGUIX_GUIX` when it is set, and otherwise the root,
   as before. Activating the new generation points the root at P and
   `/etc/omaguix` at the release's modules.

Guix substitutes or builds the whole new system before it switches the
system profile, so a move that fails (no space, a missing substitute, a
network error) leaves the running system unchanged.

Rollback is the system's previous generation: `guix system roll-back` (the
menu's Update → Guix System → Roll back) activates it, which points the root
back at the old Guix and `/etc/omaguix` at the old modules, and makes it
GRUB's default; a reboot completes it, because until then
`/run/current-system` (and so the commands on `PATH`, `omaguix-update`
among them) stays the system that booted. Each generation references the Guix it pins, so
garbage collection keeps it while the generation exists. A later
`omaguix-update` moves again.

## Alternatives

- `guix time-machine --commit=<pin>` in the VM (tested first): every VM
  clones Guix from Codeberg and needs that commit's Guix substituted by
  someone, or compiles it for hours.
- `guix pull --commit` into a profile of its own: the same clone and Guix
  derivations, plus a profile with generations to manage.
- Pinning whatever Guix evaluates the system (`current-profile`): no
  variable, but a root that ran `guix pull` and then reconfigured would pin
  that pull's profile, which the next pull collects; the models consulted
  (rounds 20261012-131449-7da9 and 20261012-203546-a67f) preferred an
  explicit choice.
- Estimating the space a move needs from substitute narinfos: grafts and
  the owner's packages make it a guess, and Guix already fails before
  switching; a minimum guards against starting with too little.
- Mirroring P's whole closure on `roguix.frolow.dev` permanently, in case
  bordeaux drops an item: left to CI, under 0006's rule that only what no
  server serves is exported.
- Resetting the VM (the previous rule): loses the owner's data.
- Letting `check-forward-update` run on a move: it clones G's channel URL
  (Codeberg) into root's cache to relate the running system's provenance
  commit to the new one; `--allow-downgrades` changes only its verdict.
  Without that cache a test move spent 8224 s cloning a local mirror
  through libgit2, and the VM failed to clone Codeberg twice.
- A flag that upstream Guix already has: none skips that check (checked at
  7e74121a), so the patch adds one; the user decided on 2026-10-16
  (consult round 20261016-170251) to carry it rather than clone.
- Checking only the Guix commit's ancestry in the VM: the VM has no Guix
  history without the clone; the channel's history, which it has, stands in.

## Consequences

- A pin bump reaches existing VMs through a release, without compiling or
  cloning Guix in the VM; the VM needs P's closure from bordeaux or
  `roguix.frolow.dev` and about 0.5 GiB for it.
- CI must build P from G plus the patch, publish it and name it and G'; a
  release without P for an architecture cannot move that architecture's
  VMs to its pin, and `omaguix-update` says so. The patch must apply to
  each new pin; a pin bump that breaks it needs the patch refreshed first.
- The channel's history is the downgrade guard: a release that rewound
  `main`, or a channel history that diverged, is refused in every VM, and
  the release step keeps G moving forward along releases.
- An image without `/etc/omaguix/channel-commit` (any built before this
  decision) cannot update; nobody runs one yet.
- The VM trusts the signed `release.json` for "G' = G plus the patch"; CI
  verifies it when it builds P, and the VM only checks that P describes
  itself as G'.
- `GUIX_CHECKOUT` is the maintainer's local Guix clone, not something the
  release step fetches or checks for freshness.
- A VM picks P for its architecture by `uname -m`.
- Tested 2026-10-12/13 in a VM from the 7e74121 image, with a test channel
  and a P built in the VM at 84ff1865 (the next Guix commit): releases on
  the same pin, the move (29 s with root's Guix checkout cached), every
  generation referencing its Guix through `guix gc`, `guix system
  roll-back` plus a reboot back to the old Guix, a second move after it,
  and the moved system booting. Substitution of a plain store path was
  checked separately with an item from bordeaux.
- The move with the patched Guix and `--no-check-forward-update` has not
  run in a VM yet; the test above used an unpatched P.
- `release.json` now steers the VM, so it is checked there: a channel
  `main` that is not a release commit is never applied.
- The old Guix and the old system stay until the owner deletes old
  generations and collects garbage; a 24 GiB VM disk limits how many pins
  it can hold at once.
