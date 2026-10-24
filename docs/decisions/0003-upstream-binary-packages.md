# Upstream release binaries for Omarchy apps Guix lacks

## Context

Omarchy's default applications include lazygit, lazydocker, gum, dua and
cliamp, which the pinned Guix does not package. Packaging them from source
means Go and Rust dependency trees of hundreds of modules each, to maintain
on every update. Each project publishes aarch64 and x86_64 Linux release
binaries.

## Decision

`guest/guix/modules/omaguix/apps.scm` installs those release binaries, each
pinned by URL and SHA-256. Four are statically linked. cliamp links glibc and
ALSA dynamically; patchelf breaks this Go binary, so `bin/cliamp` runs the
untouched binary through the store's loader with an explicit library path.
The builder builds them and `roguix.frolow.dev` serves them like Omaguix's
other packages (decision 0002). The channel also offers OpenAI's Codex CLI
(`codex-bin`, Apache-2.0) the same way, not installed by default. Its
`bin/codex` puts Guix's bubblewrap first on PATH for Codex's sandbox and turns
off Codex's startup update check with a command-line override, which
`~/.codex/config.toml` cannot undo but a later `-c` of the user's can;
`codex update` cannot replace a store path and only says to update by hand.

Exception, decided with TODO item t-dopemmpz (2026-10-16): the channel also
offers `x86-64-v2-sigill-shim` (GPL-3.0-or-later), built from source with its
tests and ordinary substitutes, and `claude-code-x86-64-v1`, Anthropic's
non-free npm binary for x86_64 run through that shim so it also works on
x86-64-v1 CPUs. The Claude Code package is labelled experimental and
unsupported, has no substitutes (`#:substitutable? #f`), and is not in the
reference system, so CI publishes nothing for it. This is the only non-free
package; Obsidian and the rest below stay out.

Not provided: Pinta (.NET), LocalSend (Flutter), Signal and Obsidian
(Electron, Obsidian non-free), and LibreOffice, which Guix packages but has
no aarch64 substitutes for (hours to build).

## Alternatives

- Building from source in the omaguix modules: the Guix way, but each needs
  its whole dependency graph packaged first.
- Leaving them out: Omarchy's Disk Usage and Docker entries, its music key
  binding and scripts using gum would not work.

## Consequences

- Guests run code built by the upstream projects' CI, not by Guix, and
  signed by the Omaguix server key; the SHA-256 pins make any change visible.
- Updating one is a version change and a URL and hash per system in
  `apps.scm`.
- The packages support `aarch64-linux` and `x86_64-linux`, one upstream
  release each; they have no `source`, since the release depends on the
  system the package is built for, which only thunked fields see. The
  x86-64-v1 pair ships one release for its only system and pins an ordinary
  `source` each.
