# Guix guest migration: image build slice

This is the first slice of replacing the Arch/Omarchy guest with Guix System and
Hyprland. The macOS launcher, patched QEMU, HVF, Virtio/VirGL and ANGLE/Metal
remain the intended host stack. The image has been built and booted once with
acceleration (see below); it is not yet connected to the launcher, is not a
supported guest, and does not yet reproduce the Omarchy desktop or its host
integrations. This does not add a second supported guest or an Arch
compatibility layer.

## Build

Use an ARM64 Linux machine with Guix, Git, Python 3 and a running
`guix-daemon`. Keep the source on the builder's native filesystem; fetching the
full Git history directly over a 9p host share is unnecessarily slow.
The source defaults to `../../../vendor/guix` relative to this directory
(`~/personal_projects/guix/vendor/guix` in the original checkout). The builder
uses that repository as a local Git channel, pinned to
`7e74121a40a8308166e328a23647cf6f3768e6c8`, via `guix time-machine`.
Tracked modifications and a different HEAD are rejected; untracked files are
not inputs to a Git channel. The checkout must include `origin/keyring`, as the
supplied vendor checkout does. A temporary bare Git repository exposes that ref
as the channel's `keyring` branch without modifying the vendor checkout or
copying its object database. The channel inherits the official Guix introduction:
Guix verifies commit signatures, not only the requested hash. Authentication is
never disabled. Guix still downloads package sources/substitutes and may build
missing packages.

### Moving the pin

Before moving the pin, check what the new commit would compile, in the
builder VM:

```sh
export GUIX="guix time-machine --commit=NEW --"
$GUIX system build -n --no-grafts -L guest/guix/modules guest/guix/system.scm \
  2>&1 | guest/guix/check-builds.sh
```

`check-builds.sh` reads the dry run and allows only two kinds of builds:
Roguix's own packages (the name and version of each package its modules
define) and derivations Guix marks `preferLocalBuild` (configuration files,
profile hooks, grafts, GRUB's image). Anything else is a package bordeaux has
not built for aarch64, and the script fails listing it: wait, or pick an
earlier commit.

`guix weather` is not enough: it asks only about package outputs, not about
the inputs of the system's local derivations. GRUB's theme image, for one, is
converted from SVG with `guile-rsvg`, which needs librsvg and so Rust; without
aarch64 substitutes for those, a build bootstraps Rust and LLVM. The dry run
lists them.

From the project root, on any host, inspect the plan without starting a build:

```sh
python3 guest/guix/build.py --dry-run
```

On the Linux builder:

```sh
# Authenticate and evaluate with the pinned Guix before building the image:
python3 guest/guix/build.py --source /path/to/vendor/guix --check
python3 guest/guix/build.py --source /path/to/vendor/guix
```

Unlike `--dry-run`, `--check` actually runs Guix and needs Linux, network access
and a daemon. It can download/build Guix itself and instantiate derivations,
but does not build the guest image or publish an output/GC root. An existing
image is left alone during checks. A failing Guix command propagates a nonzero
exit status, and the temporary channel repository is removed on either outcome.

A raw EFI image of this size plus the Guix store and build outputs needs more
room than the image itself: reserve well over 40 GiB of free space on the
builder, and expect the final `disk-image` derivation to need several GiB of
headroom. A build that runs out of space during that last derivation fails with
a `No space left on device` backtrace while copying the image into the store.

A Guix System VM can serve as the builder. Do not fetch the vendor checkout
over a 9p share: copy or clone it onto the builder's own filesystem first, and
set `safe.directory` if the copy is owned by another user.

`guest/guix/vm-run '<command>'` runs a command as root in such a builder VM
through its serial console (`.build/guix-validation/serial.sock`, or
`VM_RUN_SOCKET`) and blocks until it ends. The command runs detached in the
guest, logging to `/root/vm-run/<id>.log`; `vm-run` prints that log as it
grows and exits with the command's own exit code (124 on timeout, 125 when
the console stays unreachable). After the builder reboots, its console waits at
a login prompt and the 9p shares are unmounted, so `vm-run` sees no shell: log
in as root on the console and mount `project` (read-only) at `/mnt/project` and
`export` at `/mnt/export` first. A builder disk made as a qcow2 overlay
depends on its backing file (`qemu-img info` names it); deleting that file to
free space leaves the builder unbootable until the same file is restored,
for the official Guix VM image from ftp.gnu.org with its signature checked.
To give space back to the Mac, run `guix gc` and then `fstrim -av` through
`vm-run`. The builder's disk is attached with `discard=unmap`, so the trim
shrinks the qcow2's allocated size in place; a `qemu-img convert` would only
shorten the sparse file length, which costs no disk space (2026-10-09: gc took
the store from 50 to 34 GB and the trim the host file from 59 to 25 GiB).
Plain `guix gc` keeps every GC root, including the `time-machine` profiles
and `/root/roguix-system-ungrafted`. `build.py --export` (below) does this
after each image.
Run long builds under `herdr-job`, so they get their own tab and a real
result:

```sh
herdr-job run --name "Build image" -- guest/guix/vm-run 'guix time-machine ... -- system image ...'
herdr-job wait <id>
```

The default output `build/guix/image.raw` is a Guix GC-root symlink to a raw EFI
disk image (a 40 MiB ESP and a 16 GiB root partition), not an unpartitioned
ext4 filesystem. The system fills about 11.7 GiB of the root; the rest is
headroom for the closure to grow, since `roguix-grow-root` (below) grows the
root to the VM disk early in the first boot, before the desktop or the setup
write anything large. Measured 2026-10-09 on a fresh 16 GiB image in the app:
`roguix-grow-root` started with `file-systems`, before `guix-daemon` and the
first-boot setup, and grew the root to the 24 GiB VM disk; after the setup
`df` showed 11.3 GiB used, and the first update (`roguix-pkg add hello`,
23 minutes) added 4.9 GiB, which an ungrown 16 GiB root could not hold. A
16 GiB build took the builder from 13 to 48 GB used before the export.

An existing output, including a dangling symlink, is
refused rather than replaced. Choose another `--output` for another build. The
builder never opens existing VM workspaces.

A build grows the builder's disk by about 40 GiB, and nothing gives it back
while the image's GC root exists. Export the image to macOS with the same
script, which copies the image (not the symlink), compares the copy with
`cmp`, and only then removes the GC root, runs `guix gc` and `fstrim -av`:

```sh
herdr-job run --name "Export image" -- guest/guix/vm-run \
  'cd /mnt/project && python3 guest/guix/build.py --output /root/NAME.raw --export /mnt/export/NAME.raw'
```

A failed copy or comparison stops before the root is removed. An existing
export path is refused. Other GC roots stay, including older image roots under
`/root`, each pinning an image and its `partition.img`: check
`guix gc --list-roots` and remove the ones already exported.

The image carries no password. It declares one desktop account, `guest`
(UID 1000, the shared-folder owner), with the locked password `!`, and a
locked root. On the first start, `roguix-first-boot`
(`modules/roguix/services.scm`) switches to tty1 and asks for the account's
password twice before tty1 logs in; it sets it with `chpasswd` (SHA-512).
Guix account activation keeps a password set this way across reboots and
reconfigures, so the prompt appears only while the password is still locked.

The same setup asks for the keyboard layout, host name and time zone. It
applies them at once and writes them to `/var/lib/roguix/machine-settings.scm`,
a data file (an alist of strings, read, never loaded) that `/etc/config.scm`
uses for `roguix-operating-system`'s defaults; arguments in `config.scm`
override it. It starts no reconfigure: `roguix-machine-settings`, a boot
service the tty1 session waits for, compares the file with the values the
running system was built with and, only where they differ, sets the host
name, `/etc/hostname`, `/etc/hosts`, `/etc/localtime`, `/etc/vconsole.conf`
(which Omarchy's Hyprland input reads) and the console keymap. The next
reconfigure, for example when a package is added, builds the values in and
the service has nothing left to do.

The time zone works as in Try Omarchy 0.5 (its `docs/host-timezone.md`).
When the launcher passed the Mac's zone, the setup offers **Same as macOS**
first and preselected; the settings file then records the zone with
`timezone-follows-mac` `"yes"`, and any other choice (even the Mac's own
zone) records `"no"`. A settings file without the key keeps its zone fixed.
While following, `roguix-timezone` (`modules/roguix/timezone`, a root
Shepherd service, `test_timezone.py`) reads the zone the host writes every
five seconds on the root-only `dev.tryomarchy.timezone` port and applies a
change at once: it replaces `/etc/localtime`, records the zone in the
settings file, so the next boot and reconfigure keep it, and refreshes
Omarchy's clock in the running session. Omarchy's time zone menu is
Roguix's: it lists **Same as macOS** first while the Mac's zone is known,
which follows the Mac again from the latest zone it sent, and any zone
fixes it. The menu runs without a terminal, so `/etc/sudoers` lets
`wheel` run `roguix-timezone --select` with a valid zone or **Same as
macOS** without a password, as Omarchy's own `omarchy-tzupdate` rule does
for `timedatectl set-timezone`. The service logs to
`/var/log/roguix-timezone.log`. Replacing `/etc/localtime` by hand or
`#:timezone` in `/etc/config.scm` does not stop following; choose a zone in
the menu instead.

The language follows the Mac without a question: the launcher passes the
Mac's primary language (`tryomarchy.locale`) when the image lists it in
`guest.locales`, and the setup records it as `locale` (English otherwise).
The service and the next reconfigure set `LANG` in `/etc/environment` from
it. Only the setup reads the launcher's language, so a language chosen
later in the guest (`#:locale` in `/etc/config.scm`, or the settings file)
survives reboots and changes of the Mac's language.

The image lists Traditional Chinese (`zh_TW`), Simplified Chinese (`zh_CN`)
and Korean (`ko_KR`); the launcher sends English and any other language as
English. fcitx5 has two groups: Default (US, then Chewing) and Korean (US,
then Hangul); `Ctrl + Space` switches within the current group. A Korean
system starts in the Korean group (`roguix-omarchy-seed` puts it first when
it seeds the profile), every other language in Default; `fcitx5-remote -g
Korean` or `-g Default` switches, and fcitx5 keeps the choice. Noto Sans CJK
covers all three; `30-roguix-cjk.conf` prefers its TC face for `zh-TW` and
its KR face for Korean text.

Like the Arch guest, the VM console then logs in directly: the disk is
protected by the Mac account. tty1 auto-logs in `guest`, and
`/etc/profile.d/roguix-session.sh` runs `start-hyprland` there only; other
consoles, the serial console and SSH get an ordinary shell. The password is
what `sudo` asks for. No display manager runs and no SSH server is enabled.

SDDM provides login into the packaged Hyprland Wayland session. Guix installs
`hyprland.lua` through the account skeleton for newly created users. It starts
Foot and binds Super+Q to Foot, Super+R to Wofi, Super+C to close, and Super+M to
end the session, using Hyprland's standard navigation and workspace bindings.
Existing user configuration is not overwritten by this skeleton mechanism.

Foot avoids the separate Kitty OpenGL-context problem that Try Omarchy's Arch
guest worked around with a `kitty` wrapper. Kitty and its
software-rendering exception are not part of this image. No compositor
software-rendering override or version-specific Arch Hyprland patch is carried
over. Fonts and Mesa diagnostic tools are also installed.

The pinned checkout packages Hyprland 0.55.4 with Aquamarine 0.12.1, which
cannot follow window resizes (see below). `modules/roguix/packages.scm`
therefore defines Hyprland 0.56.1 and Aquamarine 0.14.0, the known-good Arch
guest pair, built without systemd/UWSM like the upstream package. Notes:

- Hyprland 0.56 needs a newer C++ toolchain than the default GCC 14. This
  checkout's aarch64 `gcc-16.2.0` substitute ships a libstdc++ configured
  without C99 math (`_GLIBCXX11_USE_C99_MATH` undefined, so even
  `std::signbit` is missing), so the package uses `gcc-toolchain-15`. Its one
  gap, a single C++23 `std::ranges::starts_with` call, is rewritten to the
  C++20 equivalent in an origin snippet.
- The module is project code outside Guix's channel authentication; review it
  like any other source. `build.py` passes it with `--load-path`, and the image
  installs a copy under `/etc/roguix` so an in-guest reconfigure keeps these
  versions instead of reverting to 0.55.4.

## Package the launcher artifact

```sh
make guix-package GUIX_IMAGE=/absolute/path/to/image.raw
```

`package.py` accepts only the exact `efi-raw` layout: a protective MBR,
identical primary and backup GPT headers with valid CRCs, partition 1 an EFI
system partition (FAT) at LBA 2048 and partition 2 an ext4 root labelled
`Guix_image`, nothing else. It writes `build/guix/` with exactly:

- `disk.raw.zst`: the disk, compressed with the runtime's pinned `zstd`;
- `guix-manifest.json`: kind `roguix-guest-artifacts`, boot ABI
  `uefi-gpt-v1`, the recorded partition layout, raw and compressed sizes and
  SHA-256 values, the Guix commit, a digest of the system definition files, and
  the credentials profile;
- `SHA256SUMS` for the other two files.

The directory is staged beside its target and renamed into place only after
`artifact.validate_artifacts` passes, including a full decompression that
must reproduce the raw SHA-256. An existing output is never replaced.
`systemFilesSHA256` records the definition present when packaging; the image
itself is not re-derived. The credentials profile is `first-boot`: the
image carries no password (see above).

## Ephemeral graphics smoke test on macOS

Build the existing runtime with `make runtime`. Copy the completed raw image
from Linux to the Mac, dereferencing the Guix GC-root symlink. Then run:

```sh
python3 guest/guix/run.py --image /absolute/path/to/image.raw
```

The UEFI firmware is the runtime's own
`share/qemu/edk2-aarch64-code.fd`: the EDK2 build committed in the pinned QEMU
source, decompressed and SHA-256-pinned by `prepare-qemu-gpu-runtime.sh` (it is
byte-identical to Homebrew QEMU's copy). No firmware is read from the system.

`run.py` uses only the project's signed QEMU runtime, HVF, Virtio GPU with
VirGL, and the Cocoa GLES/ANGLE path. It does not fall back to a system QEMU or
software CPU emulation. QEMU's `-snapshot` keeps all writes in a disposable
overlay: shutdown discards guest changes and leaves the supplied image intact.
There is no host filesystem share, port forwarding, microphone/camera capture,
clipboard bridge or system-wide keyboard grab in this smoke test. Guest outbound
network access uses QEMU's existing user-mode networking. `--dry-run` prints the
command without opening files or starting QEMU.

Log into the Hyprland session as `guest` using the build-time development
password. A successful build alone establishes nothing about the guest.

### Verified once, 2026-09-17, Apple M1 Pro, macOS 26.5.2

Image `aaf789447a3925fe119fcd030baf9a7ff83ea66cac96b9ef5aa8f4d88c5d0481`,
built from Guix `7e74121a`, ran on this runtime with these observations:

- The guest booted to SDDM, accepted the development password, and started the
  packaged Hyprland session. Foot opened from the autostart entry.
- GPU acceleration was real, not software. The host reported
  `ANGLE (Apple, ANGLE Metal Renderer: Apple M1 Pro)`, the guest reported
  `Renderer: virgl` and `glamor X acceleration enabled on virgl`, and
  `Mesa 26.0.2` was the user-space driver. `llvmpipe` did not appear.
- Keyboard and pointer input reached the guest through virtio. Typing in Foot
  created a file, and Super+R opened Wofi with desktop entries.
- `halt` shut the guest down; QEMU's `-action shutdown=poweroff` ended the
  process. The image SHA-256 was identical afterwards, confirming the
  `-snapshot` isolation.

### Window resizes, verified 2026-09-24, Apple M1 Pro, macOS 26.5.2

Image `e0dc1a159133e9da30c934d1127244a0fb780c68fb68b352d68838e4f123349d`
(Hyprland 0.56.1, Aquamarine 0.14.0, same Guix `7e74121a`):

- `hyprctl systeminfo` reported Hyprland 0.56.1 built against hyprutils 0.14.2
  and Aquamarine 0.14.0; the guest log still showed `Renderer: virgl` and the
  host ANGLE Metal Renderer.
- `roguix-display-sync` ran from the session. Resizing the QEMU window
  through the macOS accessibility API changed the guest mode each time, at
  scale 2: 1200x760 pt (clamped by macOS to 1187x700) gave `2374x1336`,
  700x450 gave `1400x788`, and growing again gave `2374x1336`. Foot followed
  the new size. Shrinking and growing past the boot mode both worked.
- `halt` ended QEMU and the image SHA-256 was unchanged.

With 0.55.4/0.12.1 (image `aaf78944…`, probed 2026-09-23) every mode larger
than the current one failed: atomic test commits returned `Invalid argument`,
and with `AQ_NO_ATOMIC=1` the log showed `drmModeSetCrtc failed: No space left
on device`, i.e. a modeset with the old, smaller framebuffer. Runtime rules and
config reloads did not help. Cursor handling is still unverified.

## Guest side of the persistent disk

The launcher will keep a VM's writes on its own copy of the disk and grow it
by extending the file. The guest cooperates without launcher-specific kernel
arguments:

- GRUB is installed with `grub-efi-removable-bootloader` at
  `EFI/BOOT/BOOTAA64.EFI`. EDK2 started with `-bios` keeps no UEFI variables,
  so this is the path it boots, and every `guix system reconfigure`
  reinstalls it there.
- `/` is declared by the label `Guix_image`, which the partition's ext4
  carries. The image mounts it by a derived UUID; an in-guest reconfigure of
  `/etc/roguix/system.scm` mounts the same file system by label.
- The one-shot Shepherd service `roguix-grow-root`
  (`modules/roguix/services.scm`) runs after `file-systems` and `udev`. If
  more than 1 MiB lies after partition 2 of `/dev/vdX`, it relocates the
  backup GPT (`sfdisk --relocate gpt-bak-std`), extends partition 2 in place
  (`sfdisk -N 2`, keeping start, type, GUID and name), tells the kernel
  (`partx --update`) and runs `resize2fs` online. `resize2fs` runs on every
  boot, so a growth interrupted after `sfdisk` completes on the next boot.

- Guix's `fstrim-service-type` trims the file systems in `/etc/fstab`
  hourly (`modules/roguix/system.scm`). The launcher attaches the disk with
  `discard=unmap`, so the trim punches holes in `disk.raw` and files deleted
  in the guest give their space back to the Mac. Hourly, not Guix's weekly
  default, because Shepherd's timer does not run a missed event later, and a
  VM is often closed. Verified 2026-10-09 with the app's runtime on a sparse
  raw file: writing 3 GiB took it from 70 to 3144 MiB allocated, `rm` left
  that, and `fstrim` brought it back to 72 MiB. Through the app the same
  day, the timer was scheduled hourly, and `herd trigger fstrim` took
  `disk.raw` from 14146 MiB (after writing and deleting a 2 GiB file) back to
  12098 MiB.

On the first boot, `fsck.fat` repairs `.`/`..` entries in the ESP that
genimage writes; later boots find nothing to fix.

## Running through the app

```sh
make app   # build/dev.noindex/Try Roguix.app with the build/guix guest
make run   # build it and open it
```

`build-app.sh` bundles exactly `disk.raw.zst`, `guix-manifest.json` and
`SHA256SUMS`, plus `artifact.py` as `scripts/guix-artifact.py`. Its build-time
validation writes `launch.plist` with `bootABI = uefi-gpt-v1`.

`run-qemu-gpu.sh`:

- validates the artifact (`guix-artifact.py launch-record`) when no
  `launch.plist` exists, and requires the UEFI boot ABI;
- materializes the factory disk once to `images/<identity>.raw`, re-hashed
  against the manifest, APFS-clones it to `disks/current/disk.raw` and
  sparsely extends it to 24 GiB (`WORKING_DISK_BYTES`), all under the state
  root's `guix/` subdirectory;
- boots with `-bios runtime/share/qemu/edk2-aarch64-code.fd`, passes its
  settings as SMBIOS OEM strings, and adds a USB keyboard for GRUB's menu.

### Verified 2026-09-24, Apple M1 Pro, through the app's launcher

With a test state root: the first launch materialized and verified the
12.0 GB factory disk, created the 24 GiB workspace, printed `Ready`, and the
guest grew `/` to 24G. A file written before `sudo halt` was present after a
second launch, which reused the workspace without materializing again.

### First start, verified 2026-09-24, Apple M1 Pro, macOS 27.0

On a fresh persistent copy of the image: tty1 showed the password prompt,
rejected two different entries ("The passwords differ") and asked again;
after two equal entries it set a SHA-512 hash, tty1 logged in as `guest` and
Hyprland with Foot came up. `sudo` accepted the new password, root stayed
locked (`!`), and the next boot went straight to the desktop without a prompt.

An earlier version ran `chvt 1` before prompting. On both first starts with it,
Hyprland then waited forever in `epoll_wait` right after renderer setup
(the logind session was active, but the compositor never got the seat), and
a manual VT switch away and back released it. tty1 is already the active VT
at boot, so the prompt no longer switches VTs; two fresh first starts since
went straight to the desktop.

## The Omarchy 4 desktop

`modules/roguix/omarchy.scm` gives the desktop account the Omarchy 4
("Quattro") desktop from the pinned upstream release 4.0.4 (`c668141e`, tree
`1d48adc1`):

- **Omarchy itself** is a package: the upstream tree under
  `share/omarchy`, its commands in `bin/`, and `/usr/share/omarchy` (the
  default `OMARCHY_PATH`) linked to it. Quickshell 0.3.1 (the Arch guest's
  version, `packages.scm`) runs its shell; JetBrainsMono Nerd Font 3.5.1, the
  `omarchy` glyph font, Liberation and Yaru provide its fonts and icons.
- **Arch assumptions** are replaced by `roguix-omarchy-compat`: `uwsm-app`
  and `systemd-cat` run the command directly; `systemd-run` runs it detached
  after `--on-active`'s delay; `systemctl` sends `poweroff`, `reboot`,
  `suspend` and `hibernate` to elogind's `loginctl` and accepts everything
  else as an empty success; `uwsm stop` (Logout) exits Hyprland, and tty1
  logs in again; `busctl` covers Omarchy's notification and UPower calls
  through gdbus (`test_busctl.py`); `xdg-terminal-exec` is Try Omarchy's.
- **The account** is seeded once, at the first desktop login, by
  `roguix-omarchy-seed`: Omarchy's `config/` into `~/.config` (never
  overwriting), its applications, Hyprland toggles and fontconfig aliases;
  `OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "Tokyo Night"`; first-run,
  user provisioning and shipped migrations marked done, since they install
  Arch packages and systemd units. An account from the pre-Omarchy image gets
  its old Roguix `hyprland.lua` replaced.
- **The VM additions** live in `/etc/roguix-hypr-vm.lua`, which the seed
  appends to `~/.config/hypr/monitors.lua` as the Arch guest appends its QEMU
  fragment: Hyprland's cursor is hidden when the launcher reports VirGL (Cocoa
  draws the Mac's cursor), `roguix-display-sync` follows the window, and the
  host bridges and PipeWire start with the session.
- **Lock screen:** the shell authenticates with the PAM service
  `omarchy-lock-password`, defined with `pam_unix`.
- **Menu clicks:** Omarchy's `Menu.qml` recreates every row when its guard
  batch (`when:`/`checked:`) ends, and a press on a row just before is lost.
  The build substitutes it to rebuild only when a result changed, until
  Omarchy takes the fix. Verified 2026-10-09 through the app, with a test row
  whose guard takes 3 s, pressed 0.2 s after the menu mapped and released 4 s
  later: 2 of 10 clicks ran its action without the substitution, 10 of 10
  with it; quick clicks worked 30 of 30 in both.
- **Menu and panel keys:** Omarchy 4.0.4 binds Super+Space and the other
  menu and panel keys to `omarchy-menu`/`omarchy-shell`, which start a
  `qs ipc` client that `omarchy-shell` kills on its timeout under load, and
  the toggle is then lost or arrives late. `omarchy-global-shortcuts.patch`
  backports Omarchy #13418 (6762769b): the shell registers a Hyprland global
  shortcut for each entry in `default/omarchy/shortcuts`, and the bindings
  dispatch it with `hl.dsp.global`, so a keypress starts no process. Other
  callers of `omarchy-shell` keep the old path. Remove the patch once the
  pinned Omarchy includes 6762769b; the build fails if it no longer applies.

- **Audio scripts in other languages:** Omarchy's output scripts
  (`omarchy-audio-output-set-default`, `-output-sink`, `-output-switch`,
  `-output-volume`, `-sink-availability`, `-tuning`) parse `pactl`'s
  output, which pactl translates in a Chinese or Korean session, so output
  switching and the output list failed there.
  `omarchy-audio-c-locale.patch` runs only those parsed `pactl` calls with
  `LC_ALL=C`. Remove it once the pinned Omarchy does the same.

- **Menus without perl:** `omarchy-menu-select` and `omarchy-menu-input`,
  which a dozen Omarchy commands (the time zone menu among them) build on,
  encoded their JSON payload with perl, which the image does not have, so
  those menus showed nothing. `omarchy-menu-jq.patch` encodes it with jq;
  `test_omarchy_menu_jq.py` compares both encodings. Remove it once the
  pinned Omarchy encodes without perl.

- **Power profiles:** the VM has no Linux power profile driver
  (`power-profiles-daemon`); `omarchy-macos-power-profile.patch`, Try
  Omarchy's, makes the power menu and panel show one profile, managed by
  macOS.

Menus that manage systemd timers (reminders) do nothing here. `gum` and `libvips` are not in this Guix, so gum
dialogs and background-picker thumbnails are missing.

### Packages: /etc/config.scm

There is no pacman, AUR or Arch update channel. Every program comes from Guix
and is part of the system configuration:

- **`/etc/config.scm`** is written on the first boot and is the owner's to
  edit. It calls `roguix-operating-system` (`modules/roguix/system.scm`,
  the same procedure `system.scm` builds the image from) with a list of Guix
  package names between `;; BEGIN roguix packages` and `;; END roguix
  packages`.
- **`roguix-pkg`** (`modules/roguix/roguix-pkg`, `test_roguix_pkg.py`) edits
  that list and applies it: `add` and `remove` (root; the list is restored if
  the reconfigure fails), `present` and `list` (the running system's
  profile), `pick-add` and `pick-remove` (fzf pickers).
- **Omarchy's menu** is rewritten when the `omarchy` package is built
  (`modules/roguix/omarchy-menu.py`, `test_omarchy_menu.py`): Arch-only
  entries are dropped; Install and Remove offer any Guix package and curated
  Guix programs; Update → Guix System applies, edits or rolls back the
  configuration. Omarchy's `omarchy-pkg-*` helpers call `roguix-pkg`, and
  the menu's installed-package check asks it instead of pacman.
- **`roguix-reconfigure`** runs `guix system reconfigure -L
  /etc/roguix/modules /etc/config.scm` with the Guix that built the image,
  kept as the GC root `/var/guix/gcroots/roguix-guix`, so it computes the
  image's own derivations. The image also keeps its whole system *without
  grafts* as `/var/guix/gcroots/roguix-ungrafted`: a reconfigure grafts
  again from those builds, and without them it would rebuild Hyprland and
  Quickshell, which have no substitutes, for hours.
- **Substitutes for Roguix's own packages** come from
  `https://roguix.frolow.dev` (`server/`, decision 0002), after Guix's servers;
  the guest authorizes `modules/roguix/roguix.frolow.dev.pub`. Verified
  2026-09-24 in a b12 guest: `guix weather --substitute-urls=https://roguix.frolow.dev`
  finds Quickshell, Hyprland and Omarchy (3 of 3).

Measured 2026-09-24 on a fresh image with the Mac's network: the first
`roguix-pkg add alacritty` took 20 minutes, mostly downloading about 900 MB
of other outputs (`debug`, `doc`, `jdk`) of grafted packages that grafting
needs; the next, `add helix`, took 3 minutes and 5.3 MB. Shutdown and Logout
from the menu work.

Measured 2026-10-01 on b35, when the setup still reconfigured: the first-start reconfigure took 1415 s
(2386 s in an earlier run) and downloaded 2.3 GB in 33 sequential substitute
rounds. The store gained about 5 GB of nar, mostly other outputs of packages
in the system's closure: `debug` 2.7 GB (qtdeclarative alone 1.4 GB), `doc`
0.66 GB, OpenJDK's `jdk` 0.39 GB, plus whole `out`s such as GCC 14 and 15.
The pinned Guix's `cumulative-grafts` (`guix/grafts.scm`) scans the
references of every output of each derivation it may graft, building
(substituting) missing ones, and grafts all outputs on purpose so only one
grafted variant exists (bugs 24886 and 75157). The ungrafted GC root keeps
only the closure, so these outputs are fetched again on every fresh VM.

Verified 2026-09-24 on a fresh image: the shell's bar (workspaces, clock,
weather, network, audio, display), the Tokyo Night background, Foot with the
theme's colours and border on Super+Return, and Omarchy's menu on
Super+Space; the full integration run through the launcher passed on the
same image.

## macOS integrations

`modules/roguix/integrations.scm` ports the guest side of the launcher's
integrations. The host side, the wire protocols and the guest programs come
from Try Omarchy's Arch guest, unchanged; only their startup differs.

- **Launcher settings.** The launcher passes its arguments as SMBIOS OEM
  strings (see ADR 0001); `roguix-host-settings` writes them to
  `/run/roguix/host-settings` in kernel command-line format. The shared
  folder script reads it through its `OMARCHY_MAC_SHARE_CMDLINE` override, the
  SSH gate directly. A
  missing or unreadable table yields an empty file, never a failed boot.
- **Shared folder.** `mac-share` (the Arch `omarchy-native-mac-share`) mounts
  the `mac` 9p tag at `/mnt/mac` from a Shepherd service that tty1's session
  waits for, and `/etc/profile.d` links `~/<Mac folder name>` at each login of
  the desktop account. Mount failures are logged and never block the session.
- **Clipboard.** `clipboard-bridge` runs under `roguix-agent`, which Hyprland
  starts: it keeps the bridge running while the session's Wayland socket and
  the `dev.tryomarchy.clipboard` port exist and restarts it 2 s after it
  exits, as the Arch unit's `Restart=` does. A udev rule gives the port to the
  `users` group, mode 0660. `wl-clipboard` is installed system-wide.
- **Audio.** Sound itself flows through QEMU's intel-hda. Hyprland starts
  PipeWire, WirePlumber and pipewire-pulse under `roguix-agent`, then
  `audio-bridge`, which mirrors the Mac's devices as `omarchy_host_*` remap
  endpoints through `pactl` and relays the selection. The Arch guest's graph
  quantum file is installed as `/etc/pipewire/pipewire.conf.d/`
  `90-try-omarchy-quantum.conf`, and PulseAudio's client `autospawn` is off so
  `pactl` never starts a real PulseAudio daemon. The session runs inside
  `dbus-run-session`. Try Omarchy's `omarchy-audio-input-set-default`
  replaces Omarchy's: choosing a microphone moves only application
  recordings, never the remap source's own stream (which would then record
  itself), and reads `pactl` in the C locale (`test_audio_input_helper.py`).
- **Camera.** `v4l2loopback-linux-module` is a loadable module, loaded at boot
  with the Arch guest's options (`/dev/video42`, "Mac Camera",
  `exclusive_caps`); `camera-bridge` runs under `roguix-agent`. udev gives
  the port and `video42` to the `video` group.
- **Touch ID for sudo.** `authentication-broker` is Try Omarchy's broker,
  with only its two `/usr/bin` OpenSSL references rewritten to the store at
  build time (`test_build.py` pins both). `/etc/pam.d/sudo` always starts with
  a `sufficient` `pam_exec` rule whose gate fails at once until
  `roguix-touch-id enable` (which runs `roguix-touch-id-control` through
  sudo) has enrolled with the Mac and written
  `/var/lib/roguix/touch-id-enabled`; see ADR 0001. The port is root-only,
  mode 0600, as the broker requires.
- **SSH.** `sshd` is installed with auto-start off; `roguix-ssh-access`
  starts it for the current boot only when the settings contain exactly
  `tryomarchy.ssh_access=1`. Root login is refused; host keys live on the
  guest disk.

tty1's login also waits for Shepherd's `elogind`. Without that, an early
auto-login let `pam_elogind` D-Bus-activate a second elogind; Shepherd then
disabled its own, and `pam` and `sshd` could never start.

### Integrations, verified 2026-09-24, Apple M1 Pro, macOS 27.0

Through the app's launcher with a fresh state root, a shared Mac folder named
`Work Folder` and the `tcp:2222:22` forward: SSH logged in as `guest`; the
settings file held all three launcher arguments; `~/Work Folder` pointed at
`/mnt/mac`; a Mac file was readable in the guest and a file written by the
guest appeared on the Mac; the Mac pasteboard reached `wl-paste` and a
`wl-copy` in the guest reached `pbpaste`. With audio and camera added, the
same run found PipeWire, WirePlumber and pipewire-pulse running, the audio
bridge exposing two Mac output and two Mac input endpoints, and `/dev/video42`
named "Mac Camera" with its bridge running. Streaming the camera was not
exercised: it would switch on the Mac's camera and needs macOS permission.
With Touch ID added: `/etc/pam.d/sudo` carried the gated rule, the port was
`root 600`, sudo accepted the password, and the gate returned 1 while Touch ID
was off. Enrollment needs the owner's finger on the Mac and was not run.

### Not done yet

1. Cursor handling in the display contract.
2. The Swift app still shows Omarchy names and reads Arch workspace metrics
   for its free-space guard; `resize-vm-disk.sh` handles only the Arch disk.
3. Enroll Touch ID once by hand (`roguix-touch-id enable` in the guest,
   with the VM window in front) to confirm the host approval path.
4. Switch the default build to Guix and remove the Arch builder once the
   above covers the required behavior.

## Local checks

```sh
PYTHONDONTWRITEBYTECODE=1 python3 guest/guix/test_build.py
PYTHONDONTWRITEBYTECODE=1 python3 guest/guix/test_run.py
python3 guest/guix/build.py --dry-run
```

These check build planning, pin enforcement, no-overwrite behavior and failure
propagation. A real temporary Git repository test verifies that the keyring is
exported without modifying source refs or tracked files. These tests also run
through `make test`. Smoke-launcher tests check explicit acceleration, ephemeral
storage, filename escaping, signature failure, and the absence of host access
channels. These tests do not evaluate the Guix system or boot a VM; `--check`
is the separate Linux integration check.
