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

## Host tools that take a chord first

Command acts as Super through QEMU's event tap, which sees a key only after
host tools that sit earlier in the input path. Karabiner-Elements remaps keys
in its virtual keyboard driver, and Hammerspoon hotkeys and AltTab's shortcut
are registered system-wide, so a chord they own reaches the guest as another
key or not at all. For example, a Karabiner rule that turns Command-Space
into F18 for a launcher makes the guest receive F18 instead of Super+Space.

Exempt the VM window in the Karabiner rule by adding a condition to its
manipulator. The window belongs to the bundled QEMU process, which has no
bundle identifier, so match its executable path:

```json
"conditions": [
  {
    "type": "frontmost_application_unless",
    "file_paths": ["^.*/Try Roguix\\.app/Contents/Resources/runtime/bin/Try Roguix$"]
  }
]
```

Check the path in Karabiner-EventViewer's frontmost application view while
the VM window is focused. Hammerspoon hotkeys and AltTab's shortcut need the
same treatment: disable them, or scope them so they do not fire while the VM
window is frontmost, when the guest should receive that chord.

## Validation

`make test` checksums the Cocoa patch, compiles the ISO swap helper, and
runs the guest Lua overlay. The upstream QEMU pin is unchanged. Review
`iso_swap_patch_sha256` in `macos/build-qemu-gpu-runtime.sh` against
`macos/patches/qemu-cocoa-iso-section-grave-swap.patch`. `make runtime`
applies the patch after the existing Cocoa series.
