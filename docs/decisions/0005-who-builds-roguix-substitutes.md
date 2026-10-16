# Who builds and serves Omaguix's substitutes

Supersedes [0002](0002-roguix-substitute-server.md) on who builds the
substitutes and where the server is defined; 0002's reasons for an Omaguix
substitute server, and its alternatives, still hold.

## Context

Decision 0002 made the aarch64 builder VM on the maintainer's Mac the only
builder: it exported Omaguix's store items and the VPS behind
`roguix.frolow.dev` imported and served them, with the VPS's setup (Debian 13,
`guix-install.sh`, a systemd unit and an nginx site) kept in `server/`.

Since then substitutes are also built by the `omaguix/omaguix` repository's CI
on GitHub runners, for aarch64 and x86_64, from
`(@ (omaguix system) %omaguix-reference-system)` (`guest/guix/README.md`),
whose derivation is the same on any machine. The VPS is moving to a Guix
System configuration kept in its own repository, which then defines
`guix publish` and its site. Keeping a second description of the server here
means a change to its limits must be made twice, and a public repository
describes a private host.

## Decision

- Builders: `omaguix/omaguix`'s CI builds the reference system for both
  architectures; the builder VM (`guest/guix/builder-vm`) still builds the
  image and can build and export the same items when CI cannot.
- Server: `roguix.frolow.dev` keeps serving signed substitutes with one key.
  Its host configuration belongs to the VPS's own repository.
- try-omaguix keeps only the client side: the substitute URL and public key
  in `%omaguix-trust` (`guest/guix/modules/omaguix/trust.scm`), together with
  the channel it trusts (decision 0004).
- `server/` stays until the VPS runs from its Guix System configuration;
  then it is deleted and this record's links to it go with it.

## Alternatives

- Keeping 0002 and `server/` as they are: wrong about who builds, and two
  definitions of one server.
- Moving the server's configuration into this repository for good: ties the
  Mac app's repository to the maintainer's host, which also serves other
  sites.

## Consequences

- A Guix pin moves once CI (or the builder VM) has built that pin's Omaguix
  packages and they are on the server.
- Changes to `guix publish`'s limits or the site are made in the VPS's
  repository, not here, once the migration is done.
- The trust in the server's key, and the plan to move signing off the VPS
  ([docs/omaguix-signing-keys.md](../omaguix-signing-keys.md)), are unchanged.
