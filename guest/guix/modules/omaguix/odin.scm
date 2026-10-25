;;; Omaguix — the Odin compiler, which the pinned Guix does not package.
;;;
;;; Built from source against the pinned Guix's LLVM 22, the newest major
;;; Odin's build_odin.sh supports. `odin check' and `odin test' work out of the
;;; box: the compiler finds its `base' and `core' collections next to its own
;;; executable, and links through clang-toolchain, whose clang, ld and libc its
;;; wrapper puts first on PATH. The `vendor' collection is empty.
(define-module (omaguix odin)
  #:use-module (guix packages)
  #:use-module (guix git-download)
  #:use-module (guix gexp)
  #:use-module ((guix utils) #:select (target-x86-64?))
  #:use-module (guix build-system gnu)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module ((gnu packages base) #:select (which))
  #:use-module ((gnu packages bash) #:select (bash-minimal))
  #:use-module ((gnu packages llvm) #:select (clang-toolchain-22 llvm-22))
  #:export (odin))

(define odin
  (package
    (name "odin")
    (version "2026-10")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/odin-lang/Odin")
             (commit (string-append "dev-" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "02f292znmyvbw0c6fihdllgp8amqv1v78k8xa739qprm62i1j5l6"))
       (modules '((guix build utils)))
       ;; Drop the prebuilt Windows toolchain and the vendor collection:
       ;; bindings to third-party libraries, with their prebuilt binaries and
       ;; bundled sources under other licenses.
       (snippet
        #~(begin
            (delete-file-recursively "bin")
            (delete-file "LLVM-C.dll")
            (delete-file-recursively "vendor")))))
    (build-system gnu-build-system)
    (arguments
     (list
      #:modules `(,@%default-gnu-modules (ice-9 popen) (ice-9 rdelim))
      ;; The compiler lives in share/odin next to its collections (see
      ;; 'install), so strip and check the RUNPATH there.
      #:strip-directories #~(list "share/odin")
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'pin-version
            (lambda _
              ;; Without .git the version is the build's date.
              (substitute* "build_odin.sh"
                (("\\$\\(date \\+\"%Y-%m\"\\)") #$version))))
          (replace 'build
            (lambda _
              (invoke "sh" "build_odin.sh" "release")))
          (delete 'check)
          (replace 'install
            (lambda _
              (let ((root (string-append #$output "/share/odin")))
                (install-file "odin" root)
                (for-each (lambda (collection)
                            (copy-recursively collection
                                              (string-append root "/" collection)))
                          '("base" "core" "shared"))
                ;; The compiler refuses to start without this collection.
                (mkdir-p (string-append root "/vendor"))
                ;; The compiler takes its root from /proc/self/exe, which
                ;; resolves this link to share/odin.
                (mkdir-p (string-append #$output "/bin"))
                (symlink (string-append root "/odin")
                         (string-append #$output "/bin/odin"))
                ;; It links by running `clang' from PATH (or
                ;; ODIN_CLANG_PATH); clang finds ld on PATH too.
                (wrap-program (string-append #$output "/bin/odin")
                  `("PATH" prefix
                    (#$(file-append clang-toolchain-22 "/bin")))))))
          (replace 'validate-runpath
            (lambda args
              (apply (assoc-ref %standard-phases 'validate-runpath)
                     #:elf-directories '("share/odin") args)))
          (add-after 'install 'check-installed
            (lambda* (#:key tests? #:allow-other-keys)
              (when tests?
                (let ((odin (string-append #$output "/bin/odin"))
                      (dir (string-append (getenv "TMPDIR") "/odin-check"))
                      (path (getenv "PATH")))
                  (mkdir-p (string-append dir "/sum"))
                  (call-with-output-file (string-append dir "/sum/sum.odin")
                    (lambda (port)
                      (display "package sum

import \"core:testing\"

add :: proc(a, b: int) -> int { return a + b }

@(test)
adds :: proc(t: ^testing.T) {
  testing.expect_value(t, add(2, 3), 5)
}
" port)))
                  ;; Nothing from the build environment: the wrapper alone
                  ;; must provide the linker.
                  (dynamic-wind
                    (lambda () (setenv "PATH" ""))
                    (lambda ()
                      (with-directory-excursion dir
                        (let* ((port (open-pipe* OPEN_READ odin "version"))
                               (line (read-line port)))
                          (close-pipe port)
                          (unless (string=? line (string-append
                                                  "odin version dev-"
                                                  #$version))
                            (error "unexpected version" line)))
                        (invoke odin "check" "sum" "-no-entry-point")
                        ;; Odin defaults to x86-64-v2 and refuses to run
                        ;; tests on an older CPU, such as a builder without
                        ;; POPCNT; the test names the baseline instead.
                        (apply invoke odin "test" "sum"
                               '#$(if (target-x86-64?)
                                      '("-microarch:x86-64")
                                      '()))))
                    (lambda () (setenv "PATH" path))))))))))
    (native-inputs (list which))
    (inputs (list bash-minimal clang-toolchain-22 llvm-22))
    (supported-systems '("aarch64-linux" "x86_64-linux"))
    (home-page "https://odin-lang.org/")
    (synopsis "Compiler for the Odin programming language")
    (description
     "Odin is a general-purpose, statically typed systems programming
language with manual memory management, designed as an alternative to C.  This
package provides the @command{odin} compiler with its @code{base} and
@code{core} library collections; the @code{vendor} collection of bindings to
third-party libraries is left empty.")
    ;; The compiler and most of the collections are zlib; base/runtime has
    ;; compiler-rt code (Apache 2.0 with the LLVM exception), core/mem/tlsf is
    ;; BSD-3, core/encoding/entity's table is W3C, core/crypto/_fiat is MIT
    ;; (or Apache 2.0, or BSD-1) and parts of core/crypto are public domain.
    (license (list license:zlib license:asl2.0 license:bsd-3 license:w3c
                   license:expat license:public-domain))))
