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
  identity.py guest   print package.py's --system, --load-path and
                      --credentials for the guest, shell-quoted
"""

import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

DEFAULT = Path(__file__).resolve().parent / "try-omaguix.env"

NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9 ._-]*")
BUNDLE = re.compile(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+")
DMG = r"[A-Za-z0-9][A-Za-z0-9._-]*\.dmg"
# A path inside the repository that holds the identity file.
REPOSITORY_PATH = re.compile(r"[A-Za-z0-9_-][A-Za-z0-9._-]*(/[A-Za-z0-9_-][A-Za-z0-9._-]*)*")
# Each key's pattern; names that become a path component exclude "/".
KEYS = {
    "APP_NAME": NAME,
    # The guest system's name in the app's messages ("Reset NAME").
    "GUEST_NAME": NAME,
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
    "RELEASE_DMG": re.compile(DMG),
    # Disk image names older releases published, comma-separated; may be
    # empty. The update check accepts them as it accepts RELEASE_DMG.
    "LEGACY_RELEASE_DMGS": re.compile(f"(|{DMG}(,{DMG})*)"),
    "RELEASE_REPOSITORY": re.compile(r"[A-Za-z0-9-]+/[A-Za-z0-9._-]+"),
    # The app icon's SVG source, in the identity file's directory.
    "ICON": re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]*\.svg"),
    # The bridged-networking helper's launchd service; empty for an app
    # that ships no helper and offers only NAT.
    "NETWORK_HELPER_SERVICE": re.compile(r"(|[A-Za-z0-9]+(\.[A-Za-z0-9-]+)+)"),
    # The guest image's sources, which build.py and package.py take as
    # --system and --load-path, relative to the root of the Git repository
    # that holds the identity file (see guest()).
    "GUEST_SYSTEM": REPOSITORY_PATH,
    "GUEST_LOAD_PATH": REPOSITORY_PATH,
    # How the guest gets its account's password: package.py's --credentials
    # (guest/guix/artifact.py CREDENTIALS).
    "GUEST_CREDENTIALS": re.compile(r"first-boot|preset"),
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


def guest_paths(values, path=None):
    """GUEST_SYSTEM and GUEST_LOAD_PATH resolved against the root of the Git
    repository that tracks the identity file, which must exist as a file and
    a directory there."""
    path = (Path(path) if path is not None else selected()).resolve()
    found = subprocess.run(["git", "-C", str(path.parent), "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
    if found.returncode != 0:
        raise IdentityError(f"{path}: not in a Git repository, which GUEST_SYSTEM "
                            "and GUEST_LOAD_PATH are relative to")
    root = Path(found.stdout.strip()).resolve()
    # An untracked file inside another repository is not that repository's.
    if subprocess.run(["git", "--literal-pathspecs", "-C", str(root), "ls-files",
                       "--error-unmatch", "--",
                       str(path.relative_to(root))], capture_output=True).returncode != 0:
        raise IdentityError(f"{path}: not tracked by the Git repository at {root}")
    system, load_path = root / values["GUEST_SYSTEM"], root / values["GUEST_LOAD_PATH"]
    if not system.is_file():
        raise IdentityError(f"{path}: GUEST_SYSTEM {system} is not a file")
    if not load_path.is_dir():
        raise IdentityError(f"{path}: GUEST_LOAD_PATH {load_path} is not a directory")
    return system, load_path


def guest(values, path=None):
    """package.py's arguments for the guest."""
    system, load_path = guest_paths(values, path)
    return ["--system", str(system), "--load-path", str(load_path),
            "--credentials", values["GUEST_CREDENTIALS"]]


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
    if argv == ["guest"]:
        try:
            print(shlex.join(guest(values)))
        except IdentityError as error:
            sys.exit(f"app-identity: {error}")
        return
    if argv == ["shell"]:
        for key, value in values.items():
            print(f"{key}={shlex.quote(value)}")
        return
    sys.exit("usage: identity.py check | shell | keys | icon | guest")


if __name__ == "__main__":
    main(sys.argv[1:])
