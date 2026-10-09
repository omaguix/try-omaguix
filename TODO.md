# TODO

## Next, in order

### Pass the VM's TRIM through to the Mac

Approved 2026-10-09 (the maintainer let the coordinator choose); proposed 2026-10-09. The VM disk is attached with `format=raw,cache=writeback`
and no `discard=` (QEMU's default `ignore`), and the guest runs no `fstrim`,
so files deleted in the guest never give space back: `disk.raw` only grows.
Add `discard=unmap` to the `-drive` in `macos/run-qemu-gpu.sh` and a weekly
`fstrim /` service in the guest (`modules/roguix/services.scm`). The builder
shows that QEMU 11.1 on macOS punches holes through to the APFS file (its
trim took the qcow2 from 59 to 25 GiB allocated), but verify it with the
app's own runtime first: on a disposable clone, write and delete a large
file in the guest, trim, and check the host's allocated size.

### A click in the guest menu sometimes does nothing the first time

Decided 2026-10-09: override `Menu.qml` in the Roguix build (as `MenuModel.js` already is) so rows are rebuilt only when the guard result changed, rebuild the guest, and open a PR to Omarchy (approved 2026-10-09: "make the PR remotely"; the coordinator reviews it before it is opened).

Approved 2026-10-08; diagnosed 2026-10-09, fix blocked on a guest build.

Fix it in a Roguix substitution of Omarchy's `Menu.qml` (skip the row
rebuild when the guard results are unchanged), offer it to Omarchy
upstream, or both?
Options: Roguix substitution and an upstream PR | upstream PR only, wait
for the next Omarchy pin | leave it

Reported by the maintainer 2026-10-08: opening the menu in the VM and
clicking Shutdown did not work right away; a second click did.

What was checked:

- The pointer path loses no clicks. With `libinput debug-events` in the
  guest during repeated menu clicks, including ones that did nothing, every
  `BTN_LEFT pressed` had its `released`. A Cocoa grab gap (QEMU forwards
  pointer events only while `isMouseGrabbed`, which only `mouseEntered`
  sets) was suspected and patched, but a click right after Command-Tab back
  into the window worked without the patch, so the patch was dropped.
- The menu loses them. Omarchy's `shell/plugins/menu/Menu.qml` (pin
  c668141) starts `bash -lc <guard script>` (`evaluateGuards`) on every
  `openExistingMenu`; when it exits, `guardProc.onExited` calls
  `rebuildDisplay()`, which clears `displayModel` and recreates every row
  even when the `when:`/`checked:` results did not change. Row providers
  (`mergeProviderRows`) rebuild the same way. A press that lands on a row
  just before the rebuild loses its `MouseArea`, so `onClicked` never fires.
- It depends on guest speed: it happened while the Mac was busy, and after
  closing many browser tabs on the Mac it no longer reproduced (`bash -lc
  true` took 0.28 s in the guest).
- Candidate fix: in `guardProc.onExited` (and the provider merge), call
  `rebuildDisplay()` only when the results differ from the current ones.
  A changed result can still rebuild under a press; keeping delegates
  across rebuilds (updating the model in place) would close that too.

## Proposed

### The shutdown screen shows Hyprland's startup log

Found 2026-10-07 by the shutdown-font worker and seen again 2026-10-09 with
the bold console font: at shutdown tty1 still shows the Roguix logo and
Hyprland's startup log, which `start-hyprland` printed there, and the
shutdown lines are written over its last line. Clearing tty1 when Hyprland
exits (or not printing the log there) would leave only the shutdown text.

### Build the image with a smaller --image-size

Proposed 2026-10-09. `build.py` passes `--image-size=20G`; the system uses
about 11.5 GiB of it, and the rest is zeros that the builder writes into
the store copy (allocated in the builder's ext4), the image file and the
factory image. The guest grows its root to the VM disk at boot
(`roguix-grow-root`), so the image needs only the closure plus headroom for
the first boot and setup. Measure the closure, pick a size (or Guix's
estimate), and check first boot and the first reconfigure on a fresh VM.

### Give the builder a disposable scratch disk for builds

Proposed 2026-10-09; weigh it after the cleanup step above. The image
derivations copy the closure into a temporary root, an ext4
`partition.img` and a genimage temporary in guix-daemon's build directory.
Pointing the daemon's `TMPDIR` at a second qcow2 that is deleted after the
build would free those at once instead of waiting for gc and trim. It adds
no capacity (same APFS volume) and changes how the builder is started.

## Needs a decision

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
- VM disk `disks/current/disk.raw` (64 GiB / 21 GiB): an APFS clone of the
  factory image extended sparsely to 64 GiB; only 0.27 GiB of its first
  20 GiB differ from the factory image, plus 0.73 GiB written beyond it, so
  it owns about 1 GiB of its own. Attached without `discard`, so it never
  shrinks. Deletable: no, it is the user's VM.

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
