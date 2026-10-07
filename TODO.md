# TODO

## Next, in order

### Diagnose the Accessibility grant

Decided 2026-10-07: yes, with the maintainer at the Mac to grant and revoke
access in System Settings when asked. Follow the diagnosis steps and the
release re-grant notes in "Background: the Accessibility grant".

### Fix the old rootfs.ext4 names in Swift

Requested 2026-10-07: "fix the old rootfs.ext4 names in Swift too". Found by
the saved-VM chooser worker: `QEMUGPUStorageSpaceEstimate.recordedPersistentDisk`
(disk-space estimates) looks for `rootfs.ext4` and kind
`omarchy-qemu-persistent-disk`, while `qemu-persistent-storage.sh` writes
`disk.raw` and `roguix-qemu-persistent-disk`, and `storageRootURL` does not
append the `guix` subdirectory. The same `rootfs.ext4` is in
`VMApplicationController.swift` (~line 502) and `GuestIntegrationStatus.swift`
(~line 57).

## Proposed

### A fresh start gets half the initial window frame

Found 2026-10-07 while verifying the reboot-shrink fix: a fresh windowed
start opens at 648x397 points, half of the ~1296x729 that
`cocoa_initial_window_frame` intends (75% of the screen), before and after
that fix. Likely cause: when the view is first attached the window is not yet
resizable, so the size is divided by the Retina 2x backing scale. Unverified.

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
our `qemu-cocoa-minimum-guest-size.patch` once it lands upstream.

`qemu-cocoa-minimum-guest-size.patch` fixes a hang that upstream shares: its
`qemu-cocoa-dynamic-display.patch` and QEMU's DEBUG EDK2 are the same, so a
guest reboot after a small window should hang there too. Kept as a separate
patch so rebases onto upstream do not conflict; offer it upstream (with the
firmware's ASSERT line as the reproducer) and drop ours once it lands. Upstream
QEMU's Cocoa UI also forwards the window size: reproduce on unpatched QEMU
before reporting it there.
