# TODO

## Next, in order

### Compact the builder VM disk

Requested 2026-10-09 (disk space: 15 GB free): `.build/guix-validation/builder.qcow2`
is 81 GB with 59 GB allocated. Reclaim space without losing the builder: run
`guix gc` and `fstrim` in the builder (through `guest/guix/vm-run`), shut it
down cleanly, then compact the image (e.g. `qemu-img convert -O qcow2` to a
new file, verify it boots and `vm-run` works, then replace the old one).
Requested 2026-10-09 to be done now ("do the compaction now"). Check free space before the copy; report the space won. The builder needs a
console login after a reboot (guest/guix/README.md): if it is not reachable,
stop and ask the maintainer.

### Handing Command-Tab back with Control-Option depends on timing

Approved 2026-10-08.

Found 2026-10-08 in the in-app check (main 2c39093, macOS 27.0.1): with Send
Command-Tab to Roguix on, Command-Tab reaches the guest as Super-Tab, as the
`[event-tap] ... captured for the guest` lines confirm. After pressing and
releasing Control-Option alone, the next Command-Tab switches Mac apps only
if the maintainer waits a moment first, and not always even then. The patch
(`macos/patches/qemu-cocoa-command-tab.patch`) has no delay: it arms on the
Control-Option flags-changed event and releases on the one with no flags, so
some event or flag sequence is not what it expects. The release itself is not
logged, so the log cannot show which presses counted; logging the arm and
release would make it reproducible. Cause unknown.

### Name the macOS 27 privacy list in the Accessibility texts

Approved 2026-10-08.

Found 2026-10-08: on macOS 27.0.1 the list that grants Try Roguix control of
the computer is System Settings > Privacy & Security > Device Control and Data
Access; the maintainer found no Accessibility entry under Privacy & Security.
The start menu and docs say Accessibility, the name older macOS versions use,
so the wording should follow the running macOS version; which version renamed
it is unverified. The OPEN SETTINGS flow itself works there: one window, the
macOS prompt.

### The guest ignores the window size at the login screen on a fresh disk

Approved 2026-10-08.

Found 2026-10-08 by the initial-window worker: on a fresh disk the guest
stays at 2560x1440 at the login screen instead of following the window size
(before and after the initial-window fix). Unverified beyond that run.

## Proposed

## Needs a decision

- Start the builder VM (it needs a console login after a reboot) and free disk space, so a worker can build the guest with the bold console font (ter-v32n to ter-v32b, see "Background: the shutdown font")? Checked: the fix was verified live with setfont; the builder had no serial.sock and the Mac has 13 GB free (2026-10-07).
- Test Command-Space without the F18 workaround, binding it in Hammerspoon directly after a logout? Answered 2026-10-07: the maintainer runs it later. Checked: the Karabiner exemption is in the dotfiles (ef9ebbb); the test needs your logout and keyboard.

### Background: Command-Space

Reported 2026-10-03: Command-Space does nothing in the guest, and
Command-Tab switches Mac apps.

Command-Space, found: the maintainer's Karabiner-Elements rule turns
Command-Space into F18 (for a Hammerspoon launcher) in its virtual HID
driver, before QEMU's event tap, so the guest gets F18. Exempt the VM window
in that rule's manipulator; the window belongs to QEMU, which has no bundle
identifier, so match its path (check it in Karabiner-EventViewer):

```json
{"type": "frontmost_application_unless",
 "file_paths": ["^.*/Try Roguix\\.app/Contents/Resources/runtime/bin/Try Roguix$"]}
```

Done 2026-10-03 in the maintainer's dotfiles (ef9ebbb), which also restored
the Emacs rule the F18 change had replaced. Still to do: test without the
F18 workaround, binding Cmd+Space in Hammerspoon directly after a logout
(the steps are in ~/.hammerspoon/init.lua); and document this for users of
Karabiner, Hammerspoon and AltTab: such tools may own a chord before the VM
sees it.

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

### Background: the shutdown font

Requested 2026-10-07: "the font looks terrible during the shutdown, on the
black screen". Boot messages look fine; the shutdown text appears after
Hyprland exits, on a VT. Capture a screenshot of it first (blurry, too small,
too large or wrong glyphs) and compare it with the boot screen.

Consulted 2026-10-07 (sol, MiMo, DeepSeek; unverified): all three put first
that after Hyprland drops DRM master, fbcon repaints at a mode other than the
boot's `video=Virtual-1:2560x1440M` (the window-sized mode
roguix-display-sync left, not a multiple of 16x32), or at 2560x1440 that
zoom-to-fit then scales by a non-integer factor with linear filtering. To
tell guest from host: a QMP `screendump` during the shutdown (sharp there,
blurry on screen means the Cocoa scaling), and in the guest, before and after
`hyprctl dispatch exit`, `fgconsole`, `/sys/class/graphics/fb0/virtual_size`,
the DRM connector's active mode and `setfont -C /dev/ttyN -O` (which font the
shown VT has). Candidate fixes, by cause: restore the boot mode when Hyprland
stops, nearest-neighbor filtering in the Cocoa patch, or `setfont` on the
VT shown at shutdown.

Diagnosed 2026-10-07 (worker, b35 image, windowed dev build): the mode is
not the cause; the font is. Probes after Hyprland exits, written to hvc0
during a real `loginctl poweroff`: VT 1, `fb0` 2560x1440, the DRM plane
2560x1440, exactly the boot's mode (Hyprland itself ran at 1920x1080). A
`/dev/fb0` dump is sharp, so the guest draws what it means to. What
differs from boot is the face: the kernel's `fbcon=font:TER16x32` is
Terminus Bold (all 95 ASCII glyphs byte-identical to `ter-v32b`), while
`%roguix-console-font` (`modules/roguix/services.scm`) is `ter-v32n`, the
normal weight with 2 px strokes instead of 3; the probe read `ter-v32n` on
tty1 at shutdown. Boot messages are drawn before `console-font-tty1` runs
(it waits for tty1's login), shutdown messages after it. Zoom-to-fit then
scales 2560x1440 with linear filtering (about 1.35x full screen on a 16"
MacBook), which leaves the thin strokes grey and uneven. Loading
`ter-v32b` on tty1 right after Hyprland exited, in the same run, made the
shutdown text match the boot's weight. Proposed fix: `ter-v32b.psf.gz` in
`%roguix-console-font` (same 512 glyphs, same 16x32 cell, so the setup's
layouts are still covered); it needs an image build in the builder VM and
`make guix-package`, then a look at boot, setup and shutdown in the app.
Not done by the worker: the builder VM was not running and the Mac had
16 GB free, too little for a build and export. Separately, tty1 at
shutdown also shows the Roguix logo and Hyprland's startup log, which
`start-hyprland` printed there, with the shutdown lines written over its
last line.
