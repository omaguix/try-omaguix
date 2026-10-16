# One Omaguix release step

Supersedes [0004](0004-roguix-channel.md) on how a release is published;
0004's channel, key and `omaguix-update` still hold.

## Context

An Omaguix release had two independent halves. The omaguix channel got a signed
commit whenever `guest/guix/publish-channel` ran on the maintainer's Mac,
while `omaguix/omaguix`'s CI built substitutes from a try-omaguix commit pinned
in its workflow. Nothing tied them together: the channel lagged try-omaguix by
weeks, CI built modules no VM had, and a channel commit could reach VMs
before its packages were on `roguix.frolow.dev`, so `omaguix-update` would
compile Hyprland and Quickshell for hours or stop at its build gate. Four
scripts also decided, each in its own way, which items a server already
serves; only CI's checked licences and server answers.

## Decision

`guest/guix/release.py` publishes a release in one step, and the channel's
`main` moves only at its end:

1. `publish-channel` makes the signed channel commit C on top of the
   channel's `main` and pushes it to the branch `release/<C>`, not to `main`.
2. It dispatches CI's `build-desktop.yml` with `channel_commit=C`, takes the
   run id from the run URL `gh workflow run` prints, and waits with
   `gh run watch --exit-status`. CI checks out the channel at C,
   authenticates it like a VM, builds the reference system for aarch64 and
   x86_64, splits its closure with `scripts/desktop-split`, releases what
   neither server has, and uploads each architecture's lists as a run
   artifact naming C and the Guix pin.
3. For each architecture with a CI release, it has the VPS import that
   release (`scripts/vps-import TAG` over SSH), then checks that every item
   of both architectures' package closures is served by bordeaux or
   `roguix.frolow.dev`.
4. It writes `release.json` at the channel's root: C, the try-omaguix commit,
   the Guix pin, CI's repository, run id, URL and commit, and per
   architecture the release tag (or none: nothing new to export) and how
   many items bordeaux serves, `roguix.frolow.dev` serves and the release
   added. It commits that file signed as M, a child of C, checks that M
   changes nothing but `release.json`, pushes M to `main` as a fast-forward
   and deletes `release/<C>`.

The manifest lives in the channel, in a signed commit, because that is
where a VM already looks and what it already authenticates; it cannot be
inside C, since CI runs after C exists. Files outside `modules/` do not
enter the system, so M builds what CI built from C.

If any step fails (CI fails for either architecture, an artifact names
another commit or pin, an import fails, an item is served nowhere), the
script stops before step 4: `main` does not move, nothing is announced, VMs
keep the previous release, and `release/<C>` stays for inspection. A new
attempt starts again from `main`; CI then substitutes what the failed
attempt already imported. Two releases at once cannot both land: the second
push to `main` is not a fast-forward and fails.

`omaguix-update` authenticates and follows `main`, which now names only
released commits; since [0007](0007-move-vms-across-guix-pins.md) it also
checks that `main` is such a release commit (its parent is C, and M changes
nothing but `release.json`), and `release.json` names each architecture's
Guix for VMs that move to its pin.

The closure split is `omaguix/omaguix`'s `scripts/desktop-split`, with its
licence collector; try-omaguix's builder fallback (`server/publish-system.sh`)
runs the same two scripts at a pinned omaguix commit instead of its own awk.

## Alternatives

- The manifest as a GitHub release of omaguix-channel: not covered by the
  channel's signatures, and a second place a VM would have to trust.
- The manifest inside C: it cannot name the CI run that builds C.
- Pushing C to `main` and announcing the release separately: VMs follow
  `main`, so they would get C before its binaries, which is the problem.
- Moving the modules' source into omaguix-channel: one source, but the image
  build, its tests and the Mac app's guest contracts live in try-omaguix.
- Letting one architecture release alone: `main` is one commit for both;
  the other architecture's VMs would compile.

## Consequences

- A release needs the maintainer's Mac (the channel key), GitHub's CI and
  SSH to the VPS together; any of them down means no release, never a half
  one.
- CI no longer pins a try-omaguix commit; it builds what the channel names.
  Its push trigger builds the channel's `main`.
- The channel keeps one extra commit per release, and `release/*` branches
  of failed attempts until someone deletes them.
- A VM's own additions in `/etc/config.scm` are not in the reference system
  and may still compile.
- Items bordeaux serves today are not mirrored; if bordeaux drops one, a VM
  fetching it later compiles it.
- The builder VM fallback depends on omaguix's scripts at the commit it pins;
  moving that pin is a reviewed try-omaguix change.
