#!/usr/bin/env python3
"""Build the development Guix image using the pinned local Git channel."""

import argparse
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import tempfile


HERE = Path(__file__).resolve().parent
# `git rev-parse --local-env-vars`; a test keeps this in sync with installed Git.
GIT_LOCAL_ENV_VARS = frozenset({
    "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS",
    "GIT_CONFIG_COUNT", "GIT_OBJECT_DIRECTORY", "GIT_DIR", "GIT_WORK_TREE",
    "GIT_IMPLICIT_WORK_TREE", "GIT_GRAFT_FILE", "GIT_INDEX_FILE",
    "GIT_NO_REPLACE_OBJECTS", "GIT_REPLACE_REF_BASE", "GIT_PREFIX",
    "GIT_INTERNAL_SUPER_PREFIX", "GIT_SHALLOW_FILE", "GIT_COMMON_DIR",
})


def git_environment():
    """Return the environment without repository-selecting Git variables.

    An inherited GIT_DIR or GIT_WORK_TREE would make `git -C SOURCE` inspect a
    different repository than SOURCE, silently defeating the pin check.
    """
    return {k: v for k, v in os.environ.items() if k not in GIT_LOCAL_ENV_VARS}
# The system definition and the module directory `guix system image` reads;
# another app's guest passes its own with --system and --load-path.
SYSTEM = HERE / "system.scm"
LOAD_PATH = HERE / "modules"


def pin(load_path=LOAD_PATH):
    """The Guix commit the load path's modules build on: its one
    `<module directory>/guix-commit` (this repository's
    modules/roguix/guix-commit, shared with the image's /etc/roguix and the
    roguix channel)."""
    load_path = Path(load_path)
    pins = sorted(load_path.glob("*/guix-commit"))
    if len(pins) != 1:
        raise ValueError(f"expected one */guix-commit in the load path {load_path}, "
                         f"found {len(pins)}")
    if pins[0].is_symlink() or not pins[0].is_file():
        raise ValueError(f"the Guix pin is not a regular file: {pins[0]}")
    commit = pins[0].read_text(encoding="ascii").strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError(f"the Guix pin is not a commit: {pins[0]}")
    return commit


def inputs(system=SYSTEM, load_path=LOAD_PATH):
    """The files the image is built from, by name: the system definition and
    every file Git tracks under the load path, which its modules may read
    with local-file. Names are the system file's own and the load path's
    directory name plus the path below it.

    Ignored files (__pycache__, .DS_Store) are not inputs; an untracked file
    that is not ignored is refused, since Guix would copy it with the
    modules and the digest would no longer describe the build."""
    system, load_path = Path(system), Path(load_path)
    if system.is_symlink() or not system.is_file():
        raise ValueError(f"system file is not a regular file: {system}")
    if load_path.is_symlink() or not load_path.is_dir():
        raise ValueError(f"load path is not a directory: {load_path}")

    def git(*arguments):
        try:
            output = subprocess.run(
                ["git", "-C", str(load_path), *arguments, "-z", "--", "."],
                check=True, capture_output=True, text=True,
                env=git_environment()).stdout
        except (OSError, subprocess.CalledProcessError) as error:
            raise ValueError(f"cannot list the load path's files with git: {error}") from None
        return sorted(name for name in output.split("\0") if name)

    untracked = git("ls-files", "--others", "--exclude-standard")
    if untracked:
        raise ValueError(f"untracked file in the load path: {load_path / untracked[0]}")
    files = {system.name: system}
    for name in git("ls-files"):
        path = load_path / name
        for part in [path, *path.parents]:
            if part == load_path:
                break
            if part.is_symlink():
                raise ValueError(f"build input is a symlink: {part}")
        if not path.is_file():
            raise ValueError(f"build input is not a regular file: {path}")
        files[f"{load_path.name}/{name}"] = path
    return files


def build(args):
    # The image records the published channel commit it is built from as
    # /etc/roguix/channel-commit; roguix-update refuses to run without it
    # (docs/decisions/0007). (roguix system) reads it at evaluation. Only a
    # dry run, which prints the plan, goes without it.
    channel = args.channel_commit or ""
    if not re.fullmatch(r"[0-9a-f]{40}", channel) and (channel or not args.dry_run):
        raise ValueError("--channel-commit must name the channel's release commit "
                         f"(its main) the modules come from; got {channel!r}")
    source = args.source.resolve(strict=True)
    commit = pin(args.load_path)
    env = git_environment()
    env["ROGUIX_CHANNEL_COMMIT"] = channel
    # Git channels consume committed files, not a working-tree overlay.  Refuse
    # tracked edits rather than silently build something other than the source.
    head = subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "HEAD"], text=True, env=env
    ).strip()
    if head != commit:
        raise ValueError(f"Guix checkout must be pinned to {commit}; found {head}")
    changes = subprocess.check_output(
        ["git", "-C", str(source), "status", "--porcelain", "--untracked-files=no"],
        text=True, env=env,
    )
    if changes:
        raise ValueError("Guix checkout has tracked changes; commit and review a new pin first")

    # Guix authenticates signatures using a 'keyring' branch advertised by the
    # channel. A normal vendor clone only has origin/keyring, which a local
    # fetch does not advertise. Export it in a disposable bare repository,
    # never by adding refs to the supplied checkout.
    keyring = subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "--verify",
         "refs/remotes/origin/keyring^{commit}"], text=True, env=env,
    ).strip()
    output = args.output.absolute()
    if not args.check and os.path.lexists(output):
        raise ValueError(f"Output already exists; choose a new --output: {output}")
    # The root partition's size. The system fills about 11.7 GiB of it, and
    # roguix-grow-root grows it to the VM disk early in the first boot, so it
    # needs headroom only for the closure to grow; the rest would be zeros
    # the builder writes into the store copy and the image file.
    command = [
        "guix", "time-machine", "--channels=CHANNELS", "--", "system", "image",
        f"--load-path={args.load_path.absolute()}",
        "--system=aarch64-linux", "--image-type=efi-raw", "--image-size=16G",
        f"--root={output}", str(args.system.absolute()),
    ]
    if args.check:
        command.remove(f"--root={output}")
        command.insert(-1, "--dry-run")
    if args.dry_run:
        print(f"Authenticated local channel: {source} at {commit}")
        print(f"Keyring: {keyring}; official Guix introduction retained")
        print(f"Channel release: ROGUIX_CHANNEL_COMMIT={channel or '(none; a build needs --channel-commit)'}")
        print(shlex.join(command))
        return

    if platform.system() != "Linux":
        raise ValueError("Build on Linux with Guix and a running guix-daemon; macOS cannot build this image directly")
    if not shutil.which("guix"):
        raise ValueError("guix is required")
    with tempfile.TemporaryDirectory(prefix="roguix-channel-") as directory:
        channel_source = Path(directory) / "source.git"
        subprocess.run(
            ["git", "clone", "--quiet", "--bare", "--shared", str(source),
             str(channel_source)], check=True, env=env,
        )
        subprocess.run(
            ["git", "-C", str(channel_source), "update-ref", "refs/heads/keyring",
             keyring], check=True, env=env,
        )
        channels = Path(directory) / "channels.scm"
        channels.write_text(
            "(use-modules (guix channels))\n"
            "(list (channel (inherit %default-guix-channel)\n"
            f"  (url {json.dumps(channel_source.as_uri())})\n"
            f"  (commit \"{commit}\")))\n"
        )
        command[2] = f"--channels={channels}"
        if not args.check:
            output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(command, check=True, env=env)
    if args.check:
        print("Guix image evaluation succeeded; no image was built")
    else:
        print(f"Guix image GC root: {output}")


def export(args):
    """Copy the built image out of the builder, then give its space back.

    The GC root is removed only after the copy compares equal to the image,
    and plain `guix gc` keeps every other root (the time-machine profiles,
    the ungrafted system, other images).
    """
    root = args.output.absolute()
    destination = args.export.absolute()
    if not root.is_symlink() or not os.readlink(root).startswith("/gnu/store/"):
        raise ValueError(f"Not a Guix image GC root: {root}")
    if os.path.lexists(destination):
        raise ValueError(f"Export already exists; choose a new path: {destination}")
    commands = [
        ["cp", "--dereference", "--sparse=always", str(root), str(destination)],
        ["cmp", str(root), str(destination)],
        ["rm", str(root)],
        ["guix", "gc"],
        ["fstrim", "-av"],
    ]
    if args.dry_run:
        for command in commands:
            print(shlex.join(command))
        return
    if platform.system() != "Linux":
        raise ValueError("Export on the Linux builder that holds the image")
    for command in commands:
        subprocess.run(command, check=True)
    print(f"Exported {destination}; removed the GC root and gave its space back")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path,
                        default=HERE.parents[2] / "vendor/guix")
    parser.add_argument("--output", type=Path,
                        default=HERE.parents[1] / "build/guix/image.raw")
    parser.add_argument("--system", type=Path, default=SYSTEM,
                        help="system definition to build (default: %(default)s)")
    parser.add_argument("--load-path", type=Path, default=LOAD_PATH,
                        help="module directory for --system (default: %(default)s)")
    parser.add_argument("--channel-commit", metavar="COMMIT",
                        help="the channel release (a commit of its main) whose "
                             "modules the load path holds; required to build")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the plan without running Guix")
    parser.add_argument("--check", action="store_true",
                        help="run pinned Guix to evaluate the image without building it")
    # The builder shares its export directory (BUILDER_EXPORT on the host,
    # guest/guix/builder-vm) at /mnt/export, so PATH is usually under it.
    parser.add_argument("--export", type=Path, metavar="PATH",
                        help="copy the built --output image to PATH (usually under "
                             "/mnt/export), verify it, then remove its GC root, "
                             "collect garbage and trim the disk")
    args = parser.parse_args()
    try:
        if args.export:
            export(args)
        else:
            build(args)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"guix-image: {error}\n")


if __name__ == "__main__":
    main()
