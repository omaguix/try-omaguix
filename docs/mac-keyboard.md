# Mac keyboard geometry

Try Omarchy maps the host Mac keyboard class (ANSI / ISO / JIS) into the
guest. That corrects the ISO Section / extra-ISO key inversion for every
layout. For xkeyboard-config Mac vendor layouts (`ch de dk fi fr gb is it
latam nl no pt se us` with an empty variant) it also selects Macintosh
legends.

## Host

`omarchy-vm-helper --host-keyboard-geometry` reports `ansi`, `iso`, or
`jis`. Unknown Carbon classes fail the launch. The launcher exports
`TRYOMARCHY_KEYBOARD` and appends `tryomarchy.keyboard=` on a normal boot
only. Cocoa swaps `KEY_GRAVE` and `KEY_102ND` only when that value is
`iso`. Recovery unsets the env. `--reset-storage-only` skips the probe.

## Guest

New users load `/usr/share/try-omarchy/apple-keyboard-input.lua`, which
sets only `kb_model = "applealu_" .. geometry`. Layout and variant stay
whatever Omarchy setup chose. A missing token is a no-op.

## Existing VMs

App upgrade applies the Cocoa ISO keycode swap immediately. That uninverts
`@#` / `<>` on ISO boards without changing `kb_model`. **Remove any local
`frmac` (or similar) TLDE/LSGT symbol swap first**, or those keys invert
again.

Macintosh legends still need `kb_model`. If a rebuilt guest image installed
`/usr/share/try-omarchy/apple-keyboard-input.lua`, add this to
`~/.config/hypr/input.lua`:

```lua
dofile("/usr/share/try-omarchy/apple-keyboard-input.lua")
```

Otherwise set the model yourself (do not `dofile` a missing path):

```lua
hl.config({
  input = {
    kb_model = "applealu_iso", -- or applealu_ansi / applealu_jis
  },
})
```

Save, then run `hyprctl reload` and `hyprctl configerrors`.

## Command-Tab

System chords such as Command-Space reach the guest as Super only while
Try Omaguix is allowed in System Settings > Privacy & Security > Device Control
and Data Access on macOS 27 (Accessibility before); the start menu names the
list the running macOS uses.

Command-Tab and Command-Shift-Tab stay with the macOS app switcher by
default, so the keyboard can always leave the VM. The **Send Command-Tab to
Omaguix** setting (start menu and settings, off by default, applied on the
next start) sends them to the guest as Super-Tab and Super-Shift-Tab instead,
for switching guest windows.

With it on, press and release **Control-Option** on its own to hand
Command-Tab back to macOS; the next Command-Tab then switches Mac apps.
Forwarding resumes once the VM window has lost focus and you return to it.
The chord is the one UTM and Parallels use to release the keyboard. A chord
that adds another key, such as Control-Option-T, does not count, and the
guest still receives Control and Option as usual.

The launcher passes the setting as `OMARCHY_QEMU_GPU_SEND_COMMAND_TAB`, which
becomes the Cocoa display's `send-command-tab=on|off` from
`macos/patches/qemu-cocoa-command-tab.patch`.

## Host tools that take a chord first

Omaguix needs no key remapper such as Karabiner-Elements or Hammerspoon. With
the Accessibility grant, QEMU's own event tap captures Command chords,
Command-Space included, before Spotlight; Command-Tab follows the **Send
Command-Tab to Omaguix** setting. This section only matters if you already run
such a tool.

Without the grant the VM still starts, only without the Command-to-Super
mapping. The start menu's Accessibility row (titled Device Control and Data
Access on macOS 27) then shows the grant as missing, with an **Open Settings**
button. It brings up the macOS permission prompt, or opens System Settings >
Privacy & Security > Accessibility when the prompt cannot appear. The row
updates when you return to the start menu, and the mapping takes effect on a
later launch.

Command acts as Super through QEMU's event tap, which sees a key only after
host tools that sit earlier in the input path. Karabiner-Elements remaps keys
in its virtual keyboard driver, and Hammerspoon hotkeys and AltTab's shortcut
are registered system-wide, so a chord they own reaches the guest as another
key or not at all. For example, a Karabiner rule that turns Command-Space
into F18 for a launcher makes the guest receive F18 instead of Super+Space.

Exempt the VM window in the Karabiner rule by adding a condition to its
manipulator. The window belongs to the bundled QEMU process, which runs from
a helper app inside the app bundle (`Contents/Helpers/Try Omaguix.app`) with
its own bundle identifier, one per build:

| Build | App | VM window |
| --- | --- | --- |
| Release | `dev.tryroguix.native` | `dev.tryroguix.native.vm` |
| Development (`make app`, `Try Omaguix Dev.app`) | `dev.tryroguix.native.development` | `dev.tryroguix.native.development.vm` |

```json
"conditions": [
  {
    "type": "frontmost_application_unless",
    "bundle_identifiers": ["^dev\\.tryroguix\\.native(\\.development)?\\.vm$"]
  }
]
```

Check the identifier in Karabiner-EventViewer's frontmost application view
while the VM window is focused. Hammerspoon hotkeys and AltTab's shortcut need
the same treatment: disable them, or scope them so they do not fire while the
VM window (the same bundle identifier) is frontmost, when the guest should
receive that chord.

## Validation

`make test` checksums the Cocoa patches, compiles the ISO swap helper, and
runs the guest Lua overlay. Review `command_tab_patch_sha256` against
`macos/patches/qemu-cocoa-command-tab.patch` the same way. The upstream QEMU pin is unchanged. Review
`iso_swap_patch_sha256` in `macos/build-qemu-gpu-runtime.sh` against
`macos/patches/qemu-cocoa-iso-section-grave-swap.patch`. `make runtime`
applies the patch after the existing Cocoa series.
