;;; Roguix — a macOS-style Xcursor theme.
;;;
;;; ful1e5/apple_cursor commits only SVG sources; its own build renders them
;;; with cbmp (Node and a headless browser), recolouring them as render.json
;;; says, and then runs clickgen's ctgen. This package renders the same SVGs
;;; at their native 256x256 with rsvg-convert instead and runs ctgen on the
;;; result, like Guix's bibata-cursor-theme. Only the black "macOS" variant
;;; is built; its theme directory keeps upstream's name.
(define-module (roguix cursors)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix build-system trivial)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages python-xyz)
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
    (native-inputs (list librsvg python-clickgen))
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((rsvg-convert (search-input-file %build-inputs
                                                 "/bin/rsvg-convert"))
                (ctgen (search-input-file %build-inputs "/bin/ctgen"))
                (svgs (find-files (string-append #$source "/svg") "\\.svg$"))
                (doc (string-append #$output "/share/doc/" #$name "-"
                                    #$version)))
            (mkdir-p "bitmaps")
            ;; render.json's "macOS" colours: #00FF00 is the fill, #0000FF
            ;; the outline.
            (for-each
             (lambda (svg)
               (let ((copy (string-append "bitmaps/" (basename svg))))
                 (copy-file svg copy)
                 (make-file-writable copy)
                 (substitute* copy
                   (("#00[Ff][Ff]00") "#000000")
                   (("#0000[Ff][Ff]") "#FFFFFF"))
                 (invoke rsvg-convert "-o"
                         (string-append (string-drop-right copy 4) ".png")
                         copy)))
             svgs)
            (invoke ctgen (string-append #$source "/configs/x.build.toml")
                    "-p" "x11" "-d" "bitmaps" "-n" "macOS"
                    "-c" "macOS-style cursors"
                    "-o" (string-append #$output "/share/icons"))
            (install-file (string-append #$source "/LICENSE") doc)))))
    (home-page "https://github.com/ful1e5/apple_cursor")
    (synopsis "macOS-style cursor theme")
    (description
     "This package provides the black variant of the apple_cursor project, an
open-source X11 cursor theme drawn in the style of the macOS pointers, installed
as the @code{macOS} cursor theme.  It is not affiliated with or endorsed by
Apple.")
    (license license:gpl3)))
