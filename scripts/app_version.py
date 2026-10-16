#!/usr/bin/env python3
"""Resolve the Git version used by app stamping and build caching."""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def release_tag_prefix() -> str:
    """The app identity's release tags: this prefix plus X.Y.Z (docs/releasing.md)."""
    path = Path(__file__).resolve().parents[1] / "macos/apps/identity.py"
    spec = importlib.util.spec_from_file_location("app_identity", path)
    identity = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(identity)
    return identity.load()["RELEASE_TAG_PREFIX"]


def build_version(root: Path) -> dict[str, str] | None:
    def git(*arguments: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(root), *arguments],
            text=True,
            stderr=subprocess.PIPE,
        ).strip()

    try:
        inside = git("rev-parse", "--is-inside-work-tree")
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    if inside != "true":
        return None

    prefix = release_tag_prefix()
    describe = git("describe", "--tags", "--match", prefix + "[0-9]*", "--always")
    # Unlike `git describe --dirty`, status also detects untracked source files.
    if git("status", "--porcelain", "--untracked-files=all"):
        describe += "-dirty"
    release = re.fullmatch(re.escape(prefix) + r"([0-9]+\.[0-9]+\.[0-9]+)", describe)
    return {
        "CFBundleShortVersionString": release.group(1) if release else "0.0.0",
        "CFBundleVersion": git("rev-list", "--count", "HEAD"),
        "TryOmarchyBuildDescribe": describe,
        **upstream_bases(root, git),
    }


def upstream_bases(root: Path, git) -> dict[str, str]:
    """The three upstreams a build carries (docs/releasing.md)."""
    bases = {}
    try:
        # Upstream's tags live under try-omarchy/, apart from Try Roguix's.
        fork_point = git("merge-base", "HEAD", "refs/remotes/upstream/main")
        bases["RoguixTryOmarchyBase"] = "{} ({})".format(
            git("describe", "--tags", "--match", "try-omarchy/v[0-9]*", fork_point)
            .removeprefix("try-omarchy/"),
            fork_point,
        )
    except subprocess.CalledProcessError:
        pass
    modules = root / "guest/guix/modules/roguix"
    try:
        version = re.search(r'\(name "omarchy"\)\s*\(version "([^"]+)"\)',
                            (modules / "omarchy.scm").read_text())
        if version:
            bases["RoguixOmarchyVersion"] = version.group(1)
        bases["RoguixGuixCommit"] = (modules / "guix-commit").read_text().strip()
    except OSError:
        pass
    return bases


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--plist", type=Path)
    action.add_argument("--require-release", action="store_true")
    action.add_argument("--check-app", type=Path,
                        help="fail unless this built app carries the release tag at HEAD")
    args = parser.parse_args()
    version = build_version(args.root)

    if args.require_release or args.check_app:
        if version and version["TryOmarchyBuildDescribe"].endswith("-dirty"):
            raise ValueError("the worktree must be clean before building a signed app")
        if not version or re.fullmatch(
            re.escape(release_tag_prefix()) + r"[0-9]+\.[0-9]+\.[0-9]+",
            version["TryOmarchyBuildDescribe"],
        ) is None:
            raise ValueError(
                f"HEAD must carry an exact {release_tag_prefix()}X.Y.Z release tag")
        if args.check_app:
            info = plistlib.loads((args.check_app / "Contents/Info.plist").read_bytes())
            for key in ("CFBundleShortVersionString", "TryOmarchyBuildDescribe"):
                if info.get(key) != version[key]:
                    raise ValueError(
                        f"{args.check_app} has {key} {info.get(key)!r}, "
                        f"but {version['TryOmarchyBuildDescribe']} at HEAD needs {version[key]!r}"
                    )
    elif version is None:
        print(
            f"warning: {args.root} is not a git checkout; "
            "keeping the checked-in Info.plist version",
            file=sys.stderr,
        )
    else:
        value = plistlib.loads(args.plist.read_bytes())
        value.update(version)
        args.plist.write_bytes(plistlib.dumps(value))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"app-version: {error}", file=sys.stderr)
        raise SystemExit(1)
