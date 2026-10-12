# TODO

## Next, in order

### Upgrade existing VMs across Guix pin bumps

Requested 2026-10-12 by the roguix-vps coordinator, approved by the
owner (review of the Roguix repositories, consult round
20261012-012022-7047; herdr decisions d-aqilyu75, d-fnkaqv5d, d-fe6dbtq2,
d-knq7b5mj, d-5m55urp7). Order: trust record, docs, release step,
upgrade path.
roguix-update (guest/guix/modules/roguix/omarchy.scm:483) tells users to
reset the VM when a release needs a newer Guix. Existing VMs should move to
the new pin keeping their settings and data, with a rollback. New users
are Try Roguix Mac app users for now; bare metal is not pursued.

### Rebase and re-test the Omarchy menu-rows PR

Asked 2026-10-12 whether https://github.com/omacom/omarchy/pull/14740 is
obsolete now that Omarchy opens menus through Hyprland global shortcuts
(https://github.com/omacom/omarchy/pull/13418, merged 2026-09-27, before
our PR). Round 20261012-202605-5528 (sol, MiMo, DeepSeek): not obsolete.
Global shortcuts only remove the qs IPC launch; on current main
openExistingMenu() still runs evaluateGuards() on every open and
guardProc.onExited still calls rebuildDisplay() unconditionally (checked
in shell/plugins/menu/Menu.qml). A reviewer
(https://github.com/omacom/omarchy/pull/14740#issuecomment-6130082381)
asked to rebase on https://github.com/omacom/omarchy/pull/15048 (merged)
and check the case still reproduces; https://github.com/omacom/omarchy/pull/14993
(open) rewrites rebuildDisplay's append. Do: rebase the PR branch on
current main, re-run the press-across-guard-exit test with and without the
fix opening through the real global shortcut, then reply to the reviewer
with the commit and numbers. If it no longer reproduces, say so and close
the PR. Placement, round 20261012-202819-4d50: right after the item in
progress, before the first release (sol, MiMo; rebase and repro are
short, the release takes hours); do not wait for #14993 (open, its
timing and shape unknown; DeepSeek alone would wait). Pushing the PR branch and replying are covered by the approved
upstream-offer of that item.

### First Roguix release through release.py

Decided by the user 2026-10-12 (d-evsasl4e): "yes, after the upgrade
path" item. Set `VPS_IMPORT=/usr/local/sbin/vps-import` in the local
`.env`, then run guest/guix/release.py for current try-roguix main: a
signed roguix-channel commit, roguixos/roguix's build-desktop.yml
dispatched with `channel_commit` (aarch64 and x86_64, hours), VPS import,
the closure check, then the signed release.json moves the channel's main.
Report the run ids and the release commit; on any failure, main stays.

### Offer the ANGLE multisample fix to startergo's virglrenderer tap

Decided by the user 2026-10-12: "yes, after acceptance". Proposed
2026-10-12 by the Metal worker (models: after end-to-end
acceptance, to startergo/homebrew-virglrenderer first): offer
macos/patches/virgl-angle-multisample.patch upstream once Metal is the
default and LibreWolf and Chromium pass (Metal became the default
2026-10-12, commit "macos: run guests on ANGLE/Metal by default"). Cost: a short PR; no build.

### roguix-update checks the release manifest

Follow-up of the release step (decision 0006, done 2026-10-12), decided by
the user 2026-10-12 (d-6ff4fe5q). roguix-update in a VM checks the
channel's release.json: it names HEAD's parent (the released commit) and
its commit changes nothing but release.json, so modules can only come
from a released commit. Needs a guest build.

### release.py resumes from an existing CI run

Follow-up of the release step, decided by the user 2026-10-12
(d-6ff4fe5q). An option to resume guest/guix/release.py from a finished
CI run of the same channel commit, so a failed VPS import or closure
check does not need a new multi-hour CI build. No build.

Note for both: the release step works only after roguixos/roguix adds the
`channel_commit` workflow input and the `split-*` artifacts (sent to the
guix-x86_64-iso-omguix coordinator 2026-10-12) and `.env` gets
`VPS_IMPORT` (the roguix-vps coordinator, 2026-10-12: installed at
`/usr/local/sbin/vps-import` on root@vps.frolow.dev port 1027, roguix
e1e2d64, also on root's PATH as vps-import; the release.py-resume worker
sets it in the local `.env`). roguixos/roguix's side is done (the
guix-x86_64-iso-omguix coordinator, 2026-10-12, roguix commit 356d2db1):
build-desktop.yml takes `channel_commit`, authenticates the channel,
uploads the `split-*` artifacts; not run in CI yet. The channel's main
(d610bc0c) lacks %roguix-reference-system, so the first run must be a
release.py run with a channel commit from current try-roguix.

### Send roguix-vps the store paths server/publish.sh published

Requested 2026-10-12 by the roguix-vps coordinator, passed on by the user:
roguix.frolow.dev moves to static, CI-signed substitutes (roguix decision
0001); before guix publish and its key leave the VPS, roguix-vps
backfills everything served today into the static tree. server/publish.sh
imported aarch64 items on the VPS without GC roots. Send roguix-vps the
list of every store path it published that is still meant to be served
(the publish.txt of each run, or a command that rebuilds the list), or
put them under a GC root such as /var/guix/gcroots/try-roguix/<name> on
the VPS and say so. Until then nothing is deleted on the VPS.

### Move Roguix to roguix.org

Asked 2026-10-12: "I bought roguix.org at Porkbun. Move it. Ask the
models." Round 20261012-191411-5986 (sol, MiMo, DeepSeek), plan decided by
the coordinator with the models: the website at roguix.org (GitHub Pages
or the VPS), substitutes at substitutes.roguix.org (all three; not a path
under the apex, not "cache"). Decided by the user 2026-10-12, overriding the models' 12-month alias:
"no, nobody uses it; switch it off": a clean cutover, roguix.frolow.dev is
turned off once substitutes.roguix.org serves, and the trust record names
only the new URL (no overlap release). The URL change still ships apart
from the publish key change. Decided by the user 2026-10-12 (d-2zft4rjx):
the publish key change is a clean cutover too, see "Trust two publish
keys during the move off the serving host". TLS for both names
before the release; CAA limited to the issuing CA; no mail on the domain:
null MX, `v=spf1 -all`, DMARC `p=reject`; DNSSEC only once stable.
Needs: DNS records at Porkbun (the owner, or an API key the owner
provides), the VPS vhost and certificate (the roguix-vps coordinator,
which owns the host and its static-substitutes move), then try-roguix's
trust record and docs. App update feeds stay where they are until checked.

### Tagline and topics: "Roguix: Omarchy on Guix System"

Asked 2026-10-12 (round 20261012-191411-5986): put "Roguix: Omarchy on
Guix System" in README and in the descriptions of roguixos/try-roguix,
roguix and roguix-channel, with a short "independent, not affiliated with
Omarchy" line in README (nominative use, no endorsement implied). Topics:
omarchy, guix, guix-system, hyprland on all three; macos and
virtual-machine on try-roguix. Repository descriptions and topics are
GitHub settings (gh repo edit); README is a docs commit.

## Proposed

### Accept Guix's Ungoogled Chromium on the Metal path

Split from the Metal item 2026-10-12 by the user's decision ("LibreWolf
first"): once roguixos/roguix's CI builds `ungoogled-chromium` for aarch64
(no substitute at the pin; a many-hour build), check it on `gl=es` like
LibreWolf (GPU compositing, raster, WebGL 2, no software fallback) and fix
what differs. Needs CI to build the package first.

### Let agents click in a VM and see the result: evaluate hypruse first

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

### Run Omarchy's acceptance suite on Roguix

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

### A reset erases the old VM before fetching the factory disk [t-cpdtxhhy]

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

### Register checks for herdr todo run [t-atkjktc5]

Proposed 2026-10-10 by the herdr coordinator: `herdr todo run` (verify,
cherry-pick, install, push) needs this repository's checks and install
registered in `.herdr/checks.toml`: `make test` as the check, `make install`
as the install step (only with the maintainer's go, since it replaces the
installed app), and what a guest build needs. Until then the coordinator
runs headless workers with `herdr worker start`, `wait`, `verify` and
cherry-picks by hand.

### Test gliff-server in the guest before packaging it [t-sakzbqb5]

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

### Compare wayvnc as the remote view [t-4vzb5lvt]

Proposed 2026-10-10 (see "Background: Roguix as a gliff remote machine").
wayvnc 0.10.1 is already in Guix at the pinned commit (`gnu/packages/vnc.scm`)
and needs no Vulkan or VA-API. Run it in the guest for one boot against the
same checks as the gliff test, so a choice is made between measured options.

### List gliff as not provided at the next Omarchy bump [t-76ot56gb]

Proposed 2026-10-10 (see "Background: gliff"). Omarchy 9d48fc402e
(2026-10-09) installs gliff by default (`omarchy-base.packages` and a
migration) and adds a status-only "Remote session" bar indicator. The pinned
Omarchy (c668141, 2026-09-15) predates it. When the pin moves past it, add
gliff to `docs/omarchy-packages.md` as not provided (no Guix package; its
upstream package is x86_64 only), check that the indicator stays dark and
quiet with no `gliff-server` installed, and leave the migration to the seed,
which marks shipped migrations done. Docs only, with the bump.

### Offer Try Omarchy the zero-block punch [t-5wxjylaq]

Proposed 2026-10-09 (see "Background: large VM files"): Try Omarchy's
fresh working disk allocates about 1.1 GiB of zeros. Offer a small change
that punches whole zero blocks in its helper's SHA-256 pass after
decoding, framed modestly (initial footprint, contents unchanged), with a
measurement on its current main. Contacting upstream needs approval.

### omarchy-shell kills non-idempotent calls on a timeout [t-3b46spbn]

Proposed 2026-10-09 by the Super+Space worker, raised by sol and MiMo:
`omarchy-shell` runs `qs ipc` under `timeout --kill-after=1s 2s` and reports
"not responding" when it kills the client, but the call may already have
reached the shell, so a toggle is lost or applied late and the caller
cannot tell which. Other bindings and scripts still go through it after the
#13418 backport. A kill should mean "outcome unknown", never a failure to
retry; callers that need a state should ask for it (open or close, not
toggle). Check which default callers toggle, and offer it upstream.

### The shutdown screen shows Hyprland's startup log [t-5nrn7cv4]

Found 2026-10-07 by the shutdown-font worker and seen again 2026-10-09 with
the bold console font: at shutdown tty1 still shows the Roguix logo and
Hyprland's startup log, which `start-hyprland` printed there, and the
shutdown lines are written over its last line. Clearing tty1 when Hyprland
exits (or not printing the log there) would leave only the shutdown text.

### Give the builder a disposable scratch disk for builds [t-4brvu3it]

Proposed 2026-10-09; weigh it after the cleanup step above. The image
derivations copy the closure into a temporary root, an ext4
`partition.img` and a genimage temporary in guix-daemon's build directory.
Pointing the daemon's `TMPDIR` at a second qcow2 that is deleted after the
build would free those at once instead of waiting for gc and trim. It adds
no capacity (same APFS volume) and changes how the builder is started.

### Let the export drop every old image root [t-edvvmbii]

Proposed 2026-10-09 by the builder cleanup worker: `build.py --export`
removes only the exported image's GC root, so an older `/root/*.raw` root
kept a previous image pinned (the builder stayed at 39 GiB until it was
removed by hand). The export could also remove the other `/root/*.raw`
roots that point to a `-disk-image` store item.

### Recheck Venus on macOS at the next virglrenderer release [t-zb7efvcb]

Approved 2026-10-10; waits for the next virglrenderer release.

Proposed 2026-10-10 (see "Background: KosmicKrisp and Venus"). When a
virglrenderer release after 1.3.0 contains the macOS Venus series (!1600,
!1601, !1602, !1635), check read-only whether it also settles host memory
on KosmicKrisp (!1685), whether Guix's Mesa has reached 26.2.4 or later,
and whether UTM still keeps the Linux desktop on VirGL; then update the
background and ask again. No runtime change.

### A time-boxed Venus experiment on a throwaway runtime [t-gh4i2jvb]

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

### Hardware H.264 encoding through VA-API and VideoToolbox [t-3fkebvn4]

Proposed 2026-10-10 (see "Background: KosmicKrisp and Venus"); only if CPU
encoding (OpenH264, gliff) is measured too slow in the guest. The route
independent of Vulkan: guest VA-API (Guix's Mesa builds its VA driver with
`-Dvideo-codecs=all`) over virgl's video protocol to a virglrenderer
patched to encode with VideoToolbox, as OmacVM does (#48). Needs
`-Dvideo=true` and a carried patch; measure CPU, latency and copies first.

## Needs a decision

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
