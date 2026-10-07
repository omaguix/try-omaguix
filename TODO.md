# TODO

## Next, in order

### Diagnose the Accessibility grant

Decided 2026-10-07: yes, with the maintainer at the Mac to grant and revoke
access in System Settings when asked. Follow the diagnosis steps and the
release re-grant notes in "Background: the Accessibility grant".

### The font on the shutdown screen looks terrible

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

## Proposed

### A fresh start gets half the initial window frame

Found 2026-10-07 while verifying the reboot-shrink fix: a fresh windowed
start opens at 648x397 points, half of the ~1296x729 that
`cocoa_initial_window_frame` intends (75% of the screen), before and after
that fix. Likely cause: when the view is first attached the window is not yet
resizable, so the size is divided by the Retina 2x backing scale. Unverified.

### The data-folder picker looks for the storage marker in the wrong place

Found 2026-10-07 by the layout worker: the picker looks for the
`.omarchy-qemu-storage` marker in the chosen folder, while
`qemu-persistent-storage.sh` writes it in `<folder>/guix/`, so choosing an
existing Roguix folder again is probably rejected as not empty. Changes which
folders the picker accepts. Unverified.

## Needs a decision

- Check in the running app, with your keyboard, the Command-Tab setting (off: macOS switches apps; on: Roguix gets Super-Tab; Control-Option hands it back) the startup-failure alert with Show Log, and the saved-VM chooser (Keep and Launch, Show in Finder)? Checked: all three are covered by tests only (c5d56ca, d34583a, the chooser commit); the key routing needs a real keyboard and the Accessibility grant, the alert and the chooser clicks in the start menu.
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
applies, even if System Settings still shows it on. This is the leading
hypothesis, not yet proven. Development builds signed with the local
identity have `certificate leaf = H"..."` instead, which stays the same
across rebuilds.

- Diagnose: run only `~/Applications/Try Roguix.app`; check the start
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
