;;; Omaguix — the guest's operating system.
;;;
;;; `omaguix-operating-system' is the whole system; guest/guix/system.scm
;;; builds the image from it with no extra packages. In the guest,
;;; /etc/config.scm calls it with the owner's package list (edited by hand or
;;; by Omarchy's install menus through omaguix-pkg), and
;;; `sudo omaguix-reconfigure' applies it with the Guix that built the image.
(define-module (omaguix system)
  #:use-module (gnu)
  #:use-module (gnu system linux-initrd)
  #:use-module (gnu system locale)
  #:use-module (guix gexp)
  #:use-module (guix grafts)
  #:use-module ((guix store) #:select (direct-store-path?))
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 textual-ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (omaguix integrations)
  #:use-module (omaguix omarchy)
  #:use-module (omaguix packages)
  #:use-module (omaguix services)
  #:use-module (omaguix trust)
  #:export (omaguix-operating-system
            %omaguix-reference-system
            %pinned-guix-root))
(use-service-modules desktop docker linux sddm sound ssh xorg)
(use-package-modules fonts gl linux package-management terminals
                     window-management xdisorg)

;; The Guix that evaluated the system. Building the image, that is the pinned
;; commit run by `guix time-machine'; the image keeps it as a GC root, and in
;; the guest the system reuses that same store item instead of rebuilding it,
;; so reconfiguring with it computes the very derivations the image was built
;; from and only fetches what the owner adds. omaguix-update moves the system
;; to a release's Guix by running that Guix with OMAGUIX_GUIX set to it, which
;; pins it instead (docs/decisions/0007).
(define %pinned-guix-root "/var/guix/gcroots/omaguix-guix")
(define (pinned-guix)
  (match (getenv "OMAGUIX_GUIX")
    (#f (if (file-exists? %pinned-guix-root)
            (readlink %pinned-guix-root)
            (current-guix)))
    ((? direct-store-path? guix) guix)
    (other (error "OMAGUIX_GUIX is not a store item:" other))))

;; Files that define this system; build and test tooling is left out.
(define (omaguix-source? file stat)
  (or (eq? 'directory (stat:type stat))
      (member (basename file) '("system.scm"))
      (string-contains file "/modules/omaguix/")))

;; The commit of the channel's main this system was built from, kept as
;; /etc/omaguix/channel-commit: omaguix-update moves only to a main that
;; descends from it (docs/decisions/0007). build.py (the image) and
;; omaguix-update set OMAGUIX_CHANNEL_COMMIT; any other reconfigure, such as
;; omaguix-reconfigure's, keeps the running system's record.
(define %channel-commit-file "/etc/omaguix/channel-commit")
(define (channel-commit)
  (let ((commit (or (getenv "OMAGUIX_CHANNEL_COMMIT")
                    (and (file-exists? %channel-commit-file)
                         (string-trim-both
                          (call-with-input-file %channel-commit-file
                            get-string-all))))))
    (cond ((not commit) #f)
          ((string-match "^[0-9a-f]{40}$" commit) commit)
          (else (error "not a channel commit:" commit)))))

(define (omaguix-sources)
  (let ((sources (local-file "../.." "omaguix-sources"
                             #:recursive? #t
                             #:select? omaguix-source?))
        (commit (channel-commit)))
    (if commit
        (computed-file "omaguix-sources"
                       (with-imported-modules '((guix build utils))
                         #~(begin
                             (use-modules (guix build utils))
                             (copy-recursively #$sources #$output
                                               #:log (%make-void-port "w"))
                             (call-with-output-file
                                 (string-append #$output "/channel-commit")
                               (lambda (port)
                                 (display #$commit port)
                                 (newline port))))))
        sources)))

;; Installed as /etc/config.scm on first boot, then the owner's to edit.
(define config-template
  (plain-file "config.scm" "\
;; Omaguix: this machine's system configuration.
;;
;; Add programs by their Guix package names (`guix search NAME' finds them),
;; then apply the change with:
;;
;;   sudo omaguix-reconfigure
;;
;; Omarchy's install menus edit the same list. The host name, time zone,
;; keyboard and language come from the first-start setup, kept in
;; /var/lib/omaguix/machine-settings.scm; #:host-name, #:timezone,
;; #:keyboard-layout, #:keyboard-variant and #:locale (e.g. \"pl_PL.utf8\")
;; here override them. Everything else is the Omaguix system in /etc/omaguix,
;; which this reuses as is.
(use-modules (omaguix system))

(omaguix-operating-system
 #:packages
 '(;; BEGIN omaguix packages
   ;; END omaguix packages
   ))
"))

(define omaguix-config-activation
  #~(unless (file-exists? "/etc/config.scm")
      (copy-file #$config-template "/etc/config.scm")
      (chmod "/etc/config.scm" #o644)))

;; Guix builds every package first without grafts (its security fixes applied
;; to finished binaries) and then grafts it. The image holds only grafted
;; items, so a reconfigure, which grafts again, would rebuild Omaguix's own
;; packages (Hyprland, Quickshell), which have no substitutes, and download
;; the ungrafted Guix packages. The image therefore keeps the whole ungrafted
;; system as a GC root.
(define %ungrafted-root "/var/guix/gcroots/omaguix-ungrafted")

;; An operating system as a file-like object: its system derivation's output.
(define-record-type <system-closure>
  (system-closure os)
  system-closure?
  (os system-closure-os))

(define-gexp-compiler (system-closure-compiler (closure <system-closure>)
                                               system target)
  (operating-system-derivation (system-closure-os closure)))

(define (omaguix-operating-system . options)
  "Return the Omaguix system, adding #:packages, a list of package names.
#:host-name, #:timezone, #:keyboard-layout and #:keyboard-variant (XKB names)
and #:locale (a Guix locale name such as \"zh_TW.utf8\") default to the
first-start setup's answers (%omaguix-machine-settings-file), then to the
image's defaults."
  (apply settings-operating-system (read-machine-settings) options))

(define* (settings-operating-system settings #:key (packages '())
                                    host-name timezone keyboard-layout
                                    keyboard-variant locale)
  "Return the Omaguix system for SETTINGS, the machine settings alist."
  (define (setting key)
    (let ((value (assq-ref settings key)))
      (and value (not (string-null? value)) value)))
  (let* ((host-name (or host-name (setting 'host-name) "omaguix"))
         (timezone (or timezone (setting 'timezone) "Etc/UTC"))
         (layout (or keyboard-layout (setting 'keyboard-layout) "us"))
         (variant (or keyboard-variant
                      (and (not keyboard-layout) (setting 'keyboard-variant))))
         (locale (or locale (setting 'locale) "en_US.utf8"))
         (os (base-operating-system packages host-name timezone layout
                                    variant
                                    (or (setting 'console-keymap) "")
                                    locale)))
    (operating-system
      (inherit os)
      (services
       (cons (extra-special-file %ungrafted-root
                                 (with-parameters ((%graft? #f))
                                   (system-closure os)))
             (operating-system-user-services os))))))

(define (base-operating-system packages host-name timezone layout variant
                               console-keymap locale)
  (operating-system
    (host-name host-name)
    (timezone timezone)
    (locale locale)
    ;; The image's optional languages (artifact.LOCALES): the first-start
    ;; setup takes the Mac's (tryomarchy.locale) once. Defined here, so that
    ;; choosing one does not rebuild the locales; Guix adds any other LOCALE.
    ;; zh_CN.utf8 is one of %default-locale-definitions.
    (locale-definitions
     (cons* (locale-definition (name "zh_TW.utf8") (source "zh_TW")
                               (charset "UTF-8"))
            (locale-definition (name "ko_KR.utf8") (source "ko_KR")
                               (charset "UTF-8"))
            %default-locale-definitions))
    (keyboard-layout (if variant
                         (keyboard-layout layout variant)
                         (keyboard-layout layout)))
    (kernel linux-libre)
    (firmware '())
    ;; /dev/video42 for the Mac camera (omaguix-camera-service-type) and the
    ;; mirrored Mac battery (omaguix-battery-service-type).
    (kernel-loadable-modules (list v4l2loopback-linux-module
                                   omaguix-battery-module))
    (initrd-modules (cons* "virtio_gpu" "virtio_console"
                           (base-initrd-modules linux-libre)))
    ;; Guix builds the keyboard layout into the initrd, for typing a LUKS
    ;; passphrase; the VM's disk is not encrypted. Left out, the initrd no
    ;; longer changes with the first-start setup's layout, whose reconfigure
    ;; would otherwise rebuild the initrd's kernel modules, which no server
    ;; offers.
    (initrd (lambda (file-systems . options)
              (apply base-initrd file-systems
                     (let loop ((options options))
                       (match options
                         (() '())
                         ((#:keyboard-layout _ . rest) (loop rest))
                         ((key value . rest)
                          (cons* key value (loop rest))))))))
    ;; The VM's display is Retina-sized: the kernel's 8x16 console font is
    ;; unreadably small there, so boot messages use its built-in Terminus
    ;; 16x32 (see also console-font-service-type below).
    ;; The launcher sizes the display to the window's Retina pixels, where
    ;; Terminus 16x32 is small; at 1920x1080 scaled up it was too large. The
    ;; text console uses 2560x1440, outside the EDID's list, so M asks the
    ;; kernel for CVT timings. Hyprland sets its own mode from the window
    ;; (omaguix-display-sync).
    (kernel-arguments (cons* "console=hvc0" "fbcon=font:TER16x32"
                             "video=Virtual-1:2560x1440M"
                             %default-kernel-arguments))

    ;; The launcher boots EDK2 with -bios, which keeps no UEFI variables, so
    ;; GRUB must live at the removable-media path EFI/BOOT/BOOTAA64.EFI; every
    ;; reconfigure reinstalls it there.
    (bootloader (bootloader-configuration
                  (bootloader grub-efi-removable-bootloader)
                  (targets '("/boot/efi"))
                  ;; At the display's native size GRUB's text is tiny; QEMU
                  ;; scales this mode up to the window.
                  ;; The inherited background is an SVG converted with
                  ;; guile-rsvg (librsvg, Rust): check it has substitutes when
                  ;; moving the pin (guest/guix/README.md).
                  (theme (grub-theme
                          (inherit (grub-theme))
                          (gfxmode '("1024x768" "auto"))))))
    ;; The image itself mounts / by a UUID that `guix system image` derives; this
    ;; label is what that partition's ext4 carries, so an in-guest reconfigure
    ;; of this file finds the same root.
    (file-systems
     (cons* (file-system
              (mount-point "/")
              (device (file-system-label "Guix_image"))
              (type "ext4"))
            (file-system
              (mount-point "/boot/efi")
              (device (file-system-label "GNU-ESP"))
              (type "vfat"))
            %base-file-systems))

    (users (cons* (user-account
                   (name "root")
                   (uid 0)
                   (group "root")
                   (home-directory "/root")
                   (password "!"))
                  ;; No password ships in the image: the account starts locked
                  ;; and omaguix-first-boot asks for one on the first start.
                  (user-account
                   (name %omaguix-account)
                   (uid 1000)
                   (group "users")
                   (password "!")
                   (supplementary-groups '("wheel" "netdev" "audio" "video")))
                  %base-user-accounts))
    ;; Omarchy's time zone menu runs without a terminal, where sudo cannot
    ;; ask for the password; Omarchy lets wheel set the zone without one
    ;; (etc/sudoers.d/omarchy-tzupdate), and so does this rule for its
    ;; replacement, omaguix-timezone, which checks the zone itself.
    (sudoers-file
     (plain-file "sudoers"
                 (string-append
                  (plain-file-content %sudoers-specification)
                  "%wheel ALL=(root) NOPASSWD: "
                  "/run/current-system/profile/bin/omaguix-timezone "
                  "^--select (Same as macOS|[A-Za-z0-9_+][A-Za-z0-9_+-]*"
                  "(/[A-Za-z0-9_+][A-Za-z0-9_+-]*)*)$\n")))

    ;; Foot avoids the separate Kitty OpenGL-context workaround in the Arch
    ;; guest. Keep compositor rendering on VirGL, without a software override.
    (packages (append (list hyprland-0.56 xdg-desktop-portal-hyprland-0.56
                            omaguix-display-sync
                            foot wofi font-dejavu mesa-utils)
                      (map specification->package packages)
                      %base-packages))
    (services
     (cons* ;; The same definitions for in-guest reconfigure and rollback, so they
            ;; never fall back to the pinned checkout's broken Hyprland 0.55.4:
            ;;   sudo guix system reconfigure -L /etc/omaguix/modules \
            ;;     /etc/omaguix/system.scm
            (simple-service 'omaguix-sources etc-service-type
                            `(("omaguix" ,(omaguix-sources))))
            ;; Omarchy 4's desktop: its Hyprland configuration and Quickshell
            ;; shell, seeded into the account at the first desktop login.
            (service omaguix-omarchy-service-type)
            (service omaguix-grow-root-service-type)
            ;; The VM disk is attached with discard=unmap, so a trim gives
            ;; deleted files' blocks back to the Mac. Hourly rather than
            ;; Guix's weekly default: Shepherd's timer does not catch up on
            ;; a run missed while the VM was closed, and ext4 skips groups
            ;; already trimmed since the mount, so a run costs little.
            (service fstrim-service-type
                     (fstrim-configuration (schedule "0 * * * *")))
            (extra-special-file %pinned-guix-root (pinned-guix))
            (simple-service 'omaguix-config activation-service-type
                            omaguix-config-activation)
            (service omaguix-first-boot-service-type)
            ;; What this system is built with; the boot service applies the
            ;; settings file only where it differs.
            (service omaguix-machine-settings-service-type
                     `((host-name . ,host-name)
                       (timezone . ,timezone)
                       (keyboard-layout . ,layout)
                       (keyboard-variant . ,(or variant ""))
                       (console-keymap . ,console-keymap)
                       (locale . ,locale)))
            (service omaguix-host-settings-service-type)
            (service omaguix-mac-share-service-type)
            (service omaguix-clipboard-service-type)
            (service omaguix-audio-service-type)
            (service omaguix-camera-service-type)
            (service omaguix-battery-service-type)
            (service omaguix-timezone-service-type)
            (service omaguix-settings-service-type)
            ;; Omarchy's Hyprland input reads the layout from systemd's
            ;; vconsole.conf; Guix keeps it in keyboard-layout instead.
            (simple-service 'omaguix-vconsole etc-service-type
                            `(("vconsole.conf"
                               ,(plain-file "vconsole.conf"
                                            (string-append
                                             "XKBLAYOUT=" layout "\n"
                                             "XKBVARIANT=" (or variant "")
                                             "\n")))))
            (service omaguix-touch-id-service-type)
            ;; Installed but never auto-started: omaguix-ssh-access starts it
            ;; for one boot when the launcher forwards SSH.
            (service openssh-service-type
                     (openssh-configuration
                      (%auto-start? #f)
                      (permit-root-login #f)))
            (service omaguix-ssh-access-service-type)
            ;; Omarchy's Docker: the daemon runs, but the account is not in the
            ;; docker group (root-equivalent), so the CLI runs under sudo.
            (service containerd-service-type)
            (service docker-service-type)
            ;; Like the Arch guest, log straight in on the VM console: the disk
            ;; is protected by the Mac account. tty1 waits for the first-start
            ;; password prompt, then /etc/profile.d starts Hyprland there.
            (simple-service 'omaguix-session etc-profile-d-service-type
                            (list omaguix-session-script))
            (modify-services
                (remove (lambda (service)
                          (memq (service-kind service)
                                (list gdm-service-type sddm-service-type)))
                        %desktop-services)
              ;; Omaguix's own packages (Hyprland, Quickshell, Omarchy, the
              ;; VM agents) have no substitutes on Guix's servers; its server
              ;; publishes them, signed with its key, after Guix's own
              ;; servers in the search order ((omaguix trust)).
              (guix-service-type
               config => (guix-configuration
                          (inherit config)
                          (substitute-urls
                           (append (guix-configuration-substitute-urls config)
                                   (list (omaguix-trust-substitute-url %omaguix-trust))))
                          (authorized-keys
                           (cons (omaguix-trust-substitute-key %omaguix-trust)
                                 (guix-configuration-authorized-keys config)))))
              ;; pipewire-pulse serves the PulseAudio socket; pactl (the audio
              ;; bridge's tool) must never start a real PulseAudio daemon.
              ;; The Mac's own low-power handling is the only authority: UPower
              ;; still warns, but its action threshold of 0% never suspends or
              ;; powers off the VM (this UPower has no Ignore action).
              (upower-service-type
               config => (upower-configuration
                          (inherit config)
                          (use-percentage-for-policy? #t)
                          (percentage-action 0)))
              (pulseaudio-service-type
               config => (pulseaudio-configuration
                          (inherit config)
                          (client-conf '((autospawn . no)))))
              (console-font-service-type
               config => (map (lambda (tty)
                                (cons (car tty) %omaguix-console-font))
                              config))
              (mingetty-service-type
               config => (if (string=? (mingetty-configuration-tty config) "tty1")
                             (mingetty-configuration
                              (inherit config)
                              (auto-login %omaguix-account)
                              ;; The shared folder is mounted before the
                              ;; session starts, as in the Arch guest. The
                              ;; login also waits for Shepherd's elogind:
                              ;; pam_elogind would otherwise D-Bus-activate a
                              ;; second one, Shepherd would disable its own,
                              ;; and everything requiring elogind (pam, sshd)
                              ;; could no longer start.
                              (shepherd-requirement
                               (cons* 'omaguix-first-boot 'omaguix-mac-share
                                      'omaguix-machine-settings
                                      'elogind
                                      (mingetty-configuration-shepherd-requirement
                                       config))))
                             config)))))))

;; The image's system with the default host settings, independent of any
;; machine's settings file: what omaguix/omaguix's CI builds substitutes for,
;; the same derivation wherever it is evaluated. Its extra packages are those
;; Omaguix publishes substitutes for without putting them in the image:
;; Odin, (omaguix odin), requested for lang-for-ai's checks on both
;; architectures. Names, as in /etc/config.scm.
;; Defined last: it calls the procedures above when the module loads.
(define %omaguix-reference-system
  (settings-operating-system '() #:packages '("odin")))
