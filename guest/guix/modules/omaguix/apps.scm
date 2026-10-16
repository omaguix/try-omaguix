;;; Omaguix — Omarchy applications the pinned Guix does not package.
;;;
;;; These install the upstream projects' own aarch64 and x86_64 release
;;; binaries instead of building from source
;;; (docs/decisions/0003-upstream-binary-packages.md). Each source is pinned by
;;; its SHA-256; the builder signs the result and roguix.frolow.dev serves it
;;; like any other Omaguix item.
(define-module (omaguix apps)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (ice-9 match)
  #:use-module (guix build-system copy)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages fcitx5)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages qt)
  #:use-module (gnu packages video)
  #:use-module (gnu packages virtualization)
  #:export (lazygit-bin
            lazydocker-bin
            gum-bin
            dua-bin
            cliamp-bin
            codex-bin
            fastfetch-without-zfs
            obs-without-vlc
            fcitx5-qt6))

;; The upstream release for the system a package is built for, from RELEASES:
;; a list of (SYSTEM URL BASE32-HASH . REST), one per supported system.
;; Called from thunked fields such as `arguments', which see the system
;; `guix build --system' or a cross-compilation target asks for; `source' is
;; evaluated once, when the module loads, so these packages have none and
;; fetch the release in their 'unpack phase.
(define (system-release releases)
  (let ((system (cond ((target-aarch64?) "aarch64-linux")
                      ((target-x86-64?) "x86_64-linux")
                      (else (%current-system)))))
    (match (assoc system releases)
      ((_ url hash . rest)
       (cons (origin
               (method url-fetch)
               (uri url)
               (sha256 (base32 hash)))
             rest)))))

;; A statically linked upstream release: unpack the tarball into the build
;; directory and install its PLAN (copy-build-system's #:install-plan).
;; RELEASES lists (SYSTEM URL BASE32-HASH PLAN) for each supported system.
(define* (static-binary-package name version releases
                                #:key home-page synopsis description
                                (license license:expat))
  (package
    (name name)
    (version version)
    (source #f)
    (build-system copy-build-system)
    (arguments
     (match (system-release releases)
       ((tarball plan)
        (list
         ;; Upstream strips its release binaries.
         #:strip-binaries? #f
         #:install-plan plan
         #:phases
         #~(modify-phases %standard-phases
             ;; Some tarballs have no top-level directory.
             (replace 'unpack
               (lambda _
                 (invoke "tar" "xzf" #$tarball))))))))
    (supported-systems (map car releases))
    (home-page home-page)
    (synopsis synopsis)
    (description description)
    (license license)))

(define lazygit-bin
  (static-binary-package
   "lazygit" "0.65.1"
   (list
    (list "aarch64-linux"
          "https://github.com/jesseduffield/lazygit/releases/download/v0.65.1/lazygit_0.65.1_linux_arm64.tar.gz"
          "19q0830gd1vd3jfq1v8j6r9flrx2mnzvkxqvn7yjskyzdbgyras9"
          #~'(("lazygit" "bin/")))
    (list "x86_64-linux"
          "https://github.com/jesseduffield/lazygit/releases/download/v0.65.1/lazygit_0.65.1_linux_x86_64.tar.gz"
          "19h1q8lj7q4hyzay2a7vycx3a1vk2jl0nj731bjl58qgvayargh2"
          #~'(("lazygit" "bin/"))))
   #:home-page "https://github.com/jesseduffield/lazygit"
   #:synopsis "Terminal UI for Git"
   #:description "Lazygit is a terminal user interface for Git commands."))

(define lazydocker-bin
  (static-binary-package
   "lazydocker" "0.25.2"
   (list
    (list "aarch64-linux"
          "https://github.com/jesseduffield/lazydocker/releases/download/v0.25.2/lazydocker_0.25.2_Linux_arm64.tar.gz"
          "08yy63sydvj934p6m37dxr0460mmmlykmn26svkmg9dahnv3hp00"
          #~'(("lazydocker" "bin/")))
    (list "x86_64-linux"
          "https://github.com/jesseduffield/lazydocker/releases/download/v0.25.2/lazydocker_0.25.2_Linux_x86_64.tar.gz"
          "0g2jp4wzn1jk8qszs2iwfg7y7imdiis09cc4xpkiick8c31bz78d"
          #~'(("lazydocker" "bin/"))))
   #:home-page "https://github.com/jesseduffield/lazydocker"
   #:synopsis "Terminal UI for Docker"
   #:description "Lazydocker is a terminal user interface for Docker and
Docker Compose."))

(define gum-bin
  (static-binary-package
   "gum" "2.0.2"
   (list
    (list "aarch64-linux"
          "https://github.com/charmbracelet/gum/releases/download/v2.0.2/gum_2.0.2_Linux_arm64.tar.gz"
          "1md1rw60xf2pyc65ydqi9mm1i609nzwrzdaqpgr8330yxia8pgwf"
          #~'(("gum_2.0.2_Linux_arm64/gum" "bin/")
              ("gum_2.0.2_Linux_arm64/manpages/gum.1.gz" "share/man/man1/")))
    (list "x86_64-linux"
          "https://github.com/charmbracelet/gum/releases/download/v2.0.2/gum_2.0.2_Linux_x86_64.tar.gz"
          "1hpd14qpbg3vndmk8h7w67ij4vyvk03d33fb92pr1vfvjdny0hnq"
          #~'(("gum_2.0.2_Linux_x86_64/gum" "bin/")
              ("gum_2.0.2_Linux_x86_64/manpages/gum.1.gz" "share/man/man1/"))))
   #:home-page "https://github.com/charmbracelet/gum"
   #:synopsis "Interactive prompts for shell scripts"
   #:description "Gum provides inputs, choosers, spinners and styled text for
shell scripts; Omarchy's menus and installers use it."))

(define dua-bin
  (static-binary-package
   "dua" "2.45.0"
   (list
    (list "aarch64-linux"
          "https://github.com/Byron/dua-cli/releases/download/v2.45.0/dua-v2.45.0-aarch64-unknown-linux-musl.tar.gz"
          "0nkqmnv79hs3b9bm8ixyhq1y2gzb8pid7hnarhpdmijjdds0xj9s"
          #~'(("dua-v2.45.0-aarch64-unknown-linux-musl/dua" "bin/")))
    (list "x86_64-linux"
          "https://github.com/Byron/dua-cli/releases/download/v2.45.0/dua-v2.45.0-x86_64-unknown-linux-musl.tar.gz"
          "1kg4h6i9mv9fxdx71cziyxnjvwk1dxwy7flinw6jdcnapgsp5ffh"
          #~'(("dua-v2.45.0-x86_64-unknown-linux-musl/dua" "bin/"))))
   #:home-page "https://github.com/Byron/dua-cli"
   #:synopsis "Disk usage analyzer"
   #:description "Dua shows and interactively deletes what uses disk space;
Omarchy's Disk Usage entry runs it."))

;; Codex's update paths cannot touch the read-only store: its updater picks
;; an installer (npm, Homebrew, its install script) from where the binary
;; lives, and a store path matches none, so `codex update' only prints a link
;; to update by hand. bin/codex also turns off the startup check for a newer
;; release with the documented key check_for_update_on_startup
;; (codex-rs/tui/src/updates.rs, rust-v0.163.0). It is a command-line
;; override, which beats ~/.codex/config.toml; a later `-c' of the user's own
;; or /etc/codex/managed_config.toml still wins. `codex app-server daemon
;; update' installs a separate Codex under ~/.codex/packages, outside Guix.
;; The Linux sandbox runs the first `bwrap' on PATH, so bin/codex puts Guix's
;; bubblewrap first; upstream's own bwrap is only a fallback beside the binary
;; and is left out.
(define codex-bin
  (let ((base
         (static-binary-package
          "codex" "0.163.0"
          (list
           (list "aarch64-linux"
                 "https://github.com/openai/codex/releases/download/rust-v0.163.0/codex-aarch64-unknown-linux-musl.tar.gz"
                 "1r7z3x3akzffi83lh7ilzkg36b6wy9n9q1jslr68yvd9yijiw9m7"
                 #~'(("codex-aarch64-unknown-linux-musl" "libexec/codex")))
           (list "x86_64-linux"
                 "https://github.com/openai/codex/releases/download/rust-v0.163.0/codex-x86_64-unknown-linux-musl.tar.gz"
                 "1r6x91v7j658dh2wa3xzvwp82x54ijnq3p5jddx0bfnrxkl3kcxy"
                 #~'(("codex-x86_64-unknown-linux-musl" "libexec/codex"))))
          #:home-page "https://github.com/openai/codex"
          #:synopsis "OpenAI's coding agent for the terminal (upstream binary)"
          #:description "Codex CLI is OpenAI's coding agent that runs in the
terminal.  This package installs upstream's prebuilt static release binary; it
is not built from source.  Its startup check for updates is turned off and
@command{codex update} cannot replace it: update it with Guix.  Its sandbox
uses Guix's bubblewrap."
          #:license license:asl2.0)))
    (package
      (inherit base)
      (arguments
       (substitute-keyword-arguments (package-arguments base)
         ((#:phases phases)
          #~(modify-phases #$phases
              (add-after 'install 'wrap
                (lambda* (#:key inputs #:allow-other-keys)
                  (let ((wrapper (string-append #$output "/bin/codex")))
                    (mkdir-p (dirname wrapper))
                    (call-with-output-file wrapper
                      (lambda (port)
                        (format port "#!~a
export PATH=\"~a${PATH:+:$PATH}\"
exec ~a -c check_for_update_on_startup=false \"$@\"~%"
                                (search-input-file inputs "bin/sh")
                                (dirname (search-input-file inputs "bin/bwrap"))
                                (string-append #$output "/libexec/codex"))))
                    (chmod wrapper #o555))))
              ;; Runs the binary, so not when cross-compiling.
              (add-after 'wrap 'check
                (lambda* (#:key tests? #:allow-other-keys)
                  (when (and tests? (not #$(%current-target-system)))
                    (invoke (string-append #$output "/bin/codex")
                            "--version"))))))))
      (inputs (modify-inputs (package-inputs base)
                (append bash-minimal bubblewrap))))))

;; cliamp's release binary links glibc and ALSA dynamically. patchelf breaks
;; this Go binary (the loader segfaults), so bin/cliamp runs the untouched
;; binary through the store's loader with an explicit library path.
(define %cliamp-releases
  ;; (SYSTEM URL BASE32-HASH LOADER), LOADER being glibc's dynamic loader.
  '(("aarch64-linux"
     "https://github.com/bjarneo/cliamp/releases/download/v2.2.0/cliamp-linux-arm64"
     "1d582541z4gar74h34dhghc70nwj881157277hln5dz4mpskkbll"
     "lib/ld-linux-aarch64.so.1")
    ("x86_64-linux"
     "https://github.com/bjarneo/cliamp/releases/download/v2.2.0/cliamp-linux-amd64"
     "10nqc0zmgdws8fsifbkibsssq5ln85zci9lqm2zhz4kx6rg37zb0"
     "lib/ld-linux-x86-64.so.2")))

(define cliamp-bin
  (package
    (name "cliamp")
    (version "2.2.0")
    (source #f)
    (build-system copy-build-system)
    (arguments
     (match (system-release %cliamp-releases)
       ((binary loader)
        (list
         #:strip-binaries? #f
         ;; Guile's ELF parser rejects this Go binary, and it has no RUNPATH.
         #:validate-runpath? #f
         #:install-plan #~'(("cliamp" "libexec/"))
         #:phases
         #~(modify-phases %standard-phases
             (replace 'unpack
               (lambda _
                 (copy-file #$binary "cliamp")
                 (chmod "cliamp" #o555)))
             (add-after 'install 'wrap
               (lambda* (#:key inputs #:allow-other-keys)
                 (let ((loader (search-input-file inputs #$loader))
                       (libraries
                        (string-append
                         (dirname (search-input-file inputs "lib/libasound.so.2"))
                         ":"
                         (dirname (search-input-file inputs "lib/libc.so.6"))))
                       (wrapper (string-append #$output "/bin/cliamp")))
                   (mkdir-p (dirname wrapper))
                   (call-with-output-file wrapper
                     (lambda (port)
                       (format port "#!~a~%exec ~a --library-path ~a ~a \"$@\"~%"
                               (search-input-file inputs "bin/sh")
                               loader libraries
                               (string-append #$output "/libexec/cliamp"))))
                   (chmod wrapper #o555)
                   (invoke wrapper "--help")))))))))
    (inputs (list alsa-lib bash-minimal glibc))
    (supported-systems (map car %cliamp-releases))
    (home-page "https://github.com/bjarneo/cliamp")
    (synopsis "Terminal music player")
    (description "Cliamp is a terminal music player inspired by Winamp;
Omarchy binds it to Super+Shift+Alt+M.")
    (license license:expat)))

;; Guix's fastfetch links ZFS for pool details, which an Omaguix VM has none of.
;; ZFS brings a kernel module build and, through Guix's grafts, a slow first
;; omaguix-update.
(define fastfetch-without-zfs
  (package
    (inherit fastfetch)
    (arguments
     (substitute-keyword-arguments (package-arguments fastfetch)
       ;; Guix links fastfetch's optional libraries directly.
       ((#:configure-flags flags #~'())
        #~(cons "-DENABLE_LIBZFS=OFF" #$flags))))
    (inputs (modify-inputs (package-inputs fastfetch)
              (delete "zfs")))))

;; Qt 5 reaches the system only through VLC 3 (OBS's optional VLC video
;; source) and fcitx5-qt's Qt 5 input-method plugin. Omarchy's applications
;; are Qt 6 or GTK, so both go and with them the whole Qt 5 stack.
(define obs-without-vlc
  (package
    (inherit obs)
    (arguments
     ;; The point of the variant: the build fails if VLC or Qt 5 remain.
     (cons* #:disallowed-references (list vlc qtbase-5)
     (substitute-keyword-arguments (package-arguments obs)
       ((#:configure-flags flags #~'())
        #~(cons "-DENABLE_VLC=OFF" #$flags))
       ((#:phases phases)
        #~(modify-phases #$phases
            (replace 'wrap-executable
              (lambda _
                (wrap-program (string-append #$output "/bin/obs")
                  `("QT_PLUGIN_PATH" ":" prefix (,(getenv "QT_PLUGIN_PATH")))
                  ;; Guix's OBS needs Mesa's libraries until Mesa has glvnd.
                  `("LD_LIBRARY_PATH" ":" prefix
                    (,(string-append #$(this-package-input "mesa") "/lib")))))))))))
    (inputs (modify-inputs (package-inputs obs)
              (delete "vlc")))))

(define fcitx5-qt6
  (package
    (inherit fcitx5-qt)
    (arguments
     ;; The point of the variant: the build fails if Qt 5 remains.
     (cons* #:disallowed-references (list qtbase-5)
     (substitute-keyword-arguments (package-arguments fcitx5-qt)
       ((#:configure-flags flags #~'())
        #~(cons "-DENABLE_QT5=Off" #$flags))
       ;; The only upstream test covers the Qt 5 library's key translation,
       ;; which the Qt 6 build does not have; ctest would find no tests.
       ((#:tests? _ #t) #f))))
    (inputs (modify-inputs (package-inputs fcitx5-qt)
              ;; qtbase-5 and qtbase (6) share the label "qtbase".
              (delete "qtbase")
              (prepend qtbase)))))
