;;; Omaguix — guest side of the launcher's macOS integrations.
;;;
;;; The host side and its wire protocols come from Try Omarchy, unchanged,
;;; and so do the guest programs next to this module (reviewed there as the
;;; Arch guest's scripts); here Shepherd services and login hooks start them
;;; instead of systemd units.
;;;
;;; A UEFI guest boots its own GRUB, so the launcher passes its `name=value'
;;; settings as SMBIOS OEM strings (type 11) rather than on a kernel command
;;; line, and
;;; omaguix-host-settings writes them to %omaguix-host-settings-file in the
;;; command line's format. That file lives in /run: settings last one boot.
(define-module (omaguix integrations)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system linux-module)
  #:use-module (guix build-system trivial)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu packages tls)
  #:use-module (gnu packages python)
  #:use-module (gnu packages version-control)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu services)
  #:use-module (gnu services base)
  #:use-module (gnu services linux)
  #:use-module (gnu services shepherd)
  #:use-module (gnu services ssh)
  #:use-module (gnu system pam)
  #:export (%omaguix-host-settings-file
            omaguix-host-settings-service-type
            omaguix-mac-share
            omaguix-mac-share-service-type
            omaguix-agent
            omaguix-clipboard-bridge
            omaguix-clipboard-service-type
            omaguix-audio-bridge
            omaguix-audio-service-type
            omaguix-camera-bridge
            omaguix-camera-service-type
            omaguix-battery-module
            omaguix-battery-service-type
            omaguix-settings
            omaguix-setup
            omaguix-settings-service-type
            omaguix-timezone
            omaguix-timezone-service-type
            omaguix-touch-id
            omaguix-touch-id-service-type
            omaguix-ssh-access-service-type))

(define %omaguix-host-settings-file "/run/omaguix/host-settings")

(define host-settings-program
  (program-file
   "omaguix-host-settings"
   #~(begin
       (use-modules (ice-9 binary-ports) (ice-9 ftw) (ice-9 iconv) (ice-9 regex)
                    (rnrs bytevectors) (srfi srfi-1))

       (define directory "/sys/firmware/dmi/entries")
       ;; Exactly the launcher's argument shape; anything else is ignored.
       (define setting
         (make-regexp "^(omarchy|tryomarchy)\\.[a-z_]+=[A-Za-z0-9_.-]*$"))

       (define (oem-strings entry)
         ;; An SMBIOS structure: a formatted area whose length is byte 1,
         ;; then NUL-terminated strings ending with an empty one.
         (let* ((raw (call-with-input-file
                         (string-append directory "/" entry "/raw")
                       (lambda (port) (get-bytevector-all port))
                       #:binary #t))
                (start (bytevector-u8-ref raw 1))
                (text (bytevector->string
                       (let ((strings (make-bytevector
                                       (- (bytevector-length raw) start))))
                         (bytevector-copy! raw start strings 0
                                           (bytevector-length strings))
                         strings)
                       "ISO-8859-1")))
           (string-split text #\nul)))

       ;; A missing or unreadable table means no settings, never a failure:
       ;; the shared folder and the tty1 session start after this service.
       (define settings
         (catch #t
           (lambda ()
             (filter (lambda (value) (regexp-exec setting value))
                     (append-map oem-strings
                                 (or (scandir directory
                                              (lambda (name)
                                                (string-prefix? "11-" name)))
                                     '()))))
           (lambda (key . arguments)
             (format (current-error-port)
                     "omaguix-host-settings: ignoring SMBIOS: ~a ~s~%"
                     key arguments)
             '())))

       (define target #$%omaguix-host-settings-file)
       (define staging (string-append target ".new"))
       (unless (file-exists? (dirname target))
         (mkdir (dirname target) #o755))
       (call-with-output-file staging
         (lambda (port)
           (chmod port #o644)
           (display (string-join settings " ") port)
           (newline port)))
       (rename-file staging target))))

(define (host-settings-shepherd-service _)
  (list (shepherd-service
         (provision '(omaguix-host-settings))
         (requirement '(file-systems))
         (one-shot? #t)
         (documentation "Record the launcher's settings for this boot.")
         (start #~(lambda _
                    (zero? (system* #$host-settings-program)))))))

(define omaguix-host-settings-service-type
  (service-type
   (name 'omaguix-host-settings)
   (extensions (list (service-extension shepherd-root-service-type
                                        host-settings-shepherd-service)))
   (default-value #f)
   (description "Write the launcher's SMBIOS OEM settings to /run/omaguix.")))

;;; Shared folder: the launcher attaches virtio-9p with mount tag `mac' and
;;; passes the folder's name as omarchy.shared_folder_name. The mount runs as
;;; root before tty1 logs in; each login of the desktop account links ~/<name>.

(define omaguix-mac-share
  (package
    (name "omaguix-mac-share")
    (version "1")
    (source (local-file "mac-share"))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan #~'(("mac-share" "bin/omaguix-mac-share"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap
            (lambda* (#:key inputs #:allow-other-keys)
              (let ((program (string-append #$output "/bin/omaguix-mac-share")))
                (chmod program #o555)
                (wrap-program program
                  `("OMARCHY_MAC_SHARE_CMDLINE" = (#$%omaguix-host-settings-file))
                  `("PATH" ":" prefix
                    ,(map (lambda (command)
                            (dirname (search-input-file inputs command)))
                          '("bin/base64" "bin/find" "bin/modprobe"
                            "bin/mount" "bin/mountpoint"))))))))))
    (inputs (list bash-minimal coreutils findutils kmod util-linux))
    (home-page "https://github.com/omacom/try-omarchy")
    (synopsis "Mount and link the Mac folder shared by the launcher")
    (description "Mount the launcher's virtio-9p share and link it into the
home directory under the Mac folder's own name.")
    (license license:expat)))

(define mac-share-program
  (file-append omaguix-mac-share "/bin/omaguix-mac-share"))

(define (mac-share-shepherd-service _)
  (list (shepherd-service
         (provision '(omaguix-mac-share))
         (requirement '(file-systems udev kernel-module-loader
                        omaguix-host-settings))
         (documentation "Mount the Mac folder shared by the launcher.")
         ;; tty1's session waits for this service; a failed mount is logged
         ;; by the script and must not keep the desktop from starting.
         (start #~(lambda _
                    (system* #$mac-share-program "--mount")
                    #t))
         (stop #~(lambda _
                   (system* #$mac-share-program "--unmount")
                   #f)))))

;; Sourced by every login shell; it links for the desktop account only and
;; is idempotent, so the serial console and SSH logins are harmless.
(define mac-share-link-script
  (mixed-text-file "omaguix-mac-share-link.sh"
                   "if [ \"$(id -u)\" = 1000 ]; then\n  "
                   mac-share-program " --link 2>/dev/null || true\nfi\n"))

(define omaguix-mac-share-service-type
  (service-type
   (name 'omaguix-mac-share)
   (extensions
    (list (service-extension shepherd-root-service-type
                             mac-share-shepherd-service)
          (service-extension kernel-module-loader-service-type
                             (const '("9pnet_virtio" "9p")))
          (service-extension etc-profile-d-service-type
                             (const (list mac-share-link-script)))))
   (default-value #f)
   (description "Mount the launcher's shared Mac folder and link it at login.")))


;;; Session agents: the Arch guest runs its bridges as systemd user units
;;; with Restart=. Hyprland starts each one here through omaguix-agent, which
;;; runs it while this compositor's socket and the bridge's virtio port exist,
;;; and restarts it 2 s after it exits (the bridges exit when the host side
;;; disconnects). Agents therefore end with the session.

(define omaguix-agent
  (package
    (name "omaguix-agent")
    (version "1")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((program (string-append #$output "/bin/omaguix-agent")))
            (mkdir-p (dirname program))
            (call-with-output-file program
              (lambda (port)
                (format port "#!~a
# omaguix-agent PORT PROGRAM...: keep PROGRAM running for this session.
[ -n \"$WAYLAND_DISPLAY\" ] || { echo 'omaguix-agent: no Wayland session' >&2; exit 1; }
socket=\"$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY\"
port=$1
shift
while [ -S \"$socket\" ]; do
  [ -e \"$port\" ] && \"$@\"
  sleep 2
done
" #$(file-append bash-minimal "/bin/sh"))))
            (chmod program #o555)))))
    (home-page "https://github.com/omacom/try-omarchy")
    (synopsis "Restart an Omaguix bridge for the life of the session")
    (description "Run a host bridge while the Wayland session and its virtio
port exist, restarting it after it exits.")
    (license license:expat)))

;; A guest script written for /usr/bin whose #!/usr/bin/python3 becomes Guix's Python and
;; whose tools are put on PATH. SOURCE is (local-file FILE), written at the
;; call site so it resolves next to this module.
(define* (guest-python-script name file source #:key (tools '())
                                   (inputs '()) synopsis)
  (package
    (name name)
    (version "1")
    (source source)
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan #~'((#$file #$(string-append "bin/" name)))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap
            (lambda* (#:key inputs #:allow-other-keys)
              (let ((program (string-append #$output "/bin/" #$name)))
                (chmod program #o555)
                (unless (null? '#$tools)
                  (wrap-program program
                    `("PATH" ":" prefix
                      ,(map (lambda (tool)
                              (dirname (search-input-file inputs tool)))
                            '#$tools))))))))))
    (inputs (cons* bash-minimal python-minimal inputs))
    (home-page "https://github.com/omacom/try-omarchy")
    (synopsis synopsis)
    (description synopsis)
    (license license:expat)))

;;; Clipboard: JSON lines on dev.tryomarchy.clipboard; wl-clipboard's
;;; data-control protocol observes and replaces the Hyprland selection.

(define omaguix-clipboard-bridge
  (guest-python-script "omaguix-clipboard-bridge" "clipboard-bridge"
                            (local-file "clipboard-bridge")
                            #:tools '("bin/wl-paste")
                            #:inputs (list wl-clipboard)
                            #:synopsis "Share the Wayland clipboard with macOS"))

(define omaguix-clipboard-service-type
  (service-type
   (name 'omaguix-clipboard)
   (extensions
    (list (service-extension udev-service-type
                             (const
                              (list (udev-rule
                                     "92-omaguix-clipboard.rules"
                                     "SUBSYSTEM==\"virtio-ports\", ATTR{name}==\"dev.tryomarchy.clipboard\", GROUP=\"users\", MODE=\"0660\"\n"))))
          (service-extension profile-service-type
                             (const (list omaguix-agent
                                          omaguix-clipboard-bridge
                                          wl-clipboard)))))
   (default-value #f)
   (description "Install the clipboard bridge and its port permissions.")))

;;; SSH: the launcher adds tryomarchy.ssh_access=1 only while a forward to
;;; guest port 22 is configured. sshd is installed but never auto-started;
;;; this one-shot starts it for the current boot when that exact setting is
;;; present, and nothing is written for later boots.

(define (ssh-access-shepherd-service _)
  (list (shepherd-service
         (provision '(omaguix-ssh-access))
         (requirement '(omaguix-host-settings))
         (one-shot? #t)
         (documentation "Start sshd when the launcher forwards SSH.")
         (start #~(lambda _
                    (let ((settings
                           (false-if-exception
                            (call-with-input-file #$%omaguix-host-settings-file
                              (@ (ice-9 rdelim) read-line)))))
                      (when (and (string? settings)
                                 (member "tryomarchy.ssh_access=1"
                                         (string-tokenize settings)))
                        (start-service (lookup-service 'ssh-daemon)))
                      #t))))))

(define omaguix-ssh-access-service-type
  (service-type
   (name 'omaguix-ssh-access)
   (extensions
    (list (service-extension shepherd-root-service-type
                             ssh-access-shepherd-service)))
   (default-value #f)
   (description "Start the SSH daemon only when the launcher forwards SSH.")))

;;; Audio: sound itself flows through QEMU's intel-hda; the bridge only mirrors
;;; the Mac's devices as PipeWire remap endpoints and relays the selection
;;; over dev.tryomarchy.audio, driving pipewire-pulse through pactl. PipeWire,
;;; WirePlumber and pipewire-pulse run per session like the bridges; the
;;; Arch guest's graph quantum setting for the emulated HDA is installed as is.

(define omaguix-audio-bridge
  (guest-python-script "omaguix-audio-bridge" "audio-bridge"
                            (local-file "audio-bridge")
                            #:tools '("bin/pactl")
                            #:inputs (list pulseaudio)
                            #:synopsis "Expose macOS audio devices to PipeWire"))

(define omaguix-audio-service-type
  (service-type
   (name 'omaguix-audio)
   (extensions
    (list (service-extension udev-service-type
                             (const
                              (list (udev-rule
                                     "91-omaguix-audio.rules"
                                     "SUBSYSTEM==\"virtio-ports\", ATTR{name}==\"dev.tryomarchy.audio\", GROUP=\"audio\", MODE=\"0660\"\n"))))
          (service-extension etc-service-type
                             (const
                              `(("pipewire/pipewire.conf.d/90-try-omarchy-quantum.conf"
                                 ,(local-file "pipewire-quantum.conf")))))
          (service-extension profile-service-type
                             (const (list pipewire wireplumber pulseaudio
                                          omaguix-agent
                                          omaguix-audio-bridge)))))
   (default-value #f)
   (description "Run PipeWire per session with the macOS audio bridge.")))

;;; Camera: the Mac camera streams 1280x720 NV12 frames over
;;; dev.tryomarchy.camera only while a Linux program reads /dev/video42, a
;;; v4l2loopback device (operating-system kernel-loadable-modules must list
;;; v4l2loopback-linux-module). Module options are the Arch guest's.

(define omaguix-camera-bridge
  (guest-python-script "omaguix-camera-bridge" "camera-bridge"
                            (local-file "camera-bridge")
                            #:synopsis "Expose the macOS camera as /dev/video42"))

(define omaguix-camera-service-type
  (service-type
   (name 'omaguix-camera)
   (extensions
    (list (service-extension kernel-module-loader-service-type
                             (const '("v4l2loopback")))
          (service-extension etc-service-type
                             (const
                              `(("modprobe.d/90-try-omarchy-camera.conf"
                                 ,(local-file "camera-modprobe.conf")))))
          (service-extension udev-service-type
                             (const
                              (list (udev-rule
                                     "94-omaguix-camera.rules"
                                     "SUBSYSTEM==\"virtio-ports\", ATTR{name}==\"dev.tryomarchy.camera\", GROUP=\"video\", MODE=\"0660\"
KERNEL==\"video42\", SUBSYSTEM==\"video4linux\", GROUP=\"video\", MODE=\"0660\"\n"))))
          (service-extension profile-service-type
                             (const (list omaguix-agent
                                          omaguix-camera-bridge)))))
   (default-value #f)
   (description "Load v4l2loopback and install the macOS camera bridge.")))

;;; Battery: the launcher mirrors the Mac's battery as JSON lines on
;;; dev.tryomarchy.battery. Try Omarchy's kernel module publishes BAT0/ADP0
;;; power_supply devices fed through its sysfs state file, which the root
;;; agent writes; UPower and Omarchy's battery indicator read them as usual.

(define omaguix-battery-module
  (package
    (name "omaguix-battery-module")
    ;; Try Omarchy's MODULE_VERSION.
    (version "1.3.0")
    (source (local-file "battery-module" #:recursive? #t))
    (build-system linux-module-build-system)
    (arguments (list #:tests? #f))
    (home-page "https://github.com/omacom/try-omarchy")
    (synopsis "Mirror the macOS battery as a Linux power_supply")
    (description "Kernel module exposing BAT0 and ADP0 whose state the
Omaguix battery agent sets from the host.")
    (license license:gpl2)))

(define omaguix-battery-bridge
  (guest-python-script "omaguix-battery-bridge" "battery-bridge"
                       (local-file "battery-bridge")
                       #:synopsis "Mirror the macOS battery into the guest"))

(define (battery-shepherd-service _)
  (list (shepherd-service
         (provision '(omaguix-battery))
         (requirement '(udev kernel-module-loader))
         (respawn? #t)
         (respawn-delay 1)
         (documentation "Mirror the macOS battery into the guest.")
         (start #~(lambda _
                    ;; Both exist only in a launcher VM with the module
                    ;; loaded; otherwise stay stopped.
                    (and (file-exists? "/dev/virtio-ports/dev.tryomarchy.battery")
                         (file-exists?
                          "/sys/devices/platform/try-omarchy-battery/state")
                         (fork+exec-command
                          (list #$(file-append omaguix-battery-bridge
                                               "/bin/omaguix-battery-bridge"))))))
         (stop #~(make-kill-destructor)))))

(define omaguix-battery-service-type
  (service-type
   (name 'omaguix-battery)
   (extensions
    (list (service-extension kernel-module-loader-service-type
                             (const '("try_omarchy_battery")))
          (service-extension udev-service-type
                             (const
                              (list (udev-rule
                                     "95-omaguix-battery.rules"
                                     "SUBSYSTEM==\"virtio-ports\", ATTR{name}==\"dev.tryomarchy.battery\", MODE=\"0600\"\n"))))
          (service-extension shepherd-root-service-type
                             battery-shepherd-service)))
   (default-value #f)
   (description "Load the battery module and run the macOS battery agent.")))

;;; Time zone: while the machine settings follow the Mac (omaguix-setup's
;;; "Same as macOS"), omaguix-timezone applies the zone the launcher sends on
;;; the root-only dev.tryomarchy.timezone port every five seconds. A zone
;;; chosen in the setup or in Omarchy's time zone menu stops following;
;;; "Same as macOS" in that menu resumes it.
;;; See guest/guix/README.md, "Differences from Try Omarchy".

(define omaguix-timezone
  (guest-python-script "omaguix-timezone" "timezone"
                       (local-file "timezone")
                       #:synopsis "Follow the Mac's time zone"))

(define (timezone-shepherd-service _)
  (list (shepherd-service
         (provision '(omaguix-timezone))
         ;; The settings file is applied before following resumes from it.
         (requirement '(udev omaguix-host-settings omaguix-machine-settings))
         (respawn? #t)
         (documentation "Follow the Mac's time zone while chosen.")
         (start #~(lambda _
                    ;; Only a launcher VM has the port; otherwise stay stopped.
                    (and (file-exists? "/dev/virtio-ports/dev.tryomarchy.timezone")
                         (fork+exec-command
                          (list #$(file-append omaguix-timezone
                                               "/bin/omaguix-timezone"))
                          #:log-file "/var/log/omaguix-timezone.log"))))
         (stop #~(make-kill-destructor)))))

(define omaguix-timezone-service-type
  (service-type
   (name 'omaguix-timezone)
   (extensions
    (list (service-extension udev-service-type
                             (const
                              (list (udev-rule
                                     "96-omaguix-timezone.rules"
                                     "SUBSYSTEM==\"virtio-ports\", ATTR{name}==\"dev.tryomarchy.timezone\", OWNER=\"root\", GROUP=\"root\", MODE=\"0600\"\n"))))
          (service-extension shepherd-root-service-type
                             timezone-shepherd-service)
          (service-extension profile-service-type
                             (const (list omaguix-timezone)))))
   (default-value #f)
   (description "Follow the Mac's time zone until a fixed one is chosen.")))

;;; First-start setup: Omarchy's owner setup questions (keyboard, password,
;;; Git identity, host name, time zone) on tty1, suggested by the Mac; it
;;; writes /var/lib/omaguix/machine-settings.scm (see omaguix-setup).

(define omaguix-setup
  (guest-python-script "omaguix-setup" "omaguix-setup"
                       (local-file "omaguix-setup")
                       #:tools '("sbin/chpasswd" "bin/loadkeys" "bin/git"
                                 "bin/hostname")
                       #:inputs (list shadow kbd git inetutils)
                       #:synopsis "Ask Omaguix's first-start questions"))

;;; Settings: Omarchy's Setup menu (omarchy-menu.py) and the desktop entry
;;; ask the Mac app to show its settings with one line on
;;; dev.tryomarchy.settings; the account's group reaches the port.

(define omaguix-settings
  (package
    (name "omaguix-settings")
    (version "1")
    (source (local-file "settings" #:recursive? #t))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(("omaguix-settings" "bin/")
          ("try-omaguix-settings.desktop" "share/applications/"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap
            (lambda* (#:key inputs #:allow-other-keys)
              (let ((program (string-append #$output "/bin/omaguix-settings")))
                (chmod program #o555)
                (wrap-program program
                  `("PATH" ":" prefix
                    (,(dirname (search-input-file inputs "bin/notify-send")))))))))))
    (inputs (list bash-minimal python-minimal libnotify))
    (home-page "https://github.com/omacom/try-omarchy")
    (synopsis "Open the Try Omaguix Mac app settings from the guest")
    (description "Ask the Mac app over dev.tryomarchy.settings to show its
settings window.")
    (license license:expat)))

(define omaguix-settings-service-type
  (service-type
   (name 'omaguix-settings)
   (extensions
    (list (service-extension udev-service-type
                             (const
                              (list (udev-rule
                                     "92-omaguix-settings.rules"
                                     "SUBSYSTEM==\"virtio-ports\", ATTR{name}==\"dev.tryomarchy.settings\", GROUP=\"users\", MODE=\"0660\"\n"))))
          (service-extension profile-service-type
                             (const (list omaguix-settings)))))
   (default-value #f)
   (description "Open the Mac app's settings from Omarchy's Setup menu.")))

;;; Touch ID for sudo: the Arch guest's broker (byte-identical copy; only its
;;; two /usr/bin OpenSSL references are pointed at the store below) asks the
;;; host over the root-only dev.tryomarchy.authentication port and verifies
;;; the Secure Enclave signature with OpenSSL.
;;;
;;; The Arch guest edits /etc/pam.d/sudo when the owner opts in. Guix generates
;;; /etc/pam.d, so sudo always carries one `sufficient' pam_exec rule, and its
;;; gate fails at once unless omaguix-touch-id-control has enrolled with the
;;; host and written %touch-id-marker. Until then the rule changes nothing;
;;; afterwards any failure still falls back to the password. Enrollment comes
;;; before the marker and disabling removes the marker first, as in the Arch
;;; control script.

(define %touch-id-marker "/var/lib/omaguix/touch-id-enabled")

(define omaguix-touch-id
  (package
    (name "omaguix-touch-id")
    (version "1")
    (source (local-file "authentication-broker"))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(("authentication-broker" "libexec/omaguix/authentication-broker"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'use-store-openssl
            (lambda* (#:key inputs #:allow-other-keys)
              (let ((openssl (search-input-file inputs "bin/openssl")))
                (substitute* "authentication-broker"
                  (("Path\\(\"/usr/bin/openssl\"\\)")
                   (string-append "Path(\"" openssl "\")"))
                  (("\\{\"PATH\": \"/usr/bin\"\\}")
                   (string-append "{\"PATH\": \"" (dirname openssl) "\"}"))))))
          (add-after 'install 'install-commands
            (lambda _
              (let* ((broker (string-append
                              #$output "/libexec/omaguix/authentication-broker"))
                     (sh #$(file-append bash-minimal "/bin/sh"))
                     (sudo "/run/privileged/bin/sudo")
                     (gate (string-append #$output "/libexec/omaguix/touch-id-gate"))
                     (control (string-append #$output "/sbin/omaguix-touch-id-control"))
                     (user (string-append #$output "/bin/omaguix-touch-id")))
                (define (script file text)
                  (mkdir-p (dirname file))
                  (call-with-output-file file
                    (lambda (port) (format port "#!~a~%~a" sh text)))
                  (chmod file #o555))
                (chmod broker #o555)
                (script gate (string-append "\
# pam_exec gate for sudo: inert until Touch ID was enabled.
[ -f " #$%touch-id-marker " ] || exit 1
exec " broker " pam
"))
                (script control (string-append "\
set -eu
marker=" #$%touch-id-marker "
[ \"$(id -u)\" = 0 ] || { echo 'omaguix-touch-id-control: run as root' >&2; exit 1; }
case \"${1:-}\" in
  enable)
    " broker " enroll
    mkdir -p -m 0700 \"$(dirname \"$marker\")\"
    : > \"$marker\"
    chmod 0600 \"$marker\"
    echo 'Touch ID is enabled for sudo. The guest password remains available as fallback.' ;;
  disable)
    rm -f \"$marker\"
    " broker " disable
    echo 'Touch ID is disabled for sudo.' ;;
  repair)
    \"$0\" disable
    \"$0\" enable ;;
  *)
    echo 'Usage: omaguix-touch-id-control enable|disable|repair' >&2
    exit 64 ;;
esac
"))
                (script user (string-append "\
# Enable or disable Touch ID for sudo; sudo asks for the password once.
exec " sudo " " control " \"$@\"
"))))))))
    (inputs (list bash-minimal openssl python-minimal))
    (home-page "https://github.com/omacom/try-omarchy")
    (synopsis "Approve sudo with the Mac's Touch ID")
    (description "Ask the Mac to approve sudo with Touch ID, verifying its
Secure Enclave signature, with the password as fallback.")
    (license license:expat)))

(define touch-id-gate
  (file-append omaguix-touch-id "/libexec/omaguix/touch-id-gate"))

(define (touch-id-pam-extension _)
  (list (pam-extension
         (transformer
          (lambda (service)
            (if (string=? (pam-service-name service) "sudo")
                (pam-service
                 (inherit service)
                 (auth (cons (pam-entry
                              (control "sufficient")
                              (module (file-append linux-pam
                                                   "/lib/security/pam_exec.so"))
                              (arguments (list "quiet" "seteuid" "stdout"
                                               touch-id-gate)))
                             (pam-service-auth service))))
                service))))))

(define omaguix-touch-id-service-type
  (service-type
   (name 'omaguix-touch-id)
   (extensions
    (list (service-extension pam-root-service-type touch-id-pam-extension)
          (service-extension udev-service-type
                             (const
                              (list (udev-rule
                                     "93-omaguix-authentication.rules"
                                     "SUBSYSTEM==\"virtio-ports\", ATTR{name}==\"dev.tryomarchy.authentication\", OWNER=\"root\", GROUP=\"root\", MODE=\"0600\"\n"))))
          (service-extension profile-service-type
                             (const (list omaguix-touch-id)))))
   (default-value #f)
   (description "Offer Touch ID approval for sudo, inert until enabled.")))
