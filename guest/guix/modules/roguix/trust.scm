;;; Roguix — what a Roguix VM trusts beyond Guix's own servers and channel.
;;;
;;; Roguix's substitute server and its signed channel are the two places a
;;; VM takes code from on Roguix's word; both are named here and only here.

(define-module (roguix trust)
  #:use-module (guix gexp)
  #:use-module (srfi srfi-9)
  #:export (%roguix-trust
            roguix-trust?
            roguix-trust-substitute-url
            roguix-trust-substitute-key
            roguix-trust-channel-url
            roguix-trust-channel-introduction
            roguix-trust-channel-signer))

(define-record-type <roguix-trust>
  (roguix-trust substitute-url substitute-key
                channel-url channel-introduction channel-signer)
  roguix-trust?
  (substitute-url roguix-trust-substitute-url)
  (substitute-key roguix-trust-substitute-key)
  (channel-url roguix-trust-channel-url)
  (channel-introduction roguix-trust-channel-introduction)
  (channel-signer roguix-trust-channel-signer))

(define %roguix-trust
  (roguix-trust
   ;; guix publish on the author's server, signed with this key
   ;; (docs/decisions/0002-roguix-substitute-server.md).
   "https://roguix.frolow.dev"
   (local-file "roguix.frolow.dev.pub")
   ;; Roguix's modules, published from try-roguix (guest/guix/publish-channel)
   ;; and signed with the channel key; Guix's channel introduction model
   ;; authenticates each commit from the first
   ;; (docs/decisions/0004-roguix-channel.md).
   "https://github.com/omaguix/omaguix-channel"
   "bcc938512706d19de86dd8c6f50853fa80b063b8"
   "7D1A 8B40 0C26 0998 097F  63E5 28B8 3B16 11FA 815E"))
