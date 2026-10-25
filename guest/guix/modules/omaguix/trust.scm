;;; Omaguix — what an Omaguix VM trusts beyond Guix's own servers and channel.
;;;
;;; Omaguix's substitute server and its signed channel are the two places a
;;; VM takes code from on Omaguix's word; both are named here and only here.

(define-module (omaguix trust)
  #:use-module (guix gexp)
  #:use-module (srfi srfi-9)
  #:export (%omaguix-trust
            omaguix-trust?
            omaguix-trust-substitute-url
            omaguix-trust-substitute-key
            omaguix-trust-channel-url
            omaguix-trust-channel-introduction
            omaguix-trust-channel-signer))

(define-record-type <omaguix-trust>
  (omaguix-trust substitute-url substitute-key
                channel-url channel-introduction channel-signer)
  omaguix-trust?
  (substitute-url omaguix-trust-substitute-url)
  (substitute-key omaguix-trust-substitute-key)
  (channel-url omaguix-trust-channel-url)
  (channel-introduction omaguix-trust-channel-introduction)
  (channel-signer omaguix-trust-channel-signer))

(define %omaguix-trust
  (omaguix-trust
   ;; Static substitutes signed in omaguix/omaguix's CI with this key and
   ;; served from the VPS (docs/decisions/0008-static-substitutes-at-omaguix-org.md).
   "https://substitutes.omaguix.org"
   (local-file "substitutes.omaguix.org.pub")
   ;; Omaguix's modules, published from try-omaguix (guest/guix/publish-channel)
   ;; and signed with the channel key; Guix's channel introduction model
   ;; authenticates each commit from the first
   ;; (docs/decisions/0004-roguix-channel.md).
   "https://github.com/omaguix/omaguix-channel"
   "bcc938512706d19de86dd8c6f50853fa80b063b8"
   "7D1A 8B40 0C26 0998 097F  63E5 28B8 3B16 11FA 815E"))
