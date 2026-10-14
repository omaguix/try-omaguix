;;; Omaguix — the Omarchy 4 desktop on Guix System.
;;;
;;; Omarchy 4 ("Quattro") is installed like the Arch guest installs it: the
;;; pinned upstream tree as a package at /usr/share/omarchy (OMARCHY_PATH's
;;; default), its commands on PATH, and its user configuration seeded into
;;; the desktop account's home. The desktop is its own Hyprland Lua
;;; configuration and its Quickshell shell (bar, background, launcher menu,
;;; notifications, lock), themed Tokyo Night.
;;;
;;; What Omarchy expects from Arch is replaced, not emulated: uwsm-app,
;;; systemd-cat and `systemctl --user' become no-frills compatibility
;;; commands, busctl's notification calls go through gdbus, and nothing from
;;; its installer, package manager or systemd units runs. Menus that manage
;;; Arch packages or systemd timers therefore do nothing here.
(define-module (roguix omarchy)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system font)
  #:use-module (guix build-system trivial)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages base)
  #:use-module (gnu packages version-control)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages curl)
  #:use-module (gnu packages fontutils)
  #:use-module (gnu packages fonts)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gawk)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gnome-xyz)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages image-viewers)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages ncurses)
  #:use-module (gnu packages networking)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages python)
  #:use-module (gnu packages qt)
  #:use-module (gnu packages terminals)
  #:use-module (gnu packages video)
  #:use-module (gnu packages web)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu services)
  #:use-module (gnu system pam)
  #:use-module (roguix apps)
  #:use-module (roguix packages)
  #:use-module (roguix trust)
  #:use-module (roguix ttfx)
  #:export (omarchy
            font-jetbrains-mono-nerd
            roguix-omarchy-compat
            roguix-omarchy-service-type))

;; Upstream basecamp/omarchy 4.0.4, tree 1d48adc1.
(define omarchy
  (package
    (name "omarchy")
    (version "4.0.4")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/basecamp/omarchy")
                    (commit "c668141e9c42b13c80c9ca4ea108e11708c5e8a5")))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0djxrwz0h8nbisy5j3xdvkicj6v0kl12qxc34dvakscgw0rp3jwy"))
              ;; Omarchy #13418 (6762769b, after 4.0.4): menu and panel
              ;; bindings reach the shell as Hyprland global shortcuts
              ;; instead of a qs IPC client that omarchy-shell kills on its
              ;; timeout, which lost or delayed Super+Space. The build fails
              ;; if the patch no longer applies; remove it once the pin
              ;; includes 6762769b. The VM has no Linux power profile
              ;; driver: as in Try Omarchy, the power menu and panel show
              ;; one profile, managed by macOS. The audio scripts parse
              ;; pactl, which a Chinese or Korean session translates, so
              ;; they read it in the C locale until Omarchy does. The
              ;; background's name is title-cased as UTF-8, not as bytes.
              ;; A theme change stages the store's theme as the owner's, so
              ;; it can replace the current theme (a Guix-only problem).
              ;; The low-battery warning closes once the battery recovers.
              ;; All but the power profile and theme staging patches differ
              ;; from Try Omarchy: guest/guix/README.md, "Differences from
              ;; Try Omarchy".
              (patches
               (list (local-file "omarchy-global-shortcuts.patch")
                     (local-file "omarchy-macos-power-profile.patch")
                     (local-file "omarchy-audio-c-locale.patch")
                     (local-file "omarchy-theme-bg-utf8.patch")
                     (local-file "omarchy-theme-set-store-modes.patch")
                     (local-file "omarchy-battery-warning-dismiss.patch")))))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(("." "share/omarchy" #:exclude-regexp ("^\\.git"))
          ("default/fonts/omarchy/omarchy.ttf" "share/fonts/omarchy/"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'use-guix-packages
            ;; Programs come from Guix and /etc/config.scm, never pacman or
            ;; the AUR: the menu's Install, Remove and Update entries are
            ;; Guix's (omarchy-menu.py), Omarchy's package helpers call
            ;; roguix-pkg, and its Arch-only package commands are gone.
            ;; See guest/guix/README.md, "Differences from Try Omarchy".
            (lambda* (#:key native-inputs inputs #:allow-other-keys)
              (let* ((omarchy (string-append #$output "/share/omarchy"))
                     (bin (string-append omarchy "/bin"))
                     ;; Written after patch-shebangs would see them, so they
                     ;; name the store's bash directly.
                     (bash (search-input-file inputs "bin/bash"))
                     (menu (string-append omarchy "/default/omarchy/omarchy-menu.jsonc")))
                (invoke "python3" #$(local-file "omarchy-menu.py") menu
                        (string-append menu ".guix"))
                (rename-file (string-append menu ".guix") menu)
                (for-each (lambda (command)
                            (delete-file (string-append bin "/" command)))
                          '("omarchy-pkg-aur-accessible" "omarchy-pkg-aur-add"
                            "omarchy-pkg-aur-install" "omarchy-update-aur-pkgs"))
                (for-each
                 (lambda (helper)
                   (let ((file (string-append bin "/" (car helper))))
                     (call-with-output-file file
                       (lambda (port)
                         (format port "#!~a~%# Omaguix: ~a~%~a~%"
                                 bash (cadr helper) (caddr helper))))
                     (chmod file #o555)))
                 '(("omarchy-pkg-add" "add Guix packages to /etc/config.scm"
                    "exec sudo roguix-pkg add \"$@\"")
                   ("omarchy-pkg-drop" "remove Guix packages from /etc/config.scm"
                    "exec sudo roguix-pkg remove \"$@\"")
                   ("omarchy-pkg-present" "all of these Guix packages are installed"
                    "exec roguix-pkg present \"$@\"")
                   ("omarchy-pkg-missing" "some of these Guix packages are missing"
                    "! roguix-pkg present \"$@\"")
                   ("omarchy-pkg-install" "choose Guix packages to install"
                    "exec roguix-pkg pick-add")
                   ("omarchy-pkg-remove" "choose Guix packages to remove"
                    "exec roguix-pkg pick-remove")))
;; Try Omarchy's microphone helper: Omarchy's moves every
                ;; recording to the chosen source, including the audio
                ;; bridge's own module-remap-source stream, which then
                ;; records from itself and the Mac microphone falls silent.
                (let ((file (string-append bin "/omarchy-audio-input-set-default")))
                  (copy-file #$(local-file "audio-input-set-default") file)
                  (chmod file #o755)
                  (substitute* file (("^#!/bin/bash") (string-append "#!" bash)))
                  (chmod file #o555))
                ;; Web apps need a Chromium-family --app window; Omaguix's
                ;; browser is LibreWolf, so they open in a new browser window.
                ;; See guest/guix/README.md, "Differences from Try Omarchy".
                (let ((file (string-append bin "/omarchy-launch-webapp")))
                  (call-with-output-file file
                    (lambda (port)
                      (format port "#!~a~%# Omaguix: open a web app in a new window of the default browser.~%exec omarchy-launch-browser --new-window \"$1\"~%" bash)))
                  (chmod file #o555))
                ;; Omarchy's time zone menu calls timedatectl. Omaguix's
                ;; lists "Same as macOS" first while the Mac's zone is
                ;; known (Try Omarchy 5cebb9b): choosing it follows the Mac
                ;; again, any zone fixes it. system.scm's sudoers allows
                ;; exactly this command without a password, as Omarchy does
                ;; for timedatectl.
                ;; See guest/guix/README.md, "Differences from Try Omarchy".
                (let ((file (string-append bin "/omarchy-menu-timezone")))
                  (call-with-output-file file
                    (lambda (port)
                      (format port "#!~a
# Omaguix: choose a fixed time zone, or follow the Mac's.
set -e
helper=/run/current-system/profile/bin/roguix-timezone
timezone=$({ $helper --mirror-label 2>/dev/null || true; $helper --list; } | omarchy-menu-select \"Set timezone\" -- --width 520 --maxheight 520) || exit 1
sudo -n /run/current-system/profile/bin/roguix-timezone --select \"$timezone\"
omarchy-shell -q omarchy.clock refresh
omarchy-notification-send \"Timezone is now set to $timezone\"
" bash)))
                  (chmod file #o555))
                ;; Desktop files live in Guix profiles, not /usr.
                (substitute* (string-append bin "/omarchy-launch-browser")
                  (("\\{~/\\.local,~/\\.nix-profile,/usr\\}")
                   "{~/.local,~/.guix-profile,/run/current-system/profile}"))
                ;; The menu decides what is installed from pacman's database.
                (substitute* (string-append omarchy "/shell/plugins/menu/MenuModel.js")
                  (("pacman -Qq; LC_ALL=C pacman -Qi") "roguix-pkg list; true")
                  (("pacman -Q \"[$]1\"") "roguix-pkg present \"$1\""))
                ;; When the guard script ends, Menu.qml's guardProc.onExited
                ;; recreates every row even if no `when:'/`checked:' result
                ;; changed, and a click pressed on a row just before is lost
                ;; with it. Rebuild only on a change. Derived from Omarchy
                ;; c668141e (unchanged on master 988f44ea); remove once
                ;; Omarchy takes the fix.
                ;; See guest/guix/README.md, "Differences from Try Omarchy".
                (let ((qml (string-append omarchy "/shell/plugins/menu/Menu.qml")))
                  (substitute* qml
                    (("root\\.whenResults = nextWhen")
                     (string-append
                      "var guardsChanged = JSON.stringify(nextWhen) !== JSON.stringify(root.whenResults)\n"
                      "          || JSON.stringify(nextChecked) !== JSON.stringify(root.checkedResults)\n"
                      "      root.whenResults = nextWhen"))
                    (("^      if \\(root\\.opened\\) root\\.rebuildDisplay\\(\\)")
                     "      if (root.opened && guardsChanged) root.rebuildDisplay()"))
                  ;; substitute* does not fail when nothing matches.
                  (invoke "grep" "-q" "root.opened && guardsChanged" qml))
;; Try Omarchy 0c9817d: the mirrored Mac's charge state is
                ;; authoritative. UPower can report zero watts or no estimate
                ;; for a while after the Mac's AC changes, and the power panel
                ;; then showed a charging Mac as held at a charge limit.
                (let ((model (string-append omarchy
                                            "/shell/plugins/panels/power/Model.js")))
                  (substitute* model
                    (("^  if \\(d\\.state !== s\\.Charging \\|\\| fraction >= 0\\.99\\) return false")
                     (string-append
                      "  // The mirrored Mac state is authoritative. UPower can temporarily report\n"
                      "  // zero watts or no estimate after AC changes, even while charging.\n"
                      "  return false"))
                    (("^  return Number\\(d\\.changeRate .*") ""))
                  (invoke "grep" "-q" "The mirrored Mac state is authoritative" model)
                  (when (zero? (system* "grep" "-q" "d.changeRate" model))
                    (error "Model.js still estimates a held charge" model)))
                ;; Guix's Qt 6.9 QML parser rejects `transient', a reserved
                ;; word in its grammar, as a variable name, and Quickshell then
                ;; skips the whole notification service.
                (substitute* (string-append omarchy
                                            "/shell/plugins/notifications/Service.qml")
                  (("var transient = ") "var isTransient = ")
                  (("\\{ transient = ") "{ isTransient = ")
                  (("^( *)transient = !!" _ indent) (string-append indent "isTransient = !!"))
                  (("return transient [|][|]") "return isTransient ||"))
                ;; The screensaver is opt-in (roguix-omarchy-seed turns
                ;; Omarchy's screensaver-off toggle on) and runs at 30 fps,
                ;; not 120: every frame is redrawn by the terminal, copied
                ;; through virtio-gpu and composited by macOS, all on the
                ;; Mac's CPU and battery, and a text animation stays smooth
                ;; at 30.
                ;; See guest/guix/README.md, "Differences from Try Omarchy".
                (let ((screensaver (string-append bin "/omarchy-screensaver")))
                  (substitute* screensaver
                    (("--frame-rate 120 ") "--frame-rate 30 "))
                  (invoke "grep" "-q" "-e" "--frame-rate 30 " screensaver)))))
          (add-after 'install 'use-roguix-logo
            ;; omarchy-show-logo and friends print logo.txt: say GUIX, in
            ;; Omarchy's own block lettering, instead of OMARCHY.
            ;; See guest/guix/README.md, "Differences from Try Omarchy".
            (lambda _
              (copy-file #$(local-file "roguix-logo.txt")
                         (string-append #$output "/share/omarchy/logo.txt"))))
          (add-after 'use-guix-packages 'link-commands
            ;; The Arch package installs each command in /usr/bin.
            (lambda _
              (let ((bin (string-append #$output "/bin")))
                (mkdir-p bin)
                (for-each (lambda (command)
                            (symlink command
                                     (string-append bin "/" (basename command))))
                          (find-files (string-append #$output
                                                     "/share/omarchy/bin")))))))))
    ;; patch-shebangs points Omarchy's Python commands here; the agent-usage
    ;; ones need sqlite3, which python-minimal lacks.
    (native-inputs (list python))
    (inputs (list bash))
    (home-page "https://omarchy.org")
    (synopsis "Omarchy desktop configuration, shell and commands")
    (description "Omarchy is an opinionated Hyprland desktop: its Hyprland
configuration, Quickshell desktop shell, themes and helper commands.")
    (license license:expat)))

;; The Arch guest ships ttf-jetbrains-mono-nerd 3.5.1; Omarchy's fontconfig
;; maps monospace to it and the shell's bar icons are its Nerd Font glyphs.
(define font-jetbrains-mono-nerd
  (package
    (name "font-jetbrains-mono-nerd")
    (version "3.5.1")
    (source (origin
              (method url-fetch)
              (uri (string-append "https://github.com/ryanoasis/nerd-fonts"
                                  "/releases/download/v" version
                                  "/JetBrainsMono.tar.xz"))
              (sha256
               (base32
                "1kqhj2hcs3bpg8rhsb67ncg6hkl3jklngy0n7v8rsgv90gwyim84"))))
    (build-system font-build-system)
    (home-page "https://www.nerdfonts.com")
    (synopsis "JetBrains Mono patched with Nerd Font glyphs")
    (description "JetBrains Mono with the Nerd Fonts icon glyphs.")
    (license license:silofl1.1)))

;; Omarchy's default applications (install/omarchy-base.packages): Guix's
;; packages, LibreWolf standing in for Chromium, and (roguix apps) for those
;; Guix lacks. Not provided: LibreOffice, Pinta, LocalSend, Signal, Obsidian;
;; docs/omarchy-packages.md lists every difference from Omarchy's list.
;; See guest/guix/README.md, "Differences from Try Omarchy".
(define %omarchy-applications
  (append
   (map specification->package
        '("librewolf" "xdg-utils" "nautilus" "evince" "gnome-disk-utility"
          "xournalpp" "kdenlive" "btop"
          "neovim" "tmux" "git" "bat" "eza" "fd" "ripgrep" "zoxide" "starship"
          "less" "man-db" "tldr" "grim" "slurp" "hyprpicker" "wtype"
          "imagemagick" "yt-dlp" "tesseract-ocr" "pamixer" "brightnessctl"
          "playerctl" "unzip" "whois"
          ;; Portals: file choosers and screen sharing for sandboxed apps.
          "xdg-desktop-portal" "xdg-desktop-portal-gtk"
          ;; The Secret Service; Omarchy's default keyring has no password.
          "gnome-keyring"
          ;; Omarchy runs fcitx5 for compose keys; Chewing, Hangul and Noto
          ;; CJK back the optional Chinese and Korean languages.
          "fcitx5" "fcitx5-chewing" "fcitx5-hangul" "fcitx5-gtk"
          "font-google-noto-sans-cjk"))
   (list lazygit-bin lazydocker-bin gum-bin dua-bin cliamp-bin
         fastfetch-without-zfs obs-without-vlc fcitx5-qt6)))

;;; Compatibility commands for Omarchy's Arch assumptions, plus Try Omarchy's
;;; xdg-terminal-exec and the per-user seed.

;; Omaguix's commands never compile in the VM unless asked: packages come from
;; roguix.frolow.dev and Guix's servers, and --max-jobs=0 still lets Guix
;; build its local derivations (configuration, profiles, grafts) but refuses
;; any other build at once instead of compiling for hours.
;; ROGUIX_ALLOW_BUILD=1 lifts it.
(define %build-gate "\
gate='--max-jobs=0 --no-offload'
[ \"${ROGUIX_ALLOW_BUILD:-0}\" = 1 ] && gate=
gate_failed() {
  if [ -n \"$gate\" ]; then
    echo 'roguix: if Guix said \"unable to start any build\", this change needs' >&2
    echo 'packages no server has binaries for yet. Try again later, or build' >&2
    echo 'them here with ROGUIX_ALLOW_BUILD=1 (this can take hours).' >&2
  fi
  exit \"$1\"
}")

(define roguix-omarchy-compat
  (package
    (name "roguix-omarchy-compat")
    (version "1")
    (source (local-file "." "roguix-omarchy-compat-source"
                        #:recursive? #t
                        #:select? (lambda (file stat)
                                    (or (eq? 'directory (stat:type stat))
                                        (member (basename file)
                                                '("busctl" "xdg-terminal-exec"
                                                  "omarchy-seed" "roguix-pkg"
                                                  "fcitx5-profile"
                                                  "30-roguix-cjk.conf"))))))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(("busctl" "bin/")
          ("roguix-pkg" "bin/roguix-pkg")
          ("xdg-terminal-exec" "bin/")
          ("omarchy-seed" "bin/roguix-omarchy-seed")
          ("fcitx5-profile" "share/roguix/")
          ("30-roguix-cjk.conf" "share/roguix/"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'install-shims
            (lambda* (#:key inputs #:allow-other-keys)
              (define sh #$(file-append bash-minimal "/bin/sh"))
              (define (shim name text)
                (let ((file (string-append #$output "/bin/" name)))
                  (call-with-output-file file
                    (lambda (port) (format port "#!~a~%~a" sh text)))
                  (chmod file #o555)))
              ;; setpriv --pdeathsig SIGNAL COMMAND...: Guix's util-linux has
              ;; no setpriv; Omarchy's shell uses only this option, to end its
              ;; clipboard watchers with it.
              (let ((file (string-append #$output "/bin/setpriv")))
                (call-with-output-file file
                  (lambda (port)
                    (format port "#!~a~%~a"
                            #$(file-append python-minimal "/bin/python3") "\
import ctypes, os, signal, sys
arguments = sys.argv[1:]
while arguments and arguments[0].startswith('--'):
    option = arguments.pop(0)
    if option == '--':
        break
    if option != '--pdeathsig' or not arguments:
        sys.exit(f'setpriv: Omaguix supports only --pdeathsig, not {option}')
    name = arguments.pop(0).upper()
    number = int(name) if name.isdigit() else signal.Signals[
        name if name.startswith('SIG') else 'SIG' + name]
    # PR_SET_PDEATHSIG survives the exec below.
    ctypes.CDLL(None, use_errno=True).prctl(1, int(number), 0, 0, 0)
os.execvp(arguments[0], arguments)
")))
                (chmod file #o555))
              ;; uwsm-app [OPTIONS] -- COMMAND...: run COMMAND directly.
              (shim "uwsm-app" "\
while [ $# -gt 0 ] && [ \"$1\" != -- ]; do shift; done
[ $# -gt 0 ] && shift
exec \"$@\"
")
              ;; systemd-cat [-t TAG] [--] COMMAND...: log to the session's
              ;; stderr instead of the journal.
              (shim "systemd-cat" "\
while [ $# -gt 0 ]; do
  case \"$1\" in
    --) shift; break ;;
    -t|-p) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
exec \"$@\"
")
              ;; No user service manager: power actions go to elogind, which
              ;; lets the active local session power off or suspend; other
              ;; calls (environment import, timer queries) are empty successes.
              (shim "systemctl" (string-append "\
for arg; do
  case \"$arg\" in
    poweroff|reboot|suspend|hibernate) exec " #$(file-append elogind "/bin/loginctl") " \"$arg\" ;;
    -*) ;;
    *) exit 0 ;;
  esac
done
"))
              ;; systemd-run [OPTIONS] COMMAND...: run COMMAND detached from
              ;; the caller, after --on-active's delay (seconds or minutes).
              (shim "systemd-run" "\
delay=0
while [ $# -gt 0 ]; do
  case \"$1\" in
    --on-active=*) delay=${1#--on-active=}; delay=${delay%s}
      case $delay in *m) delay=$((${delay%m} * 60)) ;; esac ;;
    --unit|--description|-p|--property|--timer-property) shift ;;
    -*) ;;
    *) break ;;
  esac
  shift
done
setsid sh -c 'sleep \"$0\"; exec \"$@\"' \"$delay\" \"$@\" </dev/null >/dev/null 2>&1 &
")
              ;; uwsm stop: end the Hyprland session (Lua dispatcher syntax); tty1 then
              ;; logs in again, as a display manager would show its greeter.
              (shim "uwsm" "\
[ \"$1\" = stop ] && exec hyprctl dispatch 'hl.dsp.exit()'
exit 0
")
              ;; Apply /etc/config.scm with the Guix that built this system
              ;; (see (roguix system)), which only fetches what was added.
              (shim "roguix-reconfigure" (string-append "\
[ \"$(id -u)\" = 0 ] || \\
  exec sudo ROGUIX_ALLOW_BUILD=\"${ROGUIX_ALLOW_BUILD:-0}\" \"$0\" \"$@\"
" #$%build-gate "
/var/guix/gcroots/roguix-guix/bin/guix system reconfigure $gate \\
  -L /etc/roguix/modules /etc/config.scm \"$@\" || gate_failed $?
"))
              ;; Update Omaguix from its signed channel (docs/decisions/0004):
              ;; fetch it, authenticate every new commit from the channel
              ;; introduction, require the same Guix pin as this image, then
              ;; reconfigure /etc/config.scm with the channel's modules. The
              ;; applied modules become /etc/roguix, so roguix-reconfigure
              ;; keeps using them offline.
              (shim "roguix-update" (string-append "\
[ \"$(id -u)\" = 0 ] || \\
  exec sudo ROGUIX_ALLOW_BUILD=\"${ROGUIX_ALLOW_BUILD:-0}\" \"$0\" \"$@\"
" #$%build-gate "
set -e
git=" #$(file-append git "/bin/git") "
guix=/var/guix/gcroots/roguix-guix/bin/guix
dir=/var/lib/roguix/channel
url=" #$(roguix-trust-channel-url %roguix-trust) "
[ -d \"$dir/.git\" ] || $git clone --quiet --no-checkout \"$url\" \"$dir\"
# A checkout cloned before the channel moved follows its new URL.
$git -C \"$dir\" remote set-url origin \"$url\"
$git -C \"$dir\" fetch --quiet origin main keyring
# --end takes a commit, not a branch name.
head=$($git -C \"$dir\" rev-parse origin/main)
( cd \"$dir\" && $guix git authenticate --keyring=origin/keyring --end=\"$head\" \\
    " #$(roguix-trust-channel-introduction %roguix-trust) " \\
    '" #$(roguix-trust-channel-signer %roguix-trust) "' )
$git -C \"$dir\" checkout --quiet --detach \"$head\"
if ! cmp -s \"$dir/modules/roguix/guix-commit\" /etc/roguix/modules/roguix/guix-commit; then
  echo 'roguix-update: this Omaguix release needs a newer Guix than this VM has;' >&2
  echo 'reset Omaguix from the latest Try Omaguix app to get it.' >&2
  exit 1
fi
$guix system reconfigure $gate -L \"$dir/modules\" /etc/config.scm \"$@\" \\
  || gate_failed $?
"))
              (for-each (lambda (program)
                          (chmod (string-append #$output "/bin/" program) #o555))
                        '("busctl" "roguix-pkg" "xdg-terminal-exec"
                          "roguix-omarchy-seed"))
              (wrap-program (string-append #$output "/bin/busctl")
                `("PATH" ":" prefix
                  (,(dirname (search-input-file inputs "bin/gdbus"))))))))))
    (inputs (list bash bash-minimal `(,glib "bin") python-minimal))
    (home-page "https://github.com/omacom/try-omarchy")
    (synopsis "Run Omarchy's commands on Guix System")
    (description "Compatibility commands for Omarchy's systemd and uwsm
calls, a busctl subset over gdbus, and the Omarchy per-user seed.")
    (license license:expat)))

;; Hyprland additions for the VM: loaded from ~/.config/hypr/monitors.lua,
;; where the Arch guest appends its own QEMU fragment. Like that fragment it
;; hides Hyprland's cursor when the launcher reports VirGL (Cocoa draws the
;; Mac's cursor over the guest) and follows the window size; it also starts
;; the host bridges and the per-session sound server (see integrations.scm).
(define hypr-vm-lua
  (plain-file "hypr-vm.lua" "\
-- Omaguix VM integration, loaded from ~/.config/hypr/monitors.lua.
local function host_setting(expected)
  local file = io.open(\"/run/roguix/host-settings\", \"r\")
  if not file then return false end
  local settings = file:read(\"*a\") or \"\"
  file:close()
  for setting in settings:gmatch(\"%S+\") do
    if setting == expected then return true end
  end
  return false
end

if host_setting(\"omarchy.qemu_virgl=1\") then
  hl.config({ cursor = { invisible = true } })
end

hl.on(\"hyprland.start\", function()
  hl.exec_cmd(\"roguix-display-sync\")
  hl.exec_cmd(\"roguix-agent /dev/snd/controlC0 pipewire\")
  hl.exec_cmd(\"roguix-agent /dev/snd/controlC0 wireplumber\")
  hl.exec_cmd(\"roguix-agent /dev/snd/controlC0 pipewire-pulse\")
  hl.exec_cmd(\"roguix-agent /dev/virtio-ports/dev.tryomarchy.clipboard roguix-clipboard-bridge\")
  hl.exec_cmd(\"roguix-agent /dev/virtio-ports/dev.tryomarchy.audio roguix-audio-bridge\")
  hl.exec_cmd(\"roguix-agent /dev/virtio-ports/dev.tryomarchy.camera roguix-camera-bridge\")
  -- Omarchy's omarchy-fcitx5 user unit: compose sequences and Chewing.
  hl.exec_cmd(\"roguix-agent /run/current-system fcitx5 --disable notificationitem\")
end)
"))

;; Quickshell's lock plugin authenticates with this PAM service and refuses
;; to lock without it; Omarchy's Arch stack is pam_unix underneath.
(define (omarchy-pam-services _)
  (list (unix-pam-service "omarchy-lock-password")))

(define roguix-omarchy-service-type
  (service-type
   (name 'roguix-omarchy)
   (extensions
    (list (service-extension special-files-service-type
                             (const `(("/usr/share/omarchy"
                                       ,(file-append omarchy "/share/omarchy")))))
          (service-extension etc-service-type
                             (const `(("roguix-hypr-vm.lua" ,hypr-vm-lua))))
          (service-extension pam-root-service-type omarchy-pam-services)
          (service-extension profile-service-type
                             (const
                              (append
                               (list omarchy roguix-omarchy-compat quickshell-0.3
                                    foot jq socat inotify-tools hyprsunset ncurses
                                    fzf imv mpv
                                    ;; Omarchy's menus, clipboard capture and
                                    ;; name title-casing call perl.
                                    perl
                                    fontconfig procps gawk util-linux curl
                                    `(,gtk+ "bin") libnotify xdg-user-dirs
                                    qtimageformats yaru-theme font-liberation
                                    font-jetbrains-mono-nerd ttfx)
                               %omarchy-applications)))))
   (default-value #f)
   (description "Install Omarchy 4's desktop, shell and theme.")))
