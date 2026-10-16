#!/usr/bin/env python3
"""Read and validate the app identity file the build selects (APP_IDENTITY).

An identity file (macos/apps/try-omaguix.env) holds plain KEY=value lines and
full-line # comments. The Makefile includes the same file, so the grammar is
the subset Make, bash (through `shell`) and Python read identically: no
quotes, `$`, `#`, backslashes or surrounding whitespace in a value.

  identity.py check   validate the selected file; errors go to stderr
  identity.py shell   print the values as bash assignments, for eval
  identity.py keys    print the key names, for the Makefile's override guard
  identity.py icon    print the icon's path (ICON, beside the identity file)
"""

import os
from pathlib import Path
import re
import shlex
import sys

DEFAULT = Path(__file__).resolve().parent / "try-omaguix.env"

NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9 ._-]*")
BUNDLE = re.compile(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+")
# Each key's pattern; names that become a path component exclude "/".
KEYS = {
    "APP_NAME": NAME,
    "DEVELOPMENT_APP_NAME": NAME,
    "BUNDLE_IDENTIFIER": BUNDLE,
    "DEVELOPMENT_BUNDLE_IDENTIFIER": BUNDLE,
    "APPLICATION_SUPPORT_DIRECTORY": NAME,
    "LOGS_DIRECTORY": NAME,
    # Older names of the same app whose copies use the same VM; may be empty.
    "LEGACY_APP_NAMES": re.compile(r"(|[A-Za-z0-9][A-Za-z0-9 ._-]*(,[A-Za-z0-9][A-Za-z0-9 ._-]*)*)"),
    "DEVELOPMENT_CERTIFICATE": NAME,
    "DEVELOPMENT_KEYCHAIN": re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*\.keychain-db"),
    # Relative to ~/.config.
    "DEVELOPMENT_KEYCHAIN_PASSWORD": re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*"),
    "RELEASE_TAG_PREFIX": re.compile(r"[a-z0-9][a-z0-9._-]*-v"),
    "RELEASE_DMG": re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*\.dmg"),
    "RELEASE_REPOSITORY": re.compile(r"[A-Za-z0-9-]+/[A-Za-z0-9._-]+"),
    # The app icon's SVG source, in the identity file's directory.
    "ICON": re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]*\.svg"),
    # The bridged-networking helper's launchd service; empty for an app
    # that ships no helper and offers only NAT.
    "NETWORK_HELPER_SERVICE": re.compile(r"(|[A-Za-z0-9]+(\.[A-Za-z0-9-]+)+)"),
}


class IdentityError(ValueError):
    pass


def selected():
    """The file APP_IDENTITY names; the default only when it is unset, as in
    the Makefile, which refuses an empty value."""
    if "APP_IDENTITY" not in os.environ:
        return DEFAULT
    if not os.environ["APP_IDENTITY"]:
        raise IdentityError("APP_IDENTITY is empty; unset it or name an identity file")
    return Path(os.environ["APP_IDENTITY"])


def load(path=None):
    path = Path(path) if path is not None else selected()
    values = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        where = f"{path}:{number}"
        if line.startswith("#") and line.endswith("\\"):
            # Make would continue the comment into the next line.
            raise IdentityError(f"{where}: a comment ends in a backslash")
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or key not in KEYS:
            raise IdentityError(f"{where}: expected one of the identity keys as KEY=value")
        if key in values:
            raise IdentityError(f"{where}: {key} is set twice")
        if KEYS[key].fullmatch(value) is None or value != value.strip() \
                or ".." in value:
            raise IdentityError(f"{where}: {key} has an unsupported value {value!r}")
        values[key] = value
    missing = sorted(set(KEYS) - set(values))
    if missing:
        raise IdentityError(f"{path}: missing {', '.join(missing)}")
    if values["BUNDLE_IDENTIFIER"] == values["DEVELOPMENT_BUNDLE_IDENTIFIER"] or \
            values["APP_NAME"] == values["DEVELOPMENT_APP_NAME"]:
        raise IdentityError(f"{path}: development and production must differ")
    return values


def icon(values, path=None):
    """The icon's SVG source, which lives beside the selected identity file."""
    path = Path(path) if path is not None else selected()
    return path.resolve().parent / values["ICON"]


def main(argv):
    if argv == ["keys"]:
        print(" ".join(KEYS))
        return
    try:
        values = load()
    except (OSError, IdentityError) as error:
        sys.exit(f"app-identity: {error}")
    if argv == ["check"]:
        return
    if argv == ["icon"]:
        print(icon(values))
        return
    if argv == ["shell"]:
        for key, value in values.items():
            print(f"{key}={shlex.quote(value)}")
        return
    sys.exit("usage: identity.py check | shell | keys | icon")


if __name__ == "__main__":
    main(sys.argv[1:])
