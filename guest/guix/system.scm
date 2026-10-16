;; The Omaguix image: the base system with no extra packages. In the guest,
;; /etc/config.scm calls the same procedure with the owner's packages.
(use-modules (omaguix system))

(omaguix-operating-system)
