# TODO

## Next, in order

- [ ] First Omaguix release through release.py [t-omarelfs]
  Decided by the user 2026-10-12 (d-evsasl4e): "yes, after the upgrade
  path" item. Set `VPS_IMPORT=/usr/local/sbin/vps-import` in the local
  `.env`, then run guest/guix/release.py for current try-omaguix main: a
  signed omaguix-channel commit, omaguix/omaguix's build-desktop.yml
  dispatched with `channel_commit` (aarch64 and x86_64, hours), VPS import,
  the closure check, then the signed release.json moves the channel's main.
  Report the run ids and the release commit; on any failure, main stays.
  Checked 2026-10-14 (consult round 20261014-193606-be7d with sol, MiMo,
  DeepSeek): before running `guest/guix/release.py`:
  1. In `omaguix/omaguix` `.github/workflows/build-desktop.yml`:
     - Fix `sign-substitutes`'s `if:` gate (`github.actor == github.repository_owner`
       is false when a maintainer dispatches `workflow_dispatch` in the
       `omaguix` organization, skipping signing).
     - Populate `split-<prefix>/release-tag.txt` when `publish.txt` is non-empty
       (currently `: > split/release-tag.txt` is uploaded empty before
       `sign-substitutes` computes `RELEASE_TAG`, which `release.py` rejects).
     - Emit `split-<prefix>/guix-profile.txt` and include the Guix profile in
       `package-closure.txt` (required by decision 0007 / `[t-omaupgrd]`).
  2. Complete the `omaguix.org` / `substitutes.omaguix.org` cutover prerequisites
     (`[t-omabkfil]`, `[t-omaorgdm]`, `[t-omakeyfr]` below) and switch
     `guest/guix/modules/roguix/trust.scm` to `https://substitutes.omaguix.org`
     and `substitutes.omaguix.org.pub` once signed substitute content is verified.
  This release carries `codex-bin` 0.163.0 (5ba9227a, [t-fjlrfmnx], closed):
  send its released channel commit to the guix-x86_64-iso-omguix session
  (guix-x86-64-iso-omguix-86), which asked for it. Its x86_64 build was not
  run on the aarch64 builder (no emulation), so CI builds it first here;
  untested: the sandbox inside an Omaguix guest and `codex exec` after login.
  Gate from [t-omaupgrd] (d-qqlris3g): omaguix/omaguix's workflow builds
  P from upstream G plus try-roguix's forward-check patch, and the release
  names the patched commit.
  Both waiting coordinators rechecked it on 2026-10-18 and were answered:
  guix-x86_64-iso-omguix (pane w6R:p6W) waits for the released channel
  commit for its items 28 (Codex CLI) and 29 (Claude Code through the
  shim); roguix-vps (pane w1E:p42) reports substitutes.omaguix.org serving
  HTTPS with a valid Let's Encrypt certificate and a 404 `nix-cache-info`
  because `/var/lib/roguix-substitutes` is empty, with the old
  roguix.frolow.dev still serving 200 from `guix publish`. Both need main
  to move, which this item does; nothing on the VPS changes before the
  first release run. The substitutes public key they need is already
  published: `guest/guix/modules/roguix/substitutes.omaguix.org.pub`
  (SHA-256 5e9b4547f9a8409a42e658276deb6e3f4502f6715681a9617f8b105ea73b4f2a)
  on try-omaguix main and in the signed channel branch
  `release/cba50b560a38ac885b3d282f132793fe740345f6`.
  x86_64 verified 2026-10-16 on the 2010 MacBook (pane worker codex-x86):
  `codex-bin` built under the Roguix pin 7e74121a
  (/gnu/store/wq2s2lnl...-codex-0.163.0), `codex --version` prints
  codex-cli 0.163.0, and `codex sandbox` ran unprivileged with the store's
  bwrap (not setuid) with writes blocked.
  With the release, tell the guix-x86_64-iso-omguix coordinator the released
  channel commit that carries `x86-64-v2-sigill-shim` and
  `claude-code-x86-64-v1` (t-dopemmpz, landed 2026-10-25 as 0bbddcd2 and
  7a70072b: built at the pin on the Core 2 Duo P8600, the shim's `make check`
  passed with the trap tests, `bin/claude --version` printed 2.1.301; that
  coordinator's session was not running to be told).
  With the release, also tell roguix-vps that t-omabkfil (the store paths
  server/publish.sh published) is closed as superseded: omaguix/omaguix
  decision 0001 (be56772, the user 2026-10-12) has no backfill, so nothing
  on the VPS waits on a list from here.
  Blocked 2026-10-25 (checked against omaguix/omaguix main 09d6aa1): its
  build-desktop.yml still has the `github.actor == github.repository_owner`
  gate on sign-substitutes (line 203), still uploads an empty
  release-tag.txt (line 143) and emits no guix-profile.txt. That CI change
  is item 30c (t-guixprof) of the guix-x86_64-iso-omguix coordinator, whose
  worker never started (usage gate, run r-7opekqf5); it waits there on the
  user's choice of worker. t-omaorgdm waits on this release.
  Who makes the omaguix/omaguix CI change (30c, t-guixprof) this release needs?
  Options: this session does it in a worktree of omaguix/omaguix, with a
  consult review of the diff, and tells that coordinator (recommended) |
  wait for the guix-x86_64-iso-omguix coordinator's worker |
  pi-anthropic worker there now (API credits).
  Checked: the workflow lines above, that coordinator's TODO item 30c and
  its "Needs a decision" entry, the never-pushed clone omaguix-w31.
  Decided by the user 2026-10-25: this session makes the omaguix/omaguix CI
  change (30c's design) in a worktree of omaguix/omaguix, has the models
  review the diff, pushes it and tells the guix-x86_64-iso-omguix
  coordinator; then the release runs.
  Done 2026-10-25: omaguix/omaguix 5cb6692 ("ci: publish the patched Guix
  profile a release names", pushed with [skip ci], no run started): the
  guix-profile job (G' a54c94c5 at today's pin, deterministic across
  clones; `guix pull -p` from a shallow local clone checked with a dry run
  on the 2010 MacBook), the build with P/bin/guix, desktop-split
  --guix-profile/--release-tag, the sign job's checks (it makes G' again),
  the channel paths renamed to modules/omaguix, and the dispatch gate
  narrowed to the maintainer's account. Reviewed in consult round
  20261025-124251-a485 (sol, deepseek; argon refused the brief). The
  guix-x86_64-iso-omguix coordinator was not running: tell it that 30c
  (t-guixprof) landed as 5cb6692 and the omaguix-w31 clone is obsolete.
  Not yet run in CI: the first run is release.py's dispatch.
  Which trust record does the first release's channel commit carry?
  Options: switch trust.scm to substitutes.omaguix.org before the run, so
  main moves only after CI signed with the key matching the .pub, the VPS
  imported it and the coverage check found every item (one run;
  recommended) | release with roguix.frolow.dev first and switch in a
  second release (two multi-hour runs; the first one's guests cannot
  verify the new substitutes) | first a CI dispatch that does not move
  main, verify a signed narinfo by hand, then release.py.
  Checked: trust.scm still names roguix.frolow.dev and its key; release.py
  checks coverage against trust.scm's URL; t-omaorgdm asks for verified
  signed content before the trust record changes.
  Decided by the user 2026-10-25: switch trust.scm to
  substitutes.omaguix.org before the run (the first option).
  May the guix-profile job fetch G from Codeberg by its commit id instead
  of authenticating Guix's history?
  Options: accept the pin by commit id (G comes from the authenticated
  channel; Git checks every object's hash; recommended) | authenticate G
  with `guix git authenticate` on a full Guix clone in that job (minutes
  per run, full history download).
  Checked: consult round 20261025-124251-a485 (sol) noted that
  time-machine authenticated Guix's signed history, which the local
  file:// pull with --disable-authentication no longer does.
  Decided by the user 2026-10-25: authenticate G's signed history too
  (the second option), on a full Guix clone in every run.
  Done 2026-10-25: omaguix/omaguix a199f54 (clone, `guix git authenticate`
  up to G with Guix's introduction; checked on the 2010 MacBook).
  Blocked 2026-10-25 on the VPS (checked read-only over ssh): the
  installed importer is from roguix e1e2d64 (2026-10-12):
  /usr/local/sbin/vps-import execs it with no --static-dir or --key, so
  release.py's `VPS_IMPORT TAG` would run the legacy guix publish import;
  its static-tree fetches from roguixos/roguix and verify-substitutes.scm
  checks the host substitutes.roguix.org. The release would build for hours
  and then stop at the coverage check against substitutes.omaguix.org.
  roguix-vps needs: the omaguix gitlink at a199f54 reinstalled with
  scripts/mac/vps-install-import, substitutes.omaguix.org.pub on the VPS,
  and a command at a fixed path that runs static mode
  (`--static-dir /var/lib/roguix-substitutes --key <that .pub>`), which
  this repository's `.env` then names as VPS_IMPORT (release.py passes one
  path and the tag). No roguix-vps session is running.
  Who prepares the VPS importer for the first release?
  Options: you start a roguix-vps session with this text (recommended; the
  production writes stay with that repository and your OK there) | this
  session does it in roguix-vps with its scripts, as a production change
  you approve here | park the release.
  Decided by the user 2026-10-25: a roguix-vps session the user starts
  prepares it; this item waits for its report (the wrapper's path for
  VPS_IMPORT), then runs release.py.
  Sent 2026-10-25 to the omaguix-vps space's session (omaguix-vps-0a,
  a roguix-vps checkout), with the t-omabkfil closure and decision 0008.
  Answered 2026-10-25 by omaguix-vps (its dfe7a3c, owner-run): the VPS runs
  /usr/local/sbin/omaguix-release-import TAG, which is vps-import in static
  mode with the substitutes.omaguix.org key and never prunes; installed from
  omaguix/omaguix a199f54. The local .env names it as VPS_IMPORT.
  Running since 2026-10-25 13:58 (this session's background job; log in
  the maintainer's state directory, try-omaguix-release-1.log): channel
  commit 892311c4f4d23cf29f985545ed14a64dd3083856 on release/892311c4
  (from try-omaguix 0342093b), CI run
  https://github.com/omaguix/omaguix/actions/runs/40195990260. Check:
  `gh run view 40195990260 -R omaguix/omaguix`; if CI succeeds and a later
  step fails, `release.py --resume 40195990260`.
  Cancelled 2026-10-25 at its G' step, by the user's decision to include
  Odin's substitutes (t-sk47ymxd); release/892311c4 stays unreleased.
  Done 2026-10-25: trust.scm names substitutes.omaguix.org and its key,
  roguix.frolow.dev.pub removed, decision 0008 records it (consult round
  20261025-125554-cd3c: sol, deepseek, argon). The round found that a guest
  made before this release cannot update across it (its daemon trusts only
  the old key, --max-jobs=0). Decided by the user 2026-10-25: by hand,
  as decision 0008 describes (authorize the new key or use a new image); no
  updater change.

- [ ] Move Omaguix to omaguix.org [t-omaorgdm]
  The owner superseded the names on 2026-10-14: Roguix becomes Omaguix,
  the organization is `omaguix`, and the public domain is `omaguix.org`.
  The repositories are now `omaguix/omaguix`, `omaguix/omaguix-channel`,
  and `omaguix/try-omaguix`; their histories and existing tags are preserved.
  Porkbun serves the domain's DNS, with the apex and
  `substitutes.omaguix.org` pointing at the existing VPS. The new substitute
  key's public half is staged as
  `guest/guix/modules/roguix/substitutes.omaguix.org.pub`.
  The earlier plan below uses the superseded domain and filename: current
  implementation uses `omaguix.org` and `substitutes.omaguix.org.pub`.
  Do not activate the new guest trust record until HTTPS, signed substitute
  content and the matching CI signing secret have been verified. Changing
  the substitute key does not change the independently signed channel's
  introduction or signer.

  The owner instructed the migration to leave the old MacBook alone.
  On 2026-10-14 a replacement key was generated locally using Guix's
  libgcrypt generation parameters and checked by signing and verifying a
  message. Its private half was sent directly from memory to the GitHub
  `substitute-signing/SUBSTITUTE_SIGNING_KEY` secret, without creating a
  private file. The current public key's SHA-256 is
  `5e9b4547f9a8409a42e658276deb6e3f4502f6715681a9617f8b105ea73b4f2a`.
  The earlier public key/checksum below is superseded; it must not be used
  with that secret.

  Verified 2026-10-14 (consult round 20261014-193606-be7d with sol, MiMo,
  DeepSeek):
  - Porkbun NS (`curitiba/fortaleza/maceio/salvador.ns.porkbun.com`) and
    Let's Encrypt TLS certificates (`2026-10-14` to `2027-01-12`) are live on
    `https://omaguix.org` and `https://substitutes.omaguix.org` (`A 192.255.242.95`).
  - Remaining on the VPS (`roguix-vps`): `www.omaguix.org` has a `CNAME` to
    `omaguix.org.` but is missing from the TLS certificate SANs; `/var/www/omaguix.org/html`
    is empty (`403 Forbidden`); `/var/lib/roguix-substitutes` is empty
    (`https://substitutes.omaguix.org/nix-cache-info` returns `404 Not Found`),
    while `https://roguix.frolow.dev/nix-cache-info` still serves `200 OK`.
  - Remaining in `omaguix/try-omaguix` (cutover order agreed in round
    20261014-193606-be7d): once `omaguix/omaguix` CI signing gates are fixed and
    `https://substitutes.omaguix.org` serves verified substitutes signed by the
    `5e9b4547...` key, switch `%roguix-trust` in
    `guest/guix/modules/roguix/trust.scm` from `"https://roguix.frolow.dev"` and
    `roguix.frolow.dev.pub` to `"https://substitutes.omaguix.org"` and
    `substitutes.omaguix.org.pub`, remove `guest/guix/modules/roguix/roguix.frolow.dev.pub`,
    update `guest/guix/test_trust.py` and docs (`AGENTS.md`, `docs/architecture.md`,
    `guest/guix/README.md`, `server/README.md`), and publish the release commit.

  Asked 2026-10-12: "I bought roguix.org at Porkbun. Move it. Ask the
  models." Round 20261012-191411-5986 (sol, MiMo, DeepSeek), plan decided by
  the coordinator with the models: the website at roguix.org (GitHub Pages
  or the VPS), substitutes at substitutes.roguix.org (all three; not a path
  under the apex, not "cache"). Decided by the user 2026-10-12, overriding the models' 12-month alias:
  "no, nobody uses it; switch it off": a clean cutover, roguix.frolow.dev is
  turned off once substitutes.roguix.org serves, and the trust record names
  only the new URL (no overlap release). Decided by the user 2026-10-12
  (d-2zft4rjx): the publish key change is a clean cutover too, see "Trust
  two publish keys during the move off the serving host". Decided by the
  user 2026-10-12 (d-j2ilgfxy, relayed by the roguix-vps coordinator): a
  fresh key, held only in GitHub, signs substitutes.roguix.org in CI; new
  VM images trust only it, and the old key is erased from the VPS and
  GitHub. So the URL and the key change ship together. Roguix's maintainer
  (the omguix coordinator) generates the key and hands try-roguix its
  public key for the trust record. Agreed with the omguix coordinator
  2026-10-12: roguix's CI verifies the key at roguix-channel
  modules/roguix/substitutes.roguix.org.pub; since publish-channel
  regenerates the channel's modules, the file is added in try-roguix as
  guest/guix/modules/roguix/substitutes.roguix.org.pub, `(roguix trust)`
  names https://substitutes.roguix.org with it, and roguix.frolow.dev.pub
  is removed. TLS for both names
  before the release; CAA limited to the issuing CA; no mail on the domain:
  null MX, `v=spf1 -all`, DMARC `p=reject`; DNSSEC only once stable.
  Needs: DNS records at Porkbun (the owner, or an API key the owner
  provides), the VPS vhost and certificate (the roguix-vps coordinator,
  which owns the host and its static-substitutes move), then try-roguix's
  trust record and docs. App update feeds stay where they are until checked.



- [ ] Add Odin to Omaguix with substitutes for both architectures [t-sk47ymxd]
  Requested by the user 2026-10-24, relayed by the lang-for-ai coordinator
  (pane wDC:pJ2): "Omaguix needs this odin package, with substitutes for both
  architectures. Ask the models."
  Why it is wanted: lang-for-ai's task set (its item 0A.10, [t-n77zk7ia])
  needs `odin check` and `odin test` in a pinned Guix environment on aarch64
  (its gate guest) and x86_64 (the 2010 MacBook). Upstream Guix has no odin
  package (`guix show: error: odin: package not found` at Guix dda91ea6).
  Consult round 20261024-142009-4b69 (sol, MiMo, DeepSeek, Argon; all four
  agree except where named), to check against this repository when the item
  starts:
  1. Package one pinned Odin `dev-YYYY-MM` release tarball (sha256), chosen so
     the LLVM major its build script supports matches the llvm/clang at
     Omaguix's pin (`guest/guix/modules/omaguix/guix-commit`, 7e74121a; check
     with `guix time-machine --commit=7e74121a -- show llvm`). Do not patch
     Odin's LLVM version check. If no release matches, either package the
     matching LLVM in the channel (sol, DeepSeek) or move Omaguix's pin (MiMo);
     that choice is the user's. Install `core/`, `vendor/` and `base/` under
     `$out/share/odin`, wrap `bin/odin` with `ODIN_ROOT` (Argon: also clang,
     lld and libc on PATH, since `odin test` links). Check phase: `odin check`
     and `odin test` on a tiny package from another directory.
  2. Publication is the hard part: Odin would not be in the reference
     system's closure, so it needs substitutes built for x86_64-linux and
     aarch64-linux and published with the release. Verify per architecture
     with `guix weather odin --substitute-urls=https://roguix.frolow.dev` and
     `guix build --max-jobs=0 odin` in a clean store that trusts only this
     channel's key. Argon warns that an LLVM-heavy Odin build may run out of
     memory on the 2010 MacBook.
  3. Upstream Guix only after it works in Omaguix on both architectures.
  Checked 2026-10-24 against the repository: extra packages live in
  `guest/guix/modules/omaguix/apps.scm` (module `(omaguix packages)`, export
  list at line 29, `codex-bin` defined at 163), and the guest's
  `/etc/config.scm` template takes extra packages between the
  `;; BEGIN omaguix packages` and `;; END omaguix packages` markers
  (`system.scm:108-111`), which puts them in the image closure. Neither
  `guest/guix/release.py` nor `guest/guix/publish-channel` has an "extra
  package list", so the release step cannot publish an arbitrary closure
  today; the cheap route is to put odin into the image's closure, which the
  existing release already builds and signs substitutes for on both
  architectures ([t-omarelfs]). Decision 0003 (upstream binaries) does not
  apply: Odin is free software.
  When it starts: settle the LLVM match, where the package lands, whether it
  goes into the image closure or a separately published one, and the MacBook's
  memory headroom; the lang-for-ai coordinator waits for the released channel
  commit and needs no reply before then.
  Correction and checks 2026-10-24 (the lang-for-ai coordinator pointed at the
  two repositories; I read them):
  - `omaguix/omaguix`'s `.github/workflows/build-desktop.yml` builds exactly
    `(@ (roguix system) %roguix-reference-system)` with
    `guix ... system build --no-grafts`, then takes
    `guix gc -R $(cat outputs.txt)` as the closure and runs
    `scripts/desktop-split`, which publishes the package outputs inside that
    closure to substitutes.omaguix.org (not roguix.frolow.dev) for
    aarch64-linux and x86_64-linux. Local clones: `~/personal_projects/guix/roguix`
    at 09d6aa1 and `~/personal_projects/guix/omaguix-w31` at be56772.
  - `%omaguix-reference-system` is `(settings-operating-system '())`
    (`guest/guix/modules/omaguix/system.scm:410-411`), and
    `settings-operating-system` takes `#:packages` (line 145). So odin gets
    substitutes on both architectures by adding it to the reference system's
    `#:packages` in the channel module, with no CI change; the coordinator's
    alternative, an explicit extra package list in that workflow and
    `desktop-split`, is the more invasive route. Which one to take is a design
    choice for this item: the reference system's meaning changes if extra
    packages live inside it.
  - `desktop-split` refuses to publish unfree items, so the Claude Code
    package can never be substituted and stays out of CI publication, as
    decided; the shim and Odin are free and can be.
  - Both clones still use the old names (`(roguix system)`), so
    `omaguix/omaguix`'s workflow and scripts must move to the renamed modules
    before any of this can be released ([t-omarelfs]).
  Requirements from the lang-for-ai coordinator 2026-10-25 (asked at the
  user's request; they narrow the first slice):
  - Release: the newest `dev-YYYY-MM` whose LLVM major matches llvm at Guix
    7e74121a; if none matches, the user's choice above stands. A release with
    Odin's flow-based escape analysis (upstream master since 2026-10-07, after
    dev-2026-10) is wanted later; nothing waits on it.
  - Scope: `odin check` and `odin test` on one-file and small packages using
    `core` only, so clang, lld and libc on PATH; no vendor libraries, no
    `odin build` beyond what `odin test` does. Layout and check phase as in 1.
  - aarch64-linux first; x86_64-linux later, for a measurement on an x86_64
    Guix host.
  - A channel commit with the package and no substitutes is already useful:
    they build it in their guest, through a channels file pinning Guix
    7e74121a plus this channel, so the package only has to build at this
    repository's Guix pin. Send them the channel commit and its introduction
    (commit and OpenPGP fingerprint).
  - No fixed date; it is next in their queue and blocks their items
    [t-odinguix], [t-c22a5by], [t-n77zk7ia] and later [t-fcarzsiy].
  Started 2026-10-25 by the user's go ("tak"). Done in this repository:
  `(omaguix odin)` (`guest/guix/modules/omaguix/odin.scm`) packages Odin
  dev-2026-10 from its git tag against llvm-22 (Odin 2026-10 supports LLVM
  17-22, Guix 7e74121a has 14-23 with llvm-22 the default), so no pin choice
  was needed. `bin/odin` wraps the compiler with clang-toolchain-22's `bin`
  first on PATH: the first version patched clang's path into `linker.cpp`
  and passed its in-build test, but `odin test` failed in `guix shell --pure`
  ("posix_spawn failed": clang found no `ld`); the in-build check now runs
  with an empty PATH and asserts `odin version`. The compiler finds its root
  through `/proc/self/exe`, so no ODIN_ROOT. The source snippet drops the
  prebuilt Windows tools and the whole `vendor/` collection (prebuilt
  libraries, bundled third-party sources under other licenses); an empty
  `vendor/` is installed because the compiler refuses to start without it.
  Verified on aarch64-linux in the builder: build, `guix build --check`
  identical, `guix lint` clean, and in `guix shell --pure` with only odin:
  `odin version` (dev-2026-10), `odin check` of a `core` package, a type
  error rejected, `odin test` passing with 1 and 2 threads. Consult round
  20261025-103958-6e61 (sol, deepseek, argon) reviewed the diff; acted on:
  scope the empty PATH to the check (sol, deepseek), assert the version
  (deepseek), empty `vendor/` for licensing (sol), `file-append` for the
  toolchain path and drop a no-op LLVM_CONFIG (deepseek); dismissed as
  false after checking: argon's claims that `wrap-program` follows the
  link, that the build mixes gcc and clang, and that the release build uses
  `-march=native`.
  Limits of this package, informational: `vendor:` imports do not resolve,
  so `core:sys/wasm/js` (which imports `vendor:`) cannot be checked; on
  x86_64 `-no-crt` programs need `nasm` for Odin's amd64 entry assembly,
  which the package does not provide (`odin test` never uses it).
  Published 2026-10-25 with the user's go: channel commit
  `72b55436467cb2677777d81259d46b968b386461` (branch `release/<commit>`, not
  on the channel's `main`). Checked as the requester will use it, in the
  builder: a channels file pinning Guix 7e74121a and this commit with the
  channel's introduction, `guix time-machine -C` authenticated it, and
  `shell --pure -m` with only `odin` ran `odin version`, `odin check` and
  `odin test`. Commit and introduction sent to the lang-for-ai session.
  First x86_64 build 2026-10-25 on the Core 2 Duo P8600 (run
  t-dopemmpz-build3): the compiler builds, but the installed check fails in
  `odin test`: "Try using '-microarch:native' as Odin defaults to x86-64-v2
  (close to Nehalem), and your CPU seems to be older." Odin's documented
  default target is x86-64-v2, so on x86-64-v1 CPUs (the requester's x86_64
  host is this MacBook) every `odin test`/`odin build` needs
  `-microarch:native` or an explicit older microarch.
  Also reported by lang-for-ai [t-odinguix] as t-odinx86p (2026-10-25,
  folded in here): it blocks their x86_64 Check until a channel commit
  carries the fix. Done 2026-10-25: on x86_64 the installed check passes
  -microarch:x86-64, the baseline lang-for-ai also uses; built with the check
  on the Core 2 Duo P8600 (run t-sk47ymxd-x86), and in `guix shell --pure`
  `odin version`, `odin check` and `odin test -microarch:x86-64` pass.
  Decided by the user 2026-10-25: Odin's substitutes come with the first
  release, through the reference system (`#:packages '("odin")`, not the
  image), so the first run was cancelled and restarted. Its x86_64 system
  evaluates with Odin in the closure (`system build -d --no-grafts` on the
  MacBook). Review round 20261025-141108-a74e (sol, deepseek, argon): no
  defect; the reference system's derivation now differs from the image's
  (noted, the owner's chosen route). Remaining: the release, then send
  lang-for-ai the released channel commit.

- [ ] Finish the Omaguix rename on the host [t-n53t7ns3]
  Follow-up to the landed rename (d5eb244b on main, pushed 2026-10-19), for
  the parts that live outside the repository. In the renamed app's own
  settings or the owning app, not by hand where the app manages them:
  - Karabiner's Emacs exemption: done 2026-10-19, the pattern now matches
    `dev.tryomaguix.native(.development)?.vm` (dotfiles commit ab82695), but
    the grabber was not running, so the behavior it protects (Emacs keys
    inside the VM) is unchecked until the app next runs.
  - Unload and remove the old `dev.tryroguix.network` LaunchDaemon if any
    host ever installed it (it was never installed on the M1: check).
  - The old development signing identity and its keychain entry
    (`Try Roguix`), then `make signing-identity` for the new one, so builds
    stop signing ad hoc.
  - The old data and log directories `~/Library/Application Support/Try
    Roguix` and `~/Library/Logs/Try Roguix` and the old plists; the renamed
    app reads `Try Omaguix` and its own identifiers.
  - `~/.config/try-roguix/` and the local channel checkout `../roguix-channel`
    with its GnuPG home (`publish-channel` now defaults to
    `../omaguix-channel` and `~/.config/omaguix-channel/gnupg`).
  - The macOS privacy grants (TCC) start from scratch under the new bundle
    ids: grant Screen Recording and Accessibility to the new app.
  The first `try-omaguix-v` tag must be above 0.5.1 (the kept tags
  `v0.5.0` and `try-roguix-v0.5.1` do not match the new prefix).
  Check: `make app` builds from a clean tree and the app launches its guest
  under the new identity.
  Decided by the user 2026-10-25: renaming the leftovers does not wait for a
  decision; rename them. Done 2026-10-25: `../roguix-channel` moved to
  `../omaguix-channel` and `~/.config/roguix-channel` to
  `~/.config/omaguix-channel` (the channel key is there), so `publish-channel`
  runs with its defaults. Asked how the app's leftovers move, the user chose
  "rename everything" the same day; done: `~/Library/Application Support/Try
  Roguix`, `~/Library/Logs/Try Roguix`, `~/.config/try-roguix` and
  `~/Library/Keychains/try-roguix-development.keychain-db` now carry the
  Omaguix names. Still open: that keychain holds the certificate "Try Roguix
  Development", not the identity's "Try Omaguix Development", so `make app`
  still signs ad hoc until `make signing-identity`; the moved VM directory
  holds only metadata for the disk archived on the MacBook; the
  `dev.tryroguix.network` LaunchDaemon and the privacy grants are unchanged.
  May a worker delete the old Roguix host leftovers for the landed rename, and
  do you grant the macOS privacy permissions yourself?
  Options: the worker deletes the old data and log directories, the old plists
  and `~/.config/try-roguix`, moves `../roguix-channel` to `../omaguix-channel`,
  and runs `make signing-identity` for the new identity, but leaves the old
  `Try Roguix` keychain entry for you to remove, and you click the Screen
  Recording and Accessibility prompts when it says the app is installed
  (recommended) | the worker also removes the old keychain entry through
  `security delete-identity` | nothing is deleted, you do all of it yourself |
  list the exceptions you want.
  Checked 2026-10-23: the app's old VM disk is archived on the MacBook
  (`MANIFEST.txt` in `exports/20261018-disk-offload/`, SHA-256 verified before
  the local copy was deleted), so the old data directory holds no unique guest
  state; `~/.config/try-roguix` and `../roguix-channel` exist, the old
  `dev.tryroguix.network` LaunchDaemon is not loaded (`launchctl list` shows
  nothing with that label), and `make app` now fails earlier for an unrelated
  reason ([t-u6g6m27m]).
  Decided by the user 2026-10-25: a worker runs `make signing-identity` for
  the new identity, unloads the old `dev.tryroguix.network` LaunchDaemon if
  one is installed, and also deletes the old "Try Roguix Development"
  certificate from the renamed keychain with `security`; the user clicks the
  Screen Recording and Accessibility prompts once the app is installed.

- [ ] Fetch the virglrenderer tap with git at a fixed commit [t-u6g6m27m]
  Found 2026-10-19 while verifying the landed rename. `make app` on a clean
  checkout fails in the runtime build:
  `virglrenderer patches and regression tests checksum mismatch: expected
  950273fbba46905b6112ee2bd0598c1da706c25319a7347058cbc52f04ba96dd, got
  43831461ece8c8bc821e717632a9d3c297010338ceb50738bc1c88b1d8c02f02`
  (`macos/build-qemu-gpu-runtime.sh` pins `virgl_tap_sha256` for
  `https://codeload.github.com/startergo/homebrew-virglrenderer/tar.gz/refs/tags/v1.0.42`).
  The cause is upstream: tag `v1.0.42` now points at commit
  `de31b78a88b2f9eea04dff32438e6283b400edf7` (`ci: use Homebrew/actions@main
  after master branch removal`), committed 2026-10-18T18:21Z, hours after
  this tree's last successful `make app` (2026-10-18 17:50). A re-download
  today gives the new hash, so the pin is simply dead, not a corrupt
  download; the failure hits any tree, before or after the rename.
  Nothing is known yet about what changed inside the tarball beyond the CI
  commit: the patch files the formula applies were not compared with the
  old bytes (no copy of the old tarball survives here).
  Options: compare the new tarball's content against the old one (fetch the
  old object from codeload by its commit if it still resolves) and, if only
  CI metadata changed, re-pin to the new hash with that evidence in a
  decision record; or pin an artifact we control (a checksummed archive in
  the project's own storage, or a commit tarball plus its verified content
  manifest) so a moved tag cannot break a clean build again; or pin the
  previous release tag if it is still obtainable and newer than 1.0.42 is
  not needed.
  Checked 2026-10-19: `make test-contracts` passes on the landed main;
  `make app` fails only at that download; `git ls-remote --tags` and the
  GitHub commit API give the commit and its date above.
  Checked further 2026-10-24 by the coordinator: the current tag tarball is
  `43831461ece8c8bc821e717632a9d3c297010338ceb50738bc1c88b1d8c02f02`, it
  contains the usual 46 files (`homebrew-virglrenderer-1.0.42/`, the formula
  and the four patch files), and against the tag's parent commit
  `e7daef144d249a38d6206153e6146539f893eae2` the only difference in content is
  `.github/workflows/bottle.yml` (`Homebrew/actions/*@master` to `@main`).
  The parent's own tarball hashes `6954b95a…`, so the pinned `950273fb…`
  matches neither the current tag nor its parent: GitHub's generated tarballs
  are not stable over time, which is the real defect of this pin, not one
  upstream commit. A content manifest (per-file sha256 of the extracted tree)
  would make the next move diffable, and a checksummed archive we host would
  remove the dependency on GitHub's archive generation.
  Recommendation: re-pin to `43831461…` now, with the per-file content
  manifest recorded next to the pin, so the tree is verifiable as content
  rather than as one gzip byte string; then move the archive into our own
  storage when the release work touches the runtime build anyway.
  Decided by the user 2026-10-25 (after asking for a plain explanation):
  fetch the tap with git at a fixed commit instead of GitHub's generated
  tarball, and verify the checked-out tree; the runtime build script changes
  to git.

## Proposed

- [ ] static-tree: a prune without downloads, and a free-space check [t-stprune]
  Asked 2026-10-25 by omaguix-vps (its consult round
  20261025-135551-7597, sol, MiMo, DeepSeek, Argon): in omaguix/omaguix's
  scripts/static-tree, (1) `static-tree prune --directory DIR --key KEY
  --keep N`, the existing prune() under DIR/.roguix/lock with no network,
  verifying the live set before deleting and reporting the tags kept and
  bytes freed (run by the owner after both architectures of a release are
  imported, never on a timer); (2) a check in `pull` and `install` before
  any download that the assets, the unpacked tree and a reserve
  (`--min-free BYTES`) fit, since the VPS also hosts databases. `pull
  --keep N` re-downloads before it deletes, so it needs the most disk when
  disk is short. omaguix-vps waits for the commit. Cost: Python and tests in
  omaguix/omaguix; no build.

- [ ] Tell try-omabend what its identity file needs at its next pin bump [t-omabidk]
  try-omabend clones this repository at a pinned commit (its
  pins/try-roguix, 0d9d2780 on 2026-10-25), so it adopts identity changes
  only when it moves that pin. Past 4111a399 its identity file needs
  GUEST_NAME=Omabend (t-5gcnv3af), and GUEST_SYSTEM=system/image.scm,
  GUEST_LOAD_PATH=system and GUEST_CREDENTIALS=preset (t-d2xuz6pd), and its
  scripts/app can call `make guix-package` instead of package.py with its
  own arguments. A GUEST_NAME added before the bump breaks its build (the
  old validator refuses unknown keys), which this session found and undid.
  No try-omabend session was running to be told. Cost: a message; no build.

- [ ] Pass the app identity explicitly where AppKit defers work [t-idparam]
  From review round 20261025-133254-7c22 (deepseek) of t-5gcnv3af:
  `AppIdentity.main` is task-local; blocks that DispatchQueue, AppKit
  completions or Process handlers run later inherit no override, so code
  that names the app there reads the bundle's identity. In the app that is
  always right (one identity per process); in tests such a block stops the
  run on the missing Info.plist key, and StartMenuWindow carries the
  identity across its three such blocks by hand. Option: store the identity
  in StartMenuWindow and VMApplicationController and pass it to the string
  builders, so an omission fails to compile. Swift only; no build.

- [ ] Build the shim's substitutes where its trap tests run [t-shimv1ci]
  From consult round 20261025-122507-775c (deepseek), checked against the
  shim's `make check`: on a builder with POPCNT and without QEMU the trap
  tests are skipped, yet `x86-64-v2-sigill-shim` has ordinary substitutes, so
  a CI substitute could ship a shim whose x86-64-v1 path never ran. Options:
  build its substitutes on the Core 2 MacBook, run the check under
  qemu-x86_64 with `-cpu` without POPCNT in the build, or make it
  non-substitutable. Costs a CI or build change; no guest build.

- [ ] Accept Guix's Ungoogled Chromium on the Metal path [t-wgeohswx]
  Split from the Metal item 2026-10-12 by the user's decision ("LibreWolf
  first"): once omaguix/omaguix's CI builds `ungoogled-chromium` for aarch64
  (no substitute at the pin; a many-hour build), check it on `gl=es` like
  LibreWolf (GPU compositing, raster, WebGL 2, no software fallback) and fix
  what differs. Needs CI to build the package first.

- [ ] Let agents click in a VM and see the result: evaluate hypruse first [t-kmsxorgt]
  Deferred by the user 2026-10-11: "the rest later" (the coordinator
  and the supervisor come first).

  Asked 2026-10-11: "how can an agent click and watch what shows? ask the
  models"; decided by the user 2026-10-11: "evaluate hypruse first". Consult
  round 20261011-202749-4e02 (sol, MiMo, DeepSeek): give agents a small MCP
  server with screenshot (`grim -c`, PNG), click(x, y), type, key and a wait
  on a positive signal (Hyprland's socket2 events, e.g. `openwindow`,
  `activewindow`), reached as an stdio MCP over `ssh` into the guest; type
  long text through the clipboard (`wl-copy`, Ctrl+V); name the coordinate
  space in every call and calibrate it (screenshot pixels, Hyprland logical
  coordinates with scale, the tablet's 0..32767); QMP `input-send-event`
  with explicit key down/up as the host-side fallback (fixes `send-key`'s
  repeats); browser pages through DevTools rather than pixels.
  Step 1: a worker reads hypruse's source (https://pypi.org/project/hypruse/)
  for what it runs, its dependencies (ydotool needs uinput and a daemon,
  wlrctl the virtual-pointer protocol) and its license, and tries it in a
  throwaway test VM from the host through ssh: screenshot, click a known
  target, type into foot, wait for a window. Report whether to package it in
  the guest or write our own with the tools above; no guest change yet.

  Researched 2026-10-11 at the user's request ("Primeagen was hired by
  Omarchy for QA; research it with the models"), round 20261011-203239-c145:
  ThePrimeagen joined Omarchy Core on 2026-09-26 to lead "Agentic QA" with
  Oligarchy, his harness that boots Omarchy in QEMU from a fresh disk per
  test, where agents send keys, move and click the mouse and take
  screenshots, exposed per job as HTTP tool calls ("qemu-http-tools"); its
  repository now returns 404, so its code cannot be read. Upstream's own
  acceptance harness (omacom/omarchy-iso bin/omarchy-iso-test,
  omacom/omarchy test/acceptance.d/base-test.sh) uses plain virtio-vga, QMP
  screendump with tesseract OCR and QMP send-key before login, then over SSH
  grim, tesseract and `hyprctl -j` window and layer checks, with polling
  waits and per-step success/failure PNGs. Decided by the coordinator with
  the models: keep hypruse first as a bounded evaluation (sol, MiMo;
  DeepSeek ranked it last); copy upstream's evidence discipline (a PNG per
  step, `hyprctl -j` state checks, a capture failure reported apart from
  missing text) and QMP keys for global keybindings, which in-guest wtype
  does not prove; do not copy fixed polling or a non-GL display (it would
  test another graphics path). Dismissed: MiMo's and DeepSeek's claim that
  screendump is black under VirGL (the brief omitted our readback patch).
  Running upstream's acceptance suite on Roguix is a separate proposal.

- [ ] Run Omarchy's acceptance suite on Roguix [t-sn5o2yrj]
  Deferred by the user 2026-10-11: "the rest later" (the coordinator
  and the supervisor come first).

  Decided by the user 2026-10-11: "yes, after hypruse". Proposed
  2026-10-11 (from the hypruse item's research): run upstream's
  test/acceptance suite (omacom/omarchy, test/acceptance.d) in a Roguix test
  VM over SSH, with an adapter where Roguix differs (Guix paths, packages,
  services) and waits on positive conditions instead of its 1 s polling,
  as a regression oracle for what Roguix promises to share with Omarchy.
  Cost: a worker day or two; needs tesseract in the test VM (a guest
  package or a test-only image); no product change.

- [ ] A reset erases the old VM before fetching the factory disk [t-cpdtxhhy]
  Reported 2026-10-10 by another session at the maintainer's request: during a
  reset, run-qemu-gpu.sh downloads/selects the compressed factory disk (~3 GB)
  before `qemu_persistent_storage_select` erases the old VM
  (`_qps_clear_workspace_locked`), so both coexist briefly and a reset on a
  nearly full disk can still fail for space. Make a reset erase the old VM
  before the fetch (keeping the keep-saved-VM/archive semantics), so it needs
  no more room than the old VM already used. Consequence: a failed or
  interrupted download then leaves no VM, as the dropped 67a8d7a accepted.
  (67a8d7a itself targeted the pre-0.5 base-image flow and was dropped in the
  rebase on purpose.)

- [ ] Test gliff-server in the guest before packaging it [t-sakzbqb5]
  Postponed 2026-10-10 by the maintainer ("put gliff off for later, many things are more important").

  Approved 2026-10-10: run this feasibility test first; package nothing yet.
  Postponed by the maintainer 2026-10-10 (more important work first), during
  step (a); see "Progress" below for where it stopped and how to resume.

  Proposed 2026-10-10 (see "Background: Roguix as a gliff remote machine"). A
  disposable check, nothing packaged or shipped: set pass thresholds first
  (sustained frames per second and encode time per frame at 1080p, typing and
  scrolling feel), then (a) check that Hyprland's ext-image-copy-capture into a
  GBM buffer and a CPU map of it work on the VirGL render node, (b) time
  OpenH264 at 1080p on the guest's vCPUs, and only if both pass (c) run a
  gliff-server built outside the image against a gliff client on an existing
  x86_64 Linux with Hyprland, over NAT with a ProxyJump through the Mac, on a
  wired LAN. Record the numbers; stop at the first failure.

  Pass thresholds, set by the worker on 2026-10-10 before measuring (gliff
  targets 60 fps; these are the floor for a usable remote desktop, not the
  target). All at 1920x1080 on the guest's default vCPUs, the Mac otherwise
  idle:

  - (a) Capture: ext-image-copy-capture of a 1080p Hyprland output into a GBM
    buffer on the VirGL render node succeeds, and a CPU map of that buffer
    reads the real screen contents (not zeros); capture plus map plus a
    full-frame read takes at most 10 ms median and 20 ms p95 per frame.
  - (b) Encode: BGRA to I420 conversion plus an OpenH264 encode at 1080p
    (gliff's CPU tier: 4:2:0, up to four threads) takes at most 25 ms median
    and 40 ms p95 per frame, on content that changes every frame (scrolling
    text). Capture plus encode together then fit a sustained 30 fps.
  - (c) End to end, wired LAN: at least 30 fps sustained while scrolling a
    full-screen terminal or browser page for 30 s, at most 2 % of frames
    later than 100 ms; typing and scrolling "feel fine" means input-to-frame
    latency (key or wheel event at the client to the changed frame shown
    there) at most 60 ms median and 120 ms p95, with no stall over 250 ms.

  Progress 2026-10-10 (worker, stopped by the postponement; no threshold
  measured yet, nothing packaged): a disposable VM from this tree's app and
  main's guest build (`run-qemu-gpu.sh --ephemeral` with
  `OMARCHY_QEMU_GPU_STATE_ROOT` in a scratch directory and
  `OMARCHY_QEMU_GPU_PORT_FORWARDS=tcp:2299:22`, 8 vCPUs, 8 GiB, Apple M1 Pro)
  booted unattended: a script waited for each `roguix-setup: ready STEP` line
  in the run's `console.log` and answered with QMP `send-key`, then SSH with a
  password worked through the NAT forward. The guest showed Hyprland 0.56.1 on
  a 3456x2170 output (the Retina window size), `/dev/dri/renderD128`, and Guix
  offers rust 1.93.0, libva 2.22.0, mesa 26.0.2 and openh264 2.6.0. gliff
  v0.3.0 has its own probe, `gliff-probe`, which covers (a) and (b) directly:
  `capture` (ext-image-copy-capture into a GBM buffer on the render node, CPU
  map, PNG), `--video cpu roundtrip --single --width 1920 --height 1080`
  (per-frame encode time), and `stream-bench` against
  `gliff-server --listen 127.0.0.1:9000 --headless --video cpu` (fps, jitter,
  latency; with `RUST_LOG=gliff_server=debug` the server logs `read_us` and
  `enc_us` per frame, and `--headless` gives an exact 1080p output). The
  build (`guix shell rust rust:cargo pkg-config gcc-toolchain libva mesa
  wayland libxkbcommon -- cargo build --release -p gliff-server -p
  gliff-probe`, about 15 minutes, mostly substitute downloads) compiled 111
  crates, then failed in `libdbus-sys`: `dbus` is missing from that package
  list. Afterwards the guest's sshd stopped answering (TCP connected, no
  banner) while QMP reported the VM running; the cause was not investigated.
  To resume: add `dbus` to the `guix shell` list, find why SSH stopped
  answering (memory pressure from 8 parallel rustc jobs is one suspect, not
  verified), then run the probes above in this order.

- [ ] Compare wayvnc as the remote view [t-4vzb5lvt]
  Proposed 2026-10-10 (see "Background: Roguix as a gliff remote machine").
  wayvnc 0.10.1 is already in Guix at the pinned commit (`gnu/packages/vnc.scm`)
  and needs no Vulkan or VA-API. Run it in the guest for one boot against the
  same checks as the gliff test, so a choice is made between measured options.

- [ ] List gliff as not provided at the next Omarchy bump [t-76ot56gb]
  Proposed 2026-10-10 (see "Background: gliff"). Omarchy 9d48fc402e
  (2026-10-09) installs gliff by default (`omarchy-base.packages` and a
  migration) and adds a status-only "Remote session" bar indicator. The pinned
  Omarchy (c668141, 2026-09-15) predates it. When the pin moves past it, add
  gliff to `docs/omarchy-packages.md` as not provided (no Guix package; its
  upstream package is x86_64 only), check that the indicator stays dark and
  quiet with no `gliff-server` installed, and leave the migration to the seed,
  which marks shipped migrations done. Docs only, with the bump.

- [ ] Offer Try Omarchy the zero-block punch [t-5wxjylaq]
  Proposed 2026-10-09 (see "Background: large VM files"): Try Omarchy's
  fresh working disk allocates about 1.1 GiB of zeros. Offer a small change
  that punches whole zero blocks in its helper's SHA-256 pass after
  decoding, framed modestly (initial footprint, contents unchanged), with a
  measurement on its current main. Contacting upstream needs approval.

- [ ] omarchy-shell kills non-idempotent calls on a timeout [t-3b46spbn]
  Proposed 2026-10-09 by the Super+Space worker, raised by sol and MiMo:
  `omarchy-shell` runs `qs ipc` under `timeout --kill-after=1s 2s` and reports
  "not responding" when it kills the client, but the call may already have
  reached the shell, so a toggle is lost or applied late and the caller
  cannot tell which. Other bindings and scripts still go through it after the
  #13418 backport. A kill should mean "outcome unknown", never a failure to
  retry; callers that need a state should ask for it (open or close, not
  toggle). Check which default callers toggle, and offer it upstream.

- [ ] The shutdown screen shows Hyprland's startup log [t-5nrn7cv4]
  Found 2026-10-07 by the shutdown-font worker and seen again 2026-10-09 with
  the bold console font: at shutdown tty1 still shows the Roguix logo and
  Hyprland's startup log, which `start-hyprland` printed there, and the
  shutdown lines are written over its last line. Clearing tty1 when Hyprland
  exits (or not printing the log there) would leave only the shutdown text.

- [ ] Give the builder a disposable scratch disk for builds [t-4brvu3it]
  Proposed 2026-10-09; weigh it after the cleanup step above. The image
  derivations copy the closure into a temporary root, an ext4
  `partition.img` and a genimage temporary in guix-daemon's build directory.
  Pointing the daemon's `TMPDIR` at a second qcow2 that is deleted after the
  build would free those at once instead of waiting for gc and trim. It adds
  no capacity (same APFS volume) and changes how the builder is started.

- [ ] Let the export drop every old image root [t-edvvmbii]
  Proposed 2026-10-09 by the builder cleanup worker: `build.py --export`
  removes only the exported image's GC root, so an older `/root/*.raw` root
  kept a previous image pinned (the builder stayed at 39 GiB until it was
  removed by hand). The export could also remove the other `/root/*.raw`
  roots that point to a `-disk-image` store item.

- [ ] Recheck Venus on macOS at the next virglrenderer release [t-zb7efvcb]
  Approved 2026-10-10; waits for the next virglrenderer release.

  Proposed 2026-10-10 (see "Background: KosmicKrisp and Venus"). When a
  virglrenderer release after 1.3.0 contains the macOS Venus series (!1600,
  !1601, !1602, !1635), check read-only whether it also settles host memory
  on KosmicKrisp (!1685), whether Guix's Mesa has reached 26.2.4 or later,
  and whether UTM still keeps the Linux desktop on VirGL; then update the
  background and ask again. No runtime change.

- [ ] A time-boxed Venus experiment on a throwaway runtime [t-gh4i2jvb]
  Proposed 2026-10-10 (see "Background: KosmicKrisp and Venus"); only if
  Vulkan apps become a goal. A development runtime with virglrenderer main
  (plus !1685 if still open), a bundled Vulkan loader and KosmicKrisp
  (macOS 26) or MoltenVK (macOS 15), `venus=on,blob=on,hostmem=...` on the
  existing device, and a guest Mesa with "venus: honor the virtio-gpu blob
  alignment". Pass when: `vulkaninfo` shows the Venus device, vkcube in a
  Hyprland window does not lose Hyprland's GL context, the hostmem BAR fits
  on an M1 or M2 (36-bit guest addresses), and a guest-triggered device loss
  leaves the Mac and the VirGL desktop working. Record numbers against
  VirGL; ship nothing from it.

- [ ] Hardware H.264 encoding through VA-API and VideoToolbox [t-3fkebvn4]
  Proposed 2026-10-10 (see "Background: KosmicKrisp and Venus"); only if CPU
  encoding (OpenH264, gliff) is measured too slow in the guest. The route
  independent of Vulkan: guest VA-API (Guix's Mesa builds its VA driver with
  `-Dvideo-codecs=all`) over virgl's video protocol to a virglrenderer
  patched to encode with VideoToolbox, as OmacVM does (#48). Needs
  `-Dvideo=true` and a carried patch; measure CPU, latency and copies first.

- [ ] Free disk space on the Mac: move what is needed to the 2010 MacBook [t-3w5klpka]
  Asked by the user 2026-10-16: "move the ones needed for now to the 2010
  MacBook because space is short; delete what can be recreated relatively
  quickly; ask the models". The Mac had 12 GiB free; the MacBook has 391 GiB.
  Candidates found:
  - the user's own VM disk `~/Library/Application Support/Try Roguix/.../disk.raw`
    (21 GiB used; user data that cannot be recreated, and orphaned by the
    rename [t-xzufmvj7] anyway);
  - the builder disk `.build/guix-validation/builder.qcow2` (26 GiB, an
    overlay on the 1.2 GiB official image; it can be recreated, but its
    `/gnu/store` takes hours to rebuild, and it is in use);
  - `build/dev.noindex` (2.9 GiB, `make app`); `build/guix` (2.8 GiB, the
    packaged guest; recreating it needs an image build).
  Consult round in progress.
  Consult round 20261016-181137-1d2e (all five models): delete
  `build/dev.noindex`; copy the stopped VM disk with `rsync -aS --partial`
  under mb-run, compare sha256 and logical size on both ends, sync, rename,
  then delete the Mac copy (the MacBook copy is then the only one); keep the
  builder and `build/guix`; no APFS snapshots (checked). Rsync is 3.5 on both
  ends; disk.raw was not open.
  Decided by the user 2026-10-16 (d-q55wvgua): not now, there is space for
  now. Redo the plan when space runs short (the `macbook-2010` skill covers
  the move).

## Needs a decision

- [ ] Shell contract tests keep their scratch files under `TMPDIR` [t-ruyb3h22]
  Follow-up of `[t-omabendl]` (consult round 20261016-144120-c88a): the
  shell suites create scratch directories under `/private/tmp`
  (`macos/Tests/qemu-monitor-ready.test.sh:10`, `network-helper.test.sh:4`,
  `runtime-relocation.test.sh:26`, `qemu-memory-contract.test.sh:35`), which a
  headless worker's sandbox cannot write and which collide in parallel runs.
  Use `TMPDIR`; sockets, `ps` and `codesign` still need a pane worker.
  Decided by the user 2026-10-16 (d-nma3lspc): approved, moved to Next.
  Checked 2026-10-25: every listed suite still needs a pane worker
  (network-helper and runtime-relocation run codesign; qemu-monitor-ready
  and qemu-memory-contract use Unix sockets whose paths the launcher and
  QMPConnection accept only under /tmp, kept short for the 104-byte limit;
  TMPDIR here is 49 characters). `mktemp -d ...XXXXXX` already makes unique
  names, so parallel runs do not collide. The four files are Try Omarchy's
  (upstream), so a change costs a conflict on every rebase.
  Drop the item, since it frees no suite for a headless worker?
  Options: drop it (recommended) | move only the codesign suites to TMPDIR
  anyway | offer the change to Try Omarchy upstream.

- [ ] Offer the ANGLE multisample fix to startergo's virglrenderer tap [t-omaangle]
  Decided by the user 2026-10-12: "yes, after acceptance". Proposed
  2026-10-12 by the Metal worker (models: after end-to-end
  acceptance, to startergo/homebrew-virglrenderer first): offer
  macos/patches/virgl-angle-multisample.patch upstream once Metal is the
  default and LibreWolf and Chromium pass (Metal became the default
  2026-10-12, commit "macos: run guests on ANGLE/Metal by default"). Cost: a short PR; no build.
  Checked 2026-10-25: the condition is not met. LibreWolf passed, but
  Chromium on Metal is [t-wgeohswx] in "Proposed", waiting for CI to build
  ungoogled-chromium for aarch64.
  Offer the patch upstream now on LibreWolf's evidence, or wait for Chromium?
  Options: wait until [t-wgeohswx] passes, as decided (recommended) | offer
  it now, saying Chromium is unchecked | drop the offer.

### Background: renaming to Omaguix (2026-10-12)

Asked 2026-10-12: "maybe ride Omarchy's popularity and rename to omaguix?
ask the models". Round 20261012-190551-d1ba (sol, MiMo, DeepSeek), all
three: keep Roguix. "Omarchy is a pending trademark. All rights reserved."
(omarchy.org/brand); the "Oma" prefix is the Omarchy family's (Omakub,
Omarchy), so "Omaguix" reads as an official port, and community "Oma"
names are tolerated, not permitted. Search does not need the name: say
"Roguix: Omarchy on Guix System" in the README, the repositories'
descriptions and topics (omarchy, guix, hyprland). An "Oma" name would
need written permission from foundation@omarchy.org first. Renaming is
cheapest before the announcement (modules, commands, channel, domain, app
identity; the channel introduction can stay). MiMo: the Omarchy logo from
the brand kit that Try Omarchy ships stays subject to Omarchy's rights
whatever the name. No change made.

### Trust two publish keys during the move off the serving host

When the guix publish signing key moves off the serving host
(docs/roguix-signing-keys.md, the plan from the trust-record item, done
2026-10-12), guests must trust the old and the new key for one release:
compatibility under the policy (Rule 7), so it needs the owner's approval
with a removal date for the old key. Approve the dual-key release when
the move happens?
Decided by the user 2026-10-12: "yes, one release": guests trust both keys
for one release, then the old key is dropped; this applies when the move
happens (no item queued for the move itself).
Superseded by the user 2026-10-12 (d-2zft4rjx): a clean cutover, since
nobody uses Roguix yet: guests trust only the new key from the release
that moves it, with no dual-key release.
Checked 2026-10-12: the plan recommends signing on the builder and serving
static files from the VPS; no host change has been made.

### Background: drgn for agents (2026-10-11)

Asked 2026-10-11 to analyze drgn 0.3.0 (https://github.com/osandov/drgn/releases/tag/v0.3.0)
with the models, after the remark that a programmable debugger suits LLMs.
drgn inspects Linux kernels (live /proc/kcore, vmcores) and C programs,
supports AArch64, debugs a QEMU guest over QMP (`--qemu`, needs `-device
vmcoreinfo`, works on a hung VM), and since 0.3.0 reads guest memory from
the QEMU process through Linux ptrace. Round 20261011-231321-1582 (sol,
MiMo, DeepSeek), all three: do not adopt it now. It runs on Linux, not on
the macOS host, so the QMP mode would need a Linux VM and loses the fast
ptrace path; in the guest it needs kernel debug info Guix's linux-libre
likely does not ship (DWARF or BTF, unverified) and a package. It fits
none of the recent bugs well: QEMU's black screendump is host-side (lldb,
QEMU tracing), grim's hang was a Wayland stall (WAYLAND_DEBUG, gdb), and
the all-vCPU soft lockups stop any in-guest tool and point at host
scheduling (host sampling, guest ftrace). Revisit when a guest-kernel
memory bug resists ftrace and printk; the smallest step then is a test-only
image with kernel BTF or DWARF plus `-device vmcoreinfo`.

### Report grim's pending capture on a blanked output to Hyprland

Decided by the user 2026-10-11: "I will report it myself" (the maintainer
posts it in his own words; nothing for agents to do).
Checked 2026-10-11: Hyprland takes bugs only as GitHub Discussions
("Bugs - Other"), whose form requires confirming the report was written by
hand, in the reporter's own words, without AI; no existing discussion or
issue found. Facts for it: Hyprland 0.56.1 (5c9377c), grim 1.5, ARM64 VM
with virtio-gpu/VirGL; after `hyprctl dispatch 'hl.dsp.dpms({ action =
"disable" })'` the first grim succeeds and the next waits after
`capture()`, `damage`, `transform` with no `ready` or `failed` until DPMS
is enabled; the spec sets no deadline, so it is a liveness question.

### Background: rebase onto Try Omarchy 0.5 (2026-10-10)

`main` was rebased onto upstream 3c6056d (46 commits, release 0.5). Three
own commits dropped as upstream covers them (the VM integrations row and
the Language row are gone upstream; a reset already erases the old VM);
two added: the boot-fix review removed from the app (it repairs the Arch
guest's files), and 0.5's new texts adapted to Try Roguix. Decided by the
coordinator with sol and MiMo: the host follows upstream's language model
(the app sends the Mac's primary language when the image lists it; the
start menu's Language row is gone, so choosing zh_TW on a Mac in another
language is no longer possible), and releases keep `macos/release.sh`.
Follow-ups are in "Proposed".
Declined by the user 2026-10-10: Pinyin input for zh_CN (upstream has none),
a KR font for Korean text in zh_TW sessions, and migrating older VMs'
language (a VM set up before the once-only language returns to English after
a reconfigure; set `#:locale` in /etc/config.scm).

### Background: KosmicKrisp and Venus

Decided 2026-10-10: record only, recheck at the next virglrenderer release.
Checked: the sources below, the runtime scripts, the Guix Mesa package at the pin, consult round 20261010-002607-ad4d.

Requested 2026-10-10 ("add the KosmicKrisp and Venus research; ask the
models"); investigated read-only, consulted sol and MiMo (round
20261010-002607-ad4d). Short answer: Venus would be an addition for Vulkan
apps, not a replacement of VirGL on ANGLE for the desktop, and it brings no
video encoding; today it needs unreleased or third-party host code, a newer
guest Mesa and macOS 26 for KosmicKrisp. Findings:

- KosmicKrisp: LunarG's Vulkan driver on Metal 4 in Mesa (merged for Mesa
  26.0), Vulkan 1.4 conformant and in the Vulkan SDK since 2026-09-29
  (Phoronix, Khronos). macOS 26 or later only
  (docs.mesa3d.org/drivers/kosmickrisp.html); the app supports macOS 15,
  where only MoltenVK exists. Mesa main lists `VK_EXT_external_memory_metal`
  and `VK_EXT_external_memory_host`, transform feedback and tessellation,
  no `VK_KHR_external_memory_fd` and no `VK_KHR_video_*` at all.
- QEMU (our pin c3d48b7): Venus is `virtio-gpu-gl-pci,venus=on`, which
  requires `blob=on` and `hostmem`, and starts virglrenderer with
  `VIRGL_RENDERER_VENUS|VIRGL_RENDERER_RENDER_SERVER`. It adds Vulkan
  contexts beside the VirGL ones on the same device. The pin has no
  virtio-gpu blob-alignment code.
- virglrenderer: our 1.3.0 (2026-02-10) is built with `-Dvenus=true`, but
  the app starts no Venus. macOS Venus was merged upstream after 1.3.0 and is
  unreleased: build support (!1600), posix_spawn render-server workers for
  Metal (!1601), POSIX shared memory wrapped as an MTLBuffer and exported to
  the VMM as an SHM fd (!1602), Metal device export (!1635). Open: !1685
  (UTM's author) says KosmicKrisp has neither `VK_EXT_metal_objects` nor the
  MTLBuffer handle type, so every host-visible allocation fails, and moves
  the import to `VK_EXT_external_memory_host`; !1618 (Metal texture scanout,
  GL and Vulkan interop) is open. The startergo taps we build from carry
  their own Venus-on-Metal patches; their QEMU README's
  `virtio-gpu-pci,vulkan=on` is not a QEMU option, so it reads untested.
- Guest: Guix's Mesa (pin and master) is 26.0.2 and builds the Venus
  driver (`virtio`) on aarch64. Mesa 26.2.4 (2026-10-01) has "venus: honor
  the virtio-gpu blob alignment"; OmacVM reports Venus failing without it
  on a 16 KiB-page host. A backport would do as well as the bump.
- Prior art: UTM 5.0.6 beta (2026-09-24) ships Venus with MoltenVK or
  KosmicKrisp and says Linux desktop rendering in Vulkan does not work, so
  the desktop stays on VirGL. OmacVM (MIT, an Omarchy VM for the Mac) ships
  Venus on QEMU with MoltenVK (macOS 15) and KosmicKrisp (26+, default
  since 2026-10-09) behind a stack of patches: KosmicKrisp built with
  `-Dplatforms=macos` (otherwise a NULL entry point crashed QEMU on the
  guest's first allocation), a load-time fallback to MoltenVK, a smaller
  high PCI window so the hostmem BAR fits on M1 and M2 (36-bit guest
  addresses; without it the VM did not boot), and a host patch so a
  Vulkan window imported into Hyprland's virgl GL context no longer loses
  that context; the window is still copied on the host. Its M4 numbers:
  vkmark 840 (KosmicKrisp) against 650 (MoltenVK); glmark2 through Zink
  558 against VirGL 592; Chrome's ANGLE on Vulkan works only with X11 and
  flags. Its VirGL runs on Apple OpenGL, not ANGLE, so the context-loss
  path is unverified on our runtime.
- What it would give: Vulkan for guest apps (vkcube, vkmark, compute,
  OpenCL through rusticl on Zink). Not the desktop: Hyprland renders with
  GLES on VirGL, and Zink on KosmicKrisp is slower than VirGL and lacked
  GL 3+ features in OmacVM's test. Not video: neither KosmicKrisp nor Venus
  has Vulkan Video, so no hardware encoding for gliff through Vulkan
  (Vulkan compute could still do its colour conversion).
- Cost of adding it: virglrenderer from main or a patch stack, a Vulkan
  loader and KosmicKrisp (Mesa with LLVM, libclc and the SPIR-V translator
  at build time) plus MoltenVK for macOS 15, a render-server executable to
  bundle and sign, QEMU's high PCI window for the hostmem BAR on M1 and M2,
  a guest Mesa with the alignment fix, the Venus-to-VirGL presentation path,
  and a larger guest-reachable host surface (a shader compiler; OmacVM saw
  a guest drive KosmicKrisp to `VK_ERROR_DEVICE_LOST`).

Both models: record only now, (a) ahead of (b) a time-boxed experiment,
far ahead of (c) moving the desktop to Zink, which the glmark2 numbers and
UTM's note argue against; hardware encoding for gliff is the VA-API route
to VideoToolbox (OmacVM #48), independent of Venus. sol alone: gate any
adoption on acceptance criteria (KosmicKrisp allocations work, the guest
alignment fix, the BAR on M1 and M2, Vulkan windows presented reliably,
recoverable device loss), not on a release number; advertising
`VK_EXT_external_memory_metal` and !1685's failure can both be true. MiMo
alone: check the guest kernel's virtio-gpu context and blob support and
the render server's entitlements; whether Venus would retire the 1 ms
fence poll (it would not: the desktop stays on VirGL). Dismissed: MiMo's
"OpenH264 is fine" (gliff's fast conversion kernels are x86_64 only, see
"Background: gliff"), and that the compiler runs in QEMU's process (QEMU
starts Venus with the render server, so it runs in a worker; OmacVM's
note reflects its setup).

Asked again 2026-10-11 ("why don't we use KosmicKrisp? ask the models"),
round 20261011-190341-d959 (sol, MiMo, DeepSeek): all three keep "not
now". For this product (Hyprland on GLES, terminal, browsers) Venus with
KosmicKrisp gives no visible gain: it adds Vulkan for guest apps only, the
desktop through Zink measured slower than VirGL (558 against 592), there
is no Vulkan Video, and macOS 15 still needs MoltenVK or VirGL. It does not
touch the black screendump either: that is QEMU's Cocoa GL scanout never
filling the console surface, whichever guest driver renders. sol and MiMo:
reconsider on working integration (KosmicKrisp allocations through
virglrenderer, the guest alignment fix, which may be one backported
commit), not on a release date alone; the recheck item already checks
those.

### Background: gliff

Decided 2026-10-10: adopt nothing before upstream ships a macOS client; record only.

Requested 2026-10-10 ("ask the models"); investigated read-only, consulted
sol and MiMo (round 20261010-000628-72e6). gliff (omacom/gliff, MIT, Rust,
v0.3.0 of 2026-10-09) is a Hyprland remote desktop over ssh: the server
captures a Hyprland output or a private headless one sized to the client
window and sends H.264 4:4:4 (two 4:2:0 streams) through Vulkan compute and
VA-API on AMD or Intel, or OpenH264 on the CPU; input goes through virtual
keyboard and pointer with the client's keymap; the clipboard is lazy and
carries files. Findings:

- No macOS client: the client is Linux GTK4 only. A native one (VideoToolbox
  and Metal) is a draft pull request (#5) untouched since 2026-09-21, on a
  protocol version main has since reset, so it is a reference, not a client.
- The guest has VirGL (OpenGL only), so neither Vulkan compute nor VA-API
  encode exists there: gliff would fall back to OpenH264 on the guest's
  vCPUs, whose fast conversion kernels are x86_64-only; aarch64 is untested
  and the upstream package is `arch=x86_64`.
- As the VM's display it would add capture, encode, transport and decode
  where QEMU now shows VirGL's rendering directly, and lose the Cocoa
  patches' host-window behavior (immersive mode, full grab, Command-Tab,
  pinch zoom, precise scroll, the ISO key swap); it would also show nothing
  before the Hyprland session (boot, password prompt). It would cover only
  display, input, resize and the clipboard; audio, camera, battery, Touch ID,
  time zone and the shared folder stay on their bridges.
- Remote access from another machine does not fit Try Roguix either: "Add
  SSH" binds `127.0.0.1` only, and on the same Mac Cocoa is the better view.
- Upstream Try Omarchy does not mention gliff; Omarchy itself installs it by
  default since 2026-10-09 (see "List gliff as not provided at the next
  Omarchy bump" under Proposed).
- Packaging for Guix means the whole Rust crate tree (gtk4-rs, ash,
  wayland-rs, openh264 built from source); only `gliff-server` would be
  needed in a guest (`cargo build -p gliff-server`), still an ongoing upkeep
  for a 0.x project whose protocol already broke once.

Both models: not now as a display path, possibly later as an optional
guest package for remote access, and design ideas worth borrowing (the lazy,
typed clipboard with files and offer serials; the private output sized to the
client window, which display-sync already resembles). sol alone: gate any
packaging behind one disposable CPU-tier experiment with a Linux client.
MiMo alone: audit Omarchy's gliff additions at the next bump. Dismissed:
MiMo's worry that the indicator misleads in the guest (it lights only while
a `gliff-server` runs).

### Background: Roguix as a gliff remote machine

Requested 2026-10-10 ("the real use for Roguix would be different: Roguix as
a remote machine, with gliff-server in the guest, reached from another
computer with Hyprland, e.g. an older x86_64 machine running Roguix; ask
the models"). Investigated read-only on 2026-10-10 against gliff v0.3.0
(omacom/gliff `7bc69d0c67`), Guix `7e74121a40`, Omarchy `9d48fc402e`;
consulted sol and MiMo (round 20261010-002509-0b0d).

Short answer: feasible only as an experiment for now. Reaching the guest
needs no app change, packaging is mechanical but large, and the unknown that
decides it is whether capture and CPU encoding work fast enough inside the
VM. The x86_64 client side does not exist yet.

- Reaching the guest: the correction to "Background: gliff" is that the
  launcher already has a Bridged network mode (socket_vmnet helper, own LAN
  address) whose opt-in "Allow SSH connections from the LAN" starts the
  guest's sshd for that boot (`macos/run-qemu-gpu.sh`, `QEMU_NETWORK_SSH`;
  the guest side is `roguix-ssh-access` in `integrations.scm`). In NAT mode
  the forward binds `127.0.0.1:2222` only, but gliff runs plain `ssh`, so a
  ProxyJump through the Mac works with no change. Neither path was tested
  with the Guix guest. gliff-server finds Hyprland from `XDG_RUNTIME_DIR`
  (it does not need `WAYLAND_DISPLAY`), which an ssh login gets from elogind;
  not verified in the guest.
- Packaging: `gliff-server` alone pulls 125 crates (`cargo tree -p
  gliff-server --target aarch64-unknown-linux-gnu`; 184 for the whole
  workspace with the GTK client). Guix at our pin has the Cargo.lock importer
  (`guix import crate --lockfile`, `define-cargo-inputs`), so the crate list
  is generated into our channel. Even the CPU path links libva
  (`crates/gliff-va/build.rs` requires libva >= 1.20 and libva-drm) and ash;
  both are available in Guix, so no patching is needed. `openh264-sys2`
  builds OpenH264 from bundled source. Upstream's PKGBUILD is x86_64 only;
  aarch64 is untested upstream.
- Encoding in the guest: no Vulkan or VA-API under VirGL, so gliff takes its
  CPU tier: it maps the captured GBM buffer, converts BGRA to I420 with
  scalar code (the AVX2 kernels are x86_64 only, `gliff-sw/src/convert.rs`)
  and runs OpenH264 on up to four threads. That tier sends 4:2:0, so it
  gives up gliff's sharp-text 4:4:4 unless `--full-chroma` doubles the
  work. Upstream's ~10 ms per 1080p frame is a Ryzen 7840U figure; nothing
  is measured on aarch64 vCPUs. Capture goes through ext-image-copy-capture
  into GBM buffers on the render node; whether that and the CPU map work on
  VirGL is unverified.
- The client machine: Roguix is aarch64 and VM-only today (VirtIO initrd
  modules, removable GRUB EFI, packages with `supported-systems` aarch64),
  so "an older x86_64 Roguix" is a separate port. Guix's linux-libre ships
  no GPU firmware, so an AMD client would likely decode on the CPU too. The
  gliff client needs GTK4 and libadwaita, which Guix has.
- Omarchy: 9d48fc402e adds `gliff` to the base packages, a migration, and a
  bar indicator whose `probe.sh` pgreps the user's `gliff-server` and reads
  `SSH_CONNECTION` from `/proc`. Our pinned Omarchy (`c668141e9c`) has none
  of it; with a packaged `gliff-server` the indicator would just work.
- Alternative: wayvnc 0.10.1 is in Guix at the pin, CPU-only by design and
  works with any VNC client.

Both models: the strongest argument against is the workload placement (the
Mac renders, the guest copies and software-encodes on vCPUs, an older machine
decodes), so test feasibility in the guest before packaging anything, use
NAT with ProxyJump rather than LAN-exposed sshd, and treat an x86_64 Roguix
as a separate project. sol alone: fix pass thresholds before the test, count
jitter from TCP over ssh and VM scheduling, and the CPU tier loses 4:4:4.
MiMo alone: wayvnc as the zero-risk baseline (verified packaged), and two
cheap probes first (capture with a CPU map, OpenH264 speed) before building
gliff at all. Dismissed: MiMo's "3-5x slower" estimate (not measured), its
suggestion to patch out gliff-va and ash (libva and the Vulkan loader are in
Guix), and its version-skew worry (our pinned Omarchy has no gliff at all).

### Background: choosing the next proposals

Asked 2026-10-09 ("choose with the models"); consulted sol and MiMo (round
20261009-173426-9b1a) with each item's evidence, value and cost. Recommended
order for "Next, in order"; the coordinator moves the items:

1. Drop the old image GC root (`/root/b38-image.raw`, already exported) that
   keeps the builder disk at 39 GiB: remove it, `guix gc`, `fstrim`
   (README procedure), and check the allocated size after. Minutes, about
   20 GiB back. MiMo: a prerequisite for any further guest build, which
   needs about 40 GiB of transient room.
2. "Make test VM state roots small and remove them": docs only, stops a
   repeat of the 19.7 GiB duplicate. sol: also require checking that the
   clone succeeded and deleting the root after a failed run.
3. "The factory image still comes out almost fully allocated", time-boxed
   (about an hour) and before a smaller image: no guest build, up to about
   8 GiB per factory image. MiMo: try writing the decoded stream through
   `dd conv=sparse` to tell zstd's granularity from APFS. Not urgent while
   the factory image is deleted; a reset re-extracts it.
4. "Build the image with a smaller --image-size": both keep it after 3,
   since sparse extraction cannot free the zeros inside the builder (store
   copy, `partition.img`). Size with headroom from the measured closure,
   not the 11.5 GiB in use (MiMo suggests about 16 GiB). Existing VMs keep
   their disks, so the gain comes with new factory images.
5. "Super+Space sometimes needs a second press": triage only first
   (reproduce, check Omarchy's issues); the most user-visible item, but a
   local patch of Omarchy's menu state should wait for the cause.

Park: "The shutdown screen shows Hyprland's startup log" as its own rebuild
(both: ride along with item 4's guest build only if it is a small change),
and "Give the builder a disposable scratch disk" (both: no capacity gained,
a builder-start change, and a smaller image makes it worth less).

Where they differed: nowhere on the order; MiMo added the dependency of
item 4 on item 1. Dismissed: MiMo's "a smaller image shrinks the download"
(zeros compress to almost nothing) and its worry that a reconfigure runs on
a near-full root (`roguix-grow-root` grows the root at boot, so only the
first boot runs inside the image size).

### Background: data stored twice

Investigated 2026-10-09, read-only (consult round with sol and MiMo).
Physical sharing was measured by mapping each file's data ranges
(`SEEK_DATA`/`SEEK_HOLE`) to device offsets with `F_LOG2PHYS_EXT` and
intersecting them, checked on a test file (a `cp -c` clone shared 100%, a
plain `cp` or `cat` copy 0%), plus SHA-256 for equal contents. No APFS
local snapshots held anything. Nothing the repository's tooling makes is
a real copy:

- The factory image and the VM disk share 18.7 of their 20.0 and 21.0 GiB;
  the image owns 1.4 GiB, the disk 2.3 GiB. The image predates the sparse
  extraction (a8dae12), so its 8.65 GiB of zeros (offsets 12 to 20 GiB) are
  allocated and shared with the disk; trimming the guest alone cannot free
  them while the image exists.
- The installed app and the main checkout's development app hold the same
  `disk.raw.zst` as one APFS clone (`make install` uses `ditto`,
  `build-app.sh` uses `cp -c`); each bundle owns under 0.11 GiB.
- `build/guix` in a checkout is shared with its own development app; a
  newer `build/guix` that no app embeds yet owns its 2.77 GiB.
- The builder disk (39 GiB allocated) and its 1.25 GiB backing image hold
  no Mac-side duplicate; exports are removed after packaging, and
  `omarchy-qemu-gpu.*` directories under `/tmp` are 16 KiB each and went
  away when their VMs ended.
- The real duplicate was a worker's throwaway state root (see "Make test VM
  state roots small and remove them" under Proposed): about 19.7 GiB until
  that worker deletes it.

Decided and done 2026-10-09: the factory image was deleted (no process had it open); a reset or new VM re-extracts it.

### Background: large VM files

Investigated 2026-10-09, read-only (sizes apparent / allocated; consult
round with sol and MiMo). The factory image and the VM disk are in the
app's data folder under `VM/v1/guix/`.

- Builder disk `.build/guix-validation/builder.qcow2` (82 GB file length,
  64 GiB allocated, 90 GiB virtual): a qcow2 overlay on the official Guix VM
  image, attached with `discard=unmap,detect-zeroes=unmap`; it holds the
  builder's store, GC roots and build directories. It was 25 GiB after
  `guix gc` and `fstrim` and grew about 40 GiB during the paused image build:
  the Guix image pipeline (`gnu/build/image.scm`, `gnu/system/image.scm` at
  the pin) copies the closure into a temporary root (`deduplicate? #f`),
  builds `partition.img` as its own store item, assembles the disk with
  genimage in a build directory and `copy-file`s the 20 GiB result into the
  store (zeros become unmaps on the host, but use real blocks in the
  builder's ext4). Blocks the guest frees stay allocated in the qcow2 until
  `fstrim`. Deletable now: no, it is paused mid-build and holds the store;
  losing it means a new builder and downloading the store again.
- Factory image `images/<identity>.raw` (21 GB / 20 GiB): the bundled
  `disk.raw.zst` (2.8 GiB) expanded once by `zstd -d -o`, which writes the
  8.65 GiB of zeros in it as data. It is needed only to create or reset a VM.
  Deletable now: yes, but it frees only about 0.3 GiB (the VM disk shares
  the rest), and a later reset re-extracts it in full.
- 2026-10-09: new factory images keep their zeros as holes (11.4 GiB
  allocated). `zstd --sparse` only seeks over zeros, and APFS allocates
  zeros for a skipped gap shorter than about 16 MiB, and for some longer
  ones as well (`dd conv=sparse` lost the same runs; a presized target was
  not reliable either); the helper now punches every zero block with
  `F_PUNCHHOLE` after decoding.
- VM disk `disks/current/disk.raw` (64 GiB / 21 GiB): an APFS clone of the
  factory image extended sparsely to 64 GiB; only 0.27 GiB of its first
  20 GiB differ from the factory image, plus 0.73 GiB written beyond it, so
  it owns about 1 GiB of its own. Attached without `discard`, so it never
  shrinks. Deletable: no, it is the user's VM.
- 2026-10-09: removing the last old image root (`/root/b38-image.raw`,
  superseded by the exported image), `guix gc` (43 GiB freed, `/` from
  35 to 13 GB used) and `fstrim -av` took the builder disk from 39 GiB
  to 12 GiB allocated (`du -h`).
- Try Omarchy (checked 2026-10-09 on `upstream/main` 3c6056d and its
  v0.5.1 release; consult round with sol and MiMo): no sparse handling
  anywhere in its history. Its guest is a 6 GiB ext4 image (`mke2fs -d`,
  `zstd -12`); since 2026-10-02 it keeps no factory image and runs
  `zstd -d -f -o` (no `--sparse`) straight into the working disk, verifies
  SHA-256 and grows the file sparsely; the disk is attached without
  `discard`. The v0.5.1 image has 1.14 GiB of zero 4 KiB blocks in 12 runs
  (1.12 GiB in 4 runs over 16 MiB), and with its bundled zstd 1.5.7 both
  `-d -o` and `-d --sparse -o` allocated the whole 6.0 GiB. So it has the
  same waste, about 1.1 GiB (19%) per fresh disk or reset, of which an
  unknown part is ext4 free space the guest fills soon anyway. Our punch
  fits it (its helper already has the SHA-256 and sync commands); the
  smaller variant would punch inside the helper's existing SHA-256 pass,
  and a punch failure should not fail provisioning there.

### Background: Command-Space

Reported 2026-10-03: Command-Space does nothing in the guest, and
Command-Tab switches Mac apps. Command-Space was a host key remapper taking
the chord before QEMU's event tap; `docs/mac-keyboard.md` ("Host tools that
take a chord first") explains how to exempt the VM window. Command-Tab is
the "Send Command-Tab to Roguix" setting.

### Background: the Accessibility grant

The Accessibility grant still matters for the rest:

Command-to-Super mapping of system shortcuts needs the Accessibility
permission (QEMU's full-grab CGEventTap; `FocusedCommandSuperBridge.swift`
is never started); without it the app starts the VM without the mapping and
only logs a warning. Releases, and development builds made without
`make signing-identity`, are signed ad hoc, so their designated requirement
is the cdhash (`codesign -d -r-` shows `designated => cdhash H"..."`): every
rebuild or update is a new identity for TCC, and the earlier grant no longer
applies, even if System Settings still shows it on. Development builds
signed with the local identity have `certificate leaf = H"..."` instead,
which stays the same across rebuilds.

Diagnosed 2026-10-07 with the maintainer at the Mac (macOS 27): the
hypothesis holds. QEMU's stderr (the launcher log) now has `[event-tap]`
lines (the grant as QEMU sees it, tap creation, enabled state, re-enabling,
the first event, captured Command chords) and the helper logs
`Accessibility trusted` to os_log (`dev.tryroguix.native`, category
`input`). Evidence:

- The installed build from 2026-10-03 was ad hoc
  (`designated => cdhash H"3c8d9c09..."`); its row was off and the start
  menu showed No.
- Certificate-signed build, granted once: `Accessibility trusted: yes`,
  `Created the tap; enabled: yes`, and Command-Space (key code 49) and
  Command-Return (36) `captured for the guest`; Roguix's menu and terminal
  opened. TCC: `authValue=2, authReason=4`.
- Rebuilt with `FORCE=1` (new cdhash, same certificate requirement) and
  reinstalled: still trusted without asking again, Command-Space captured.
- Ad-hoc build (`DEVELOPMENT_SIGN_IDENTITY=-`) over the same row: denied,
  `authValue=0`; tccd logged `Failed to match existing code requirement`
  with the stored `certificate leaf` requirement against the new cdhash.
- With the grant in place the tap was never disabled by macOS and no
  chords escaped, so secure input and re-enabling were not the cause.

- Diagnose (done 2026-10-07, see above): run only `~/Applications/Try Roguix.app`; check the start
  menu's Accessibility row, the `[input-bridge]` warning, and TCC denials
  (`log stream --predicate 'subsystem == "com.apple.TCC"'`). Log in the
  process that installs the tap: `AXIsProcessTrusted()`, tap creation,
  enabled state, callbacks. If the grant is fine, check tap re-enabling
  after `tapDisabledByTimeout`/`ByUserInput`, secure input
  (`ioreg -l -w 0 | grep SecureInput`), and that the tap swallows the event
  so Spotlight does not get Command-Space.
- Development builds: done; `make signing-identity` creates a persistent
  local self-signed identity in a dedicated keychain and `make app` signs
  with it (`macos/README.md`, "Development signing identity").
- Releases: until there is a Developer ID, every ad-hoc update loses the
  grant. Tell the user after an update and offer a user-triggered
  re-grant (`tccutil reset Accessibility dev.tryroguix.native`, then the
  prompt); never reset automatically. A persistent self-signed release
  certificate would also keep grants across updates on other Macs, without
  solving Gatekeeper.

### Background: the minimum guest size fix upstream

Offered 2026-10-07 as https://github.com/omacom/try-omarchy/pull/325; drop
our `qemu-cocoa-minimum-guest-size.patch` once it lands upstream or our
firmware has the EDK2 fix below, whichever comes first.

`qemu-cocoa-minimum-guest-size.patch` works around a firmware bug that
upstream Try Omarchy shares through the same dynamic-display patch and
firmware. Investigated 2026-10-07 ("isn't this a problem further upstream,
i.e. QEMU?"): it is an EDK2 bug, already fixed there, that QEMU 11.1.x still
ships.

- QEMU forwards any size, by design. Unpatched `ui/cocoa.m`
  (`updateUIInfoLocked`, l.524-568, QEMU 11.1.1 c3d48b7) already sends the
  window frame times the backing scale through `qemu_console_set_ui_info`,
  but the window is user-resizable only with zoom-to-fit, and at 2x it would
  have to be under about 320 points wide or 238 high to hit it. GTK
  (`gd_set_ui_size`), SDL2 (`SDL_WINDOWEVENT_RESIZED`), VNC (SetDesktopSize)
  and D-Bus forward sizes with no minimum either. Only the dynamic-display
  patch makes small sizes routine.
- virtio-gpu keeps the size across a guest reset on purpose: it models the
  monitor. `virtio_gpu_ui_info` stores `req_state`
  (`hw/display/virtio-gpu-base.c` l.101-122), and `virtio_gpu_base_reset`
  (l.25-39) clears only the scanouts.
- The bug: EDK2 `OvmfPkg/VirtioGpuDxe/Gop.c` `GopInitialize`
  (edk2-stable202408) adopts the host's preferred mode as
  `PcdVideoHorizontalResolution`/`VerticalResolution` with no lower bound,
  and `GraphicsConsoleDxe` then fails
  `ASSERT ((MaxColumns >= 80) && (MaxRows >= 25))` (`GraphicsConsole.c`
  l.267) and spins. QEMU builds the aarch64 firmware as DEBUG
  (`roms/edk2-build.py`, default target DEBUG). In a RELEASE build the
  ASSERT is compiled out, `DeltaX`/`DeltaY` underflow, and VirtioGpuDxe's
  `GopBlt` bounds check (l.604-609) rejects the drawing, so text is probably
  just missing (read from source, not run).
- Fixed in EDK2 by Gerd Hoffmann's 58035e8b5e (2024-08-30) "OvmfPkg/
  VirtioGpuDxe: ignore display resolutions smaller than 640x480", first in
  edk2-stable202411. QEMU bundles edk2-stable202408 up to v11.1.2
  (`roms/edk2-version`); QEMU master moved to edk2-stable202608 on
  2026-09-01 (e7764c7cda), so the fix ships with QEMU 11.2. The
  GraphicsConsoleDxe ASSERT itself is still in EDK2 master, but VirtioGpuDxe
  no longer reaches it.
- Reproduced on unpatched Homebrew QEMU 11.1.2 with its bundled firmware and
  `-device virtio-gpu-pci,xres=732,yres=412` (the same `req_state` the UI
  sets) and no disk: that ASSERT on the serial console, while 1280x800 reaches
  the boot manager. With QEMU master's edk2-stable202608 firmware, 732x412
  gives no ASSERT and the same 160x42 console as 1280x800 (the firmware's
  1280x800 default). Not run through a real Cocoa window resize.
- Models (sol, MiMo) agreed QEMU should not clamp `ui_info`, reject small
  modes in virtio-gpu or reset `req_state`: that would misreport the monitor
  for guests other than EDK2. Both preferred shipping the newer firmware over
  the UI clamp; sol added that dropping the clamp must depend on the firmware
  actually loaded, not the QEMU version, and that a request to QEMU stable to
  backport the firmware is possible but optional. MiMo's out-of-bounds-write
  worry for RELEASE builds does not hold (the `GopBlt` bounds check above).
  Note that EDK2's floor is 640x480 and the clamp's 800x600.

So no report to QEMU or EDK2 is needed. PR #325 stays useful for Try
Omarchy while it ships QEMU 11.1.x firmware and becomes unnecessary with QEMU
11.2's.

Tried 2026-10-07 (approved item "Ship firmware with the VirtioGpuDxe fix and
drop the clamp patch"): QEMU master's edk2-stable202608 firmware (e7764c7cda)
stalls in BDS under HVF on QEMU 11.1.x and never reaches GRUB, with our QEMU
and with unpatched Homebrew QEMU 11.1.2 (1 and 4 vCPUs, with and without the
GPU, `-bios` or pflash with aarch64 vars); under TCG it boots Roguix to the
initrd, and the old firmware boots under HVF. Decided 2026-10-07: wait for
QEMU 11.2 and move the runtime to it as a whole (QEMU with its own
firmware), then check a small-window reboot without the clamp and drop
`qemu-cocoa-minimum-guest-size.patch`. Not chosen: building EDK2
202411+ ourselves, or reporting the HVF stall upstream before 11.2 is out.

Asked 2026-10-07: "what do you think? Since the bug is upstream, in EDK2,
and we made the PR to Try Omarchy? Ask the models." The PR (open, no
response yet) describes the ASSERT and the dynamic-display interaction but
not that the bug is EDK2's, already fixed, or when the patch can go.
Consulted sol and MiMo (round 20261007-193715-35ce).

Recommendation: keep the PR as a temporary workaround and edit its
description (draft below). Closing it leaves Try Omarchy's users with the
hang until QEMU 11.2; an issue alone hands the same work to its maintainers,
and they cannot swap the firmware on 11.1.x either because of the HVF stall.

- Agreed (both): option (a); the removal condition is the firmware the app
  actually loads containing 58035e8b5e, verified by a small-window reboot
  under HVF, not the QEMU version number; backporting the whole newer
  firmware to QEMU 11.1.x stable is unrealistic and would hit the HVF stall;
  no new EDK2 report is needed.
- Both questioned the 800x600 floor: EDK2's own floor is 640x480 and the
  console needs 640x475, so 640x480 would cost less resolution; the patch
  gives no reason for the margin. Changing it means a new patch revision and
  re-test, so it is listed as an option.
- Both said the HVF stall of edk2-stable202608 on QEMU 11.1.x (unpatched
  Homebrew QEMU too, fine under TCG) is worth reporting now. That differs from
  the decision above to wait for QEMU 11.2; left as decided unless the
  maintainer reopens it.
- sol only: ask QEMU stable for the single EDK2 fix rather than a new
  firmware release (unusual for QEMU's bundled firmware; noted).
- MiMo only: a window minimum size (`contentMinSize`, 320x240 points at 2x)
  instead of a QEMU patch, which the PR should say why it did not use (it
  keeps windows freely resizable with zoom-to-fit); cherry-picking
  58035e8b5e onto edk2-stable202408 and building that firmware (still an
  EDK2 build of our own, not chosen above).
- Dismissed: MiMo's points-versus-pixels worry (the clamp divides 800x600 by
  `backingScaleFactor`, so it is in pixels); both asked to state that the
  reboot was not reproduced on upstream's guest, which the PR already says.

Paragraph added to PR #325's description on 2026-10-08, at the end of "What
changed and why":

> The root cause is in EDK2, not in this repository or QEMU:
> `OvmfPkg/VirtioGpuDxe` adopts the host's preferred mode with no lower
> bound. Gerd Hoffmann fixed it in 58035e8b5e ("OvmfPkg/VirtioGpuDxe: ignore
> display resolutions smaller than 640x480", first in edk2-stable202411).
> QEMU 11.1.x still bundles edk2-stable202408; QEMU master moved to
> edk2-stable202608, so the fix ships with QEMU 11.2. Swapping in the newer
> firmware on QEMU 11.1.x is not an option: under HVF it stalls in BDS before
> GRUB (also with unpatched Homebrew QEMU 11.1.2; it boots under TCG). This
> patch is therefore a temporary workaround: drop it once the firmware the app
> loads contains that commit (expected with the move to QEMU 11.2) and a guest
> reboot in a window shrunk below 640x480 pixels boots under HVF without it.

Linked on 2026-10-08 (requested: "why not link it in the PR?"): in that
paragraph 58035e8b5e links to its EDK2 commit, edk2-stable202411 and
edk2-stable202408 to their EDK2 release pages, and "moved to
edk2-stable202608" to QEMU's e7764c7cda ("edk2: update binaries to
edk2-stable202608", the prebuilt firmware QEMU ships; b8f0e2d4f4 two minutes
earlier only updates the `roms/edk2` submodule). The rest of the description
is unchanged.

### Background: the text console size

Approved 2026-10-08.

Found 2026-10-08 by the initial-window worker: on a fresh disk the guest
stays at 2560x1440 at the login screen instead of following the window size
(before and after the initial-window fix). Unverified beyond that run.

Diagnosed 2026-10-09 (dev build of 79bff87, image `3b3fb5b9…`, windowed,
fresh disk, Apple M1 Pro): this is the text console, not a host bug.

- At the first-start setup on tty1 the guest surface was 2560x1440 while the
  window's content was 1296x729 pt (2592x1458 px). Resizing the window to
  900x506 pt left it at 2560x1440; QEMU only scaled it, so the text shrank.
- After the setup, Hyprland came up at 1800x1012, the window's pixels, and
  a resize to 1199x674 pt gave 2398x1348: `roguix-display-sync` works, but
  it runs only in the Hyprland session (`omarchy.scm`).
- The console mode is fixed by the kernel argument
  `video=Virtual-1:2560x1440M` (`guest/guix/modules/roguix/system.scm`),
  chosen in 96793e9 because Terminus 16x32 at the window's Retina pixels was
  too small and 1920x1080 scaled up too large. The host's EDID already offers
  the window size as the preferred mode at boot (d398b7e), so dropping the
  argument would start the console at the window's pixels. Even then fbcon
  would not follow later resizes: the DRM fbdev emulation keeps the
  framebuffer it allocated at boot. The same mode is what the shutdown
  screen returns to (see the shutdown font item).

Decided 2026-10-09: keep 2560x1440 ("leave 2560x1440 and close the item"); the desktop already follows the window.

### Background: the lost first menu click

Fixed 2026-10-09 by substituting Omarchy's `Menu.qml` at build time so the
rows are rebuilt only when a guard result changed (d833b4e), and offered
upstream as https://github.com/omacom/omarchy/pull/14740; drop the
substitution once Omarchy takes it.

### Where does the space for the renamed guest image come from?

Asked 2026-10-18 by the coordinator. [t-xzufmvj7] step 2 needs a guest image:
the builder takes its disk from the pendrive, so about 27 GB of store growth
stays there, but the export (a 16 GiB raw image), `make guix-package` (about
4 GB in `build/guix`) and `make app` (about 4 GB) land on the M1 and need
about 24 GB of its free space. Between 12:00 and 12:20 the M1's free space
fell from 58 GiB to 22 GiB and kept falling about 2 GB per minute, because
another session is downloading into `~/.cache/huggingface` (45 GB to 48 GB
in 45 seconds, `du` measured), while herdr's own worktrees hold 28 GB of
build trees. The pane worker `omaguix-build` (pane wD4:p43) is held before
the build for that reason. Nothing here is this repository's data.
Options: hold the build until the M1 has about 40 GiB free again (the
coordinator re-checks before each heavy step; other sessions' downloads and
builds decide when) | free space now by deleting a cache or tree the user
names, which the coordinator then announces to the sessions that use it |
offload a set the user picks to the 2010 MacBook | park the rename and go on
with [t-dopemmpz], which needs the MacBook and no local disk.
Decided by the user 2026-10-18: offload to the 2010 MacBook (the third
option), leaving the set to the coordinator. Doing, in pane worker
`omaguix-build` (pane wD4:p43, task /tmp/omaguix-build-task2.md): the M1's
old packaged Roguix guest (3 files under `build/guix`) and the app's guest
disk `try-roguix-app-disk.raw` on the pendrive (68 GB apparent, 42 GB on
disk) go to `~/m1-archive/` on the MacBook over port 42022, verified with
an rsync checksum pass and a SHA-256 cross-check before the local copy is
deleted; then the image build runs with the builder disk and the export
both on the pendrive, so the M1 only needs `make guix-package` and
`make app` (about 7 GB). The guix-x86_64-iso-omguix coordinator was told
the machine will be used for the transfer. Guards unchanged: 15 GiB free
on the M1, 5 GiB on the pendrive.
Asked the models 2026-10-18 (round 20261018-122501-1ff8: sol, MiMo, Argon)
whether the pendrive archive is needed and which images it should keep.
Acted on, all three agreeing: never delete the app's guest disk before a
verified second copy exists; the pendrive keeps the builder disk and its
growth allowance and nothing else of ours; the image export goes straight
to the M1 (the running builder already does: its export share is the
worktree's `.build/guix-validation/export`, checked in the QEMU command
line); free space is checked at build, export and package boundaries.
Acted on from MiMo alone: inspect the guest disk before any deletion; no
e2fsprogs on the M1, so the archive is the cheaper way to keep it.
Dismissed: Argon's claim that runtime writes to a zstd qcow2 "easily blow
past 34 GiB" (the growth is the bytes the guest writes, the compression
only makes the base smaller), and its ballast file, which reserves space
by taking it from other sessions.
Decided by the coordinator on that basis: do not archive the app disk while
the build runs, because it shares the USB stick with the builder's disk and
a 42 GB read next to the VM's writes risks stalling the guest; the build
and export go first, then the archive with the checksum pass and a SHA-256
cross-check, then deleting the pendrive copy. If the pendrive drops below
8 GiB free, stop the build at a step boundary, archive and delete the app
disk, and resume (the store keeps finished derivations). The stale
`exports/src-omaguix-rename` copy (828 KB) is deleted; the main checkout's
`build/guix` stays; `try-omabend-builder.qcow2` is another project's and is
not touched.
Builder diagnosis 2026-10-18 (coordinator, while the worker's first attempt
sat at "console not up"): the builder disk and the pendrive are fine
(`qemu-img check` on it: no errors). The guest stops at a login prompt with
the 9p shares unmounted, which `guest/guix/README.md:131-135` documents for
a builder boot after a power-off, and every `vm-run` attempt made while
GRUB's menu was still counting down kept the guest in that menu: GRUB reads
the sent line as keystrokes, resets its countdown and polls the UART, so a
vCPU spins in `pl011_read` (sampled) and the guest never boots (a serial log
of the same disk with no client shows GRUB, fsck and `gnu login:`). The
stuck builder was stopped through QMP `quit`; the recovery handed to the
worker is: start the builder, read the console once until `gnu login:`,
log in as root, mount `project` (read-only) and `export`, then run
`vm-run`. The worker also adds that trap and its avoidance to the
README's "Builder VM" section.
Checked 2026-10-18: `df -h /`, `du -sh ~/.cache/huggingface` twice 45 s
apart, `du -sh ~/personal_projects/herdr-worktrees`, and
`/Volumes/Samsung128GB` at 34 GiB free.

## Disk offload 2026-10-18

The M1's disk reached 94% used (27 GB free), so three VM disks were moved off
it to the pendrive at `/Volumes/Samsung128GB/exports/20261018-disk-offload/`
(the M1 paths are now empty):

| what | where it was | where it is now |
| --- | --- | --- |
| try-roguix builder disk | `personal_projects/guix/try-roguix/.build/guix-validation/builder.qcow2` | `try-roguix-builder-compressed.qcow2` (zstd-compressed qcow2) |
| the app's guest disk | `~/Library/Application Support/Try Roguix/VM/v1/guix/disks/current/disk.raw` | `try-roguix-app-disk.raw` |
| try-omabend builder disk | `personal_projects/guix/try-omabend/build/builder/builder.qcow2` | `try-omabend-builder.qcow2` |

Restore with `rsync -aHS --whole-file --partial` back to the same path (the
compressed builder has to be converted back first: `qemu-img convert -O qcow2
try-roguix-builder-compressed.qcow2 builder.qcow2`, which needs about 80 GB of
free space). The pendrive is an APFS volume and must be mounted; it was not
mounted by the time the copy started, so the first copy wrote a non-sparse
81 GB file and filled it — the compressed copy replaces it. The pendrive directory holds a `MANIFEST.txt` with the same table and the restore steps.
This note is here because the move was done by the lang-for-ai coordinator, not by
this repository's; nothing else about this project changed. After the move the M1
has 77 GB free instead of 27 GB.
Builder disk back on the M1 2026-10-25: the pendrive slipped out while the
builder ran from it (guest I/O errors, ext4 remounted read-only; the boot fsck
repaired it, only `/var/log/messages` lost writes, and `guix gc
--verify=contents` found the store intact). The pendrive copy is untouched; the
builder now runs from `.build/guix-validation/builder.qcow2`, a compressed
`qemu-img convert` of it (6.5 GB, `qemu-img compare` identical).
