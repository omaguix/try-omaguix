# TODO

## Next, in order

### KosmicKrisp and Venus: Vulkan in the Roguix guest on macOS

Requested 2026-10-10 ("add the KosmicKrisp and Venus research; ask the
models"). KosmicKrisp is LunarG's Vulkan driver on Metal for macOS, in Mesa.
Find out read-only: its state and versions, whether QEMU's virtio-gpu Venus
(virglrenderer) runs on macOS on top of it, what that would give the guest
(Vulkan for the desktop and apps, video extensions for encoding), and what
moving the runtime from VirGL on ANGLE would cost. Consult the default
models; record the answer and options; adopt nothing without approval.

### Roguix as a gliff remote machine

Requested 2026-10-10 ("the real use for Roguix would be different: Roguix as
a remote machine, with gliff-server in the guest, reached from another
computer with Hyprland, e.g. an older x86_64 machine running Roguix; ask
the models"). Find out read-only what that needs: packaging gliff and
gliff-server for Guix (Rust, dependencies, aarch64 and x86_64), how the
guest is reached over ssh from another machine (Try Roguix forwards ssh only
to the Mac's loopback), CPU encoding without Vulkan video in the VM, and
what Omarchy's own gliff integration (9d48fc402e) expects. Consult the
default models; record the answer and options; adopt nothing without
approval.

### Super+Space sometimes needs a second press to open the menu

Approved 2026-10-09 (chosen with the models, see "Background: choosing the next proposals").

Found 2026-10-09 (both the old and the new image, about 1 in 20): after an
action closed the Omarchy menu, Super+Space sometimes does not open it on the
first press. Likely Omarchy's own open/close state; reproduce and check
upstream first.

Diagnosed 2026-10-09 (worker, no guest change yet): not the menu's state and
not our `Menu.qml` substitution, but Omarchy 4.0.4's IPC path. Super+Space
runs `omarchy-menu toggle`, which runs `omarchy-shell`, which runs a `qs ipc`
client under `timeout --kill-after=1s 2s`. On a throwaway VM (windowed app
from this tree, keys through QMP, Hyprland's layer events and a traced bind)
that chain took 0.3-4 s per press (`qs --version` alone 150-650 ms; the host
was heavily loaded by builds). When the client is killed, `omarchy-shell`
exits 1 ("not responding") and the toggle is lost (3 of 10 such presses) or
reaches the shell 0.6-3.5 s later. After an action closed the menu, 3 of 80
and 10 of 81 presses timed out; with the bind run under
`OMARCHY_SHELL_IPC_TIMEOUT=30s` (a test value), 0 of 84 failed and the longest
call took 3.7 s. Upstream has no issue for it; `quattro` replaced the path
after 4.0.4 (no release since): #13418 binds menus and panels as Hyprland
global shortcuts that the shell handles without starting a process (about
110 lines), #13435 sends `omarchy-shell` calls over the shell's own socket.
The defect is the kill itself: a killed client leaves a non-idempotent
toggle in an unknown state (lost or late), whatever the timeout value, so a
longer timeout is no fix. Consulted sol and MiMo (round
20261009-190242-e59a): both back removing the per-press process chain; sol
recommends the #13418 backport. MiMo's smaller alternative (a persistent socket
with request IDs and acknowledgements) is new machinery: #13435 alone is
+356 lines and still starts `socat` per press with a timeout. The #13418
handler is `onPressed` only, so a release cannot toggle twice. A press before
the shell has registered its shortcuts, or during a shell restart, reaches
no one; that is no worse than today, where `omarchy-shell` fails then too.
Fix, a guest change that needs a builder build: backport #13418 as a patch on
the pinned Omarchy (shell.qml, helpers.lua, the shortcuts list, the
bindings) and drop it when the pin includes it. Verify on a VM under host
load: hundreds of presses after menu actions, rapid double presses, presses
while the shell is busy, right after login and across a shell restart;
count the menu's open/close transitions per press (no lost and no double
toggles) and measure press-to-map latency.
Decided 2026-10-09: backport #13418 now (a patch on the pinned Omarchy, dropped when the pin includes it). The guest build waits until the image-size item is merged, so both land in one build.

## Proposed

### List gliff as not provided at the next Omarchy bump

Proposed 2026-10-10 (see "Background: gliff"). Omarchy 9d48fc402e
(2026-10-09) installs gliff by default (`omarchy-base.packages` and a
migration) and adds a status-only "Remote session" bar indicator. The pinned
Omarchy (c668141, 2026-09-15) predates it. When the pin moves past it, add
gliff to `docs/omarchy-packages.md` as not provided (no Guix package; its
upstream package is x86_64 only), check that the indicator stays dark and
quiet with no `gliff-server` installed, and leave the migration to the seed,
which marks shipped migrations done. Docs only, with the bump.

### Offer Try Omarchy the zero-block punch

Proposed 2026-10-09 (see "Background: large VM files"): Try Omarchy's
fresh working disk allocates about 1.1 GiB of zeros. Offer a small change
that punches whole zero blocks in its helper's SHA-256 pass after
decoding, framed modestly (initial footprint, contents unchanged), with a
measurement on its current main. Contacting upstream needs approval.

### omarchy-shell kills non-idempotent calls on a timeout

Proposed 2026-10-09 by the Super+Space worker, raised by sol and MiMo:
`omarchy-shell` runs `qs ipc` under `timeout --kill-after=1s 2s` and reports
"not responding" when it kills the client, but the call may already have
reached the shell, so a toggle is lost or applied late and the caller
cannot tell which. Other bindings and scripts still go through it after the
#13418 backport. A kill should mean "outcome unknown", never a failure to
retry; callers that need a state should ask for it (open or close, not
toggle). Check which default callers toggle, and offer it upstream.

### The shutdown screen shows Hyprland's startup log

Found 2026-10-07 by the shutdown-font worker and seen again 2026-10-09 with
the bold console font: at shutdown tty1 still shows the Roguix logo and
Hyprland's startup log, which `start-hyprland` printed there, and the
shutdown lines are written over its last line. Clearing tty1 when Hyprland
exits (or not printing the log there) would leave only the shutdown text.

### Give the builder a disposable scratch disk for builds

Proposed 2026-10-09; weigh it after the cleanup step above. The image
derivations copy the closure into a temporary root, an ext4
`partition.img` and a genimage temporary in guix-daemon's build directory.
Pointing the daemon's `TMPDIR` at a second qcow2 that is deleted after the
build would free those at once instead of waiting for gc and trim. It adds
no capacity (same APFS volume) and changes how the builder is started.

### Let the export drop every old image root

Proposed 2026-10-09 by the builder cleanup worker: `build.py --export`
removes only the exported image's GC root, so an older `/root/*.raw` root
kept a previous image pinned (the builder stayed at 39 GiB until it was
removed by hand). The export could also remove the other `/root/*.raw`
roots that point to a `-disk-image` store item.

## Needs a decision

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
