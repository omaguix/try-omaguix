;;; Omaguix — a macOS-style Xcursor theme.
;;;
;;; ful1e5/apple_cursor commits only SVG sources; its own build renders them
;;; with cbmp (Node and a headless browser), recolouring them as render.json
;;; says, and then runs clickgen's ctgen. clickgen needs numpy, whose x86_64
;;; substitutes require x86-64-v2 and crash on older CPUs such as the Core 2
;;; Duo, so xcursor-theme.py does ctgen's work instead from the same config:
;;; rsvg-convert renders each SVG at every cursor size and xcursorgen packs
;;; them. Only the black "macOS" variant is built; its theme directory keeps
;;; upstream's name.
(define-module (omaguix cursors)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix build-system trivial)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages python)
  #:use-module (gnu packages xorg)
  #:export (macos-style-cursor-theme))

(define macos-style-cursor-theme
  (package
    (name "macos-style-cursor-theme")
    (version "2.0.1")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/ful1e5/apple_cursor")
                    (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0nlh1zfdz6gm16nm47xm3qgzv6z7yskva3zhzyp36yf5sjd6wrw1"))))
    (build-system trivial-build-system)
    (native-inputs (list librsvg python xcursorgen))
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((doc (string-append #$output "/share/doc/" #$name "-"
                                    #$version)))
            ;; render.json's "macOS" colours: #00FF00 is the fill, #0000FF
            ;; the outline.
            (invoke (search-input-file %build-inputs "/bin/python3")
                    #$(local-file "xcursor-theme.py")
                    (search-input-file %build-inputs "/bin/rsvg-convert")
                    (search-input-file %build-inputs "/bin/xcursorgen")
                    (string-append #$source "/configs/x.build.toml")
                    (string-append #$source "/svg")
                    (string-append #$output "/share/icons/macOS")
                    "macOS" "macOS-style cursors"
                    "#00FF00=#000000" "#0000FF=#FFFFFF")
            (install-file (string-append #$source "/LICENSE") doc)))))
    (home-page "https://github.com/ful1e5/apple_cursor")
    (synopsis "macOS-style cursor theme")
    (description
     "This package provides the black variant of the apple_cursor project, an
open-source X11 cursor theme drawn in the style of the macOS pointers, installed
as the @code{macOS} cursor theme.  It is not affiliated with or endorsed by
Apple.")
    (license license:gpl3)))
