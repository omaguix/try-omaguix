#!/usr/bin/env python3
"""Release Roguix: the signed channel commit, CI's builds of it and a manifest.

docs/decisions/0006-one-roguix-release-step.md: publish-channel pushes the
channel commit C to release/C, roguixos/roguix's CI builds C for every
architecture, the VPS imports CI's releases, every package item is checked on
a server, and only then a signed release.json on top of C moves the channel's
main. Any failure stops before main moves.
"""

import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CI_REPO = "roguixos/roguix"
WORKFLOW = "build-desktop.yml"
# Matrix system -> artifact and release prefix in CI's workflow.
ARCHITECTURES = {"aarch64-linux": "aarch64-desktop",
                 "x86_64-linux": "x86_64-desktop"}
BORDEAUX = "https://bordeaux.guix.gnu.org"
MANIFEST = "release.json"
# Lists in each `split-PREFIX` artifact, as CI's desktop-split names them.
ARTIFACT_LISTS = ("publish.txt", "vps-fetch.txt", "vps-has.txt",
                  "package-closure.txt")
# delay: external deadline, a substitute server that accepts the connection
# but never answers a narinfo request.
NARINFO_TIMEOUT = 60


class ReleaseError(Exception):
    pass


def roguix_server():
    """The substitute URL of %roguix-trust, its only definition."""
    source = (HERE / "modules" / "roguix" / "trust.scm").read_text()
    body = source[source.index("(define %roguix-trust"):]
    return re.findall(r'"([^"]*)"', body)[0]


def guix_pin():
    return (HERE / "modules" / "roguix" / "guix-commit").read_text().strip()


def run(command, capture=True, **kwargs):
    """Run COMMAND; return its stdout. A failure raises ReleaseError."""
    print("+ " + shlex.join(command), file=sys.stderr)
    result = subprocess.run(command, text=True, check=False,
                            stdout=subprocess.PIPE if capture else None,
                            **kwargs)
    if result.returncode != 0:
        raise ReleaseError(f"{command[0]} exited with {result.returncode}")
    return result.stdout if capture else ""


def channel_commit(output):
    """The commit publish-channel pushed, or None when nothing changed."""
    found = re.findall(r"^channel-commit ([0-9a-f]{40})$", output, re.M)
    return found[-1] if found else None


def run_id(output):
    """The run id in the run URL `gh workflow run` prints."""
    found = re.search(
        rf"https://github\.com/{re.escape(CI_REPO)}/actions/runs/(\d+)", output)
    if not found:
        raise ReleaseError("gh workflow run printed no run URL; cannot tell "
                           "which run builds this commit")
    return found.group(1)


def read_lines(path):
    return [line for line in path.read_text().splitlines() if line]


def read_builds(directory, commit, pin):
    """Each architecture's lists from `gh run download`, checked to be CI's
    build of COMMIT at PIN for that architecture."""
    builds = {}
    for system, prefix in ARCHITECTURES.items():
        artifact = directory / f"split-{prefix}"
        if not artifact.is_dir():
            raise ReleaseError(f"the run has no artifact split-{prefix}")
        for name, expected in (("channel-commit.txt", commit),
                               ("guix-commit.txt", pin),
                               ("system.txt", system)):
            path = artifact / name
            found = path.read_text().strip() if path.is_file() else None
            if found != expected:
                raise ReleaseError(f"split-{prefix}/{name} is {found!r}, "
                                   f"expected {expected!r}")
        # GitHub keeps no empty files in an artifact either: absent is empty.
        lists = {name: read_lines(artifact / name)
                 if (artifact / name).is_file() else []
                 for name in ARTIFACT_LISTS}
        if not lists["package-closure.txt"]:
            raise ReleaseError(f"split-{prefix}/package-closure.txt is empty")
        tag_path = artifact / "release-tag.txt"
        tag = tag_path.read_text().strip() if tag_path.is_file() else ""
        if bool(tag) != bool(lists["publish.txt"]):
            raise ReleaseError(f"split-{prefix}: release tag {tag!r} with "
                               f"{len(lists['publish.txt'])} items to publish")
        builds[system] = {"release": tag or None, **lists}
    return builds


def narinfo_status(server, item):
    """HTTP status of ITEM's narinfo on SERVER."""
    store_hash = Path(item).name.split("-", 1)[0]
    try:
        with urllib.request.urlopen(f"{server}/{store_hash}.narinfo",
                                    timeout=NARINFO_TIMEOUT) as reply:
            return reply.status
    except urllib.error.HTTPError as error:
        return error.code


def coverage(builds, roguix, status=narinfo_status):
    """Per architecture, how many package items each server serves.
    roguix.frolow.dev is asked only about items bordeaux lacks, as
    desktop-split does. Raises when an item is served nowhere."""
    def where(item):
        if status(BORDEAUX, item) == 200:
            return "bordeaux"
        return "roguix" if status(roguix, item) == 200 else None

    result = {}
    with concurrent.futures.ThreadPoolExecutor(16) as pool:
        for system, build in builds.items():
            items = build["package-closure.txt"]
            places = list(pool.map(where, items))
            missing = sorted(i for i, p in zip(items, places) if p is None)
            if missing:
                raise ReleaseError(f"{system}: served nowhere: "
                                   + " ".join(missing))
            result[system] = {"bordeaux": places.count("bordeaux"),
                              "roguix": places.count("roguix")}
    return result


def manifest(commit, try_roguix, pin, ci_run, builds, served):
    return {
        "channel-commit": commit,
        "try-roguix-commit": try_roguix,
        "guix-commit": pin,
        "ci": {"repository": CI_REPO, "run-id": ci_run["databaseId"],
               "url": ci_run["url"], "commit": ci_run["headSha"]},
        "architectures": {
            system: {"release": build["release"],
                     "published": len(build["publish.txt"]),
                     "served-by-bordeaux": served[system]["bordeaux"],
                     "served-by-roguix": served[system]["roguix"]}
            for system, build in builds.items()},
    }


def read_env(path):
    """KEY=value lines of .env, which server/publish.sh sources in bash."""
    values = {}
    for line in path.read_text().splitlines():
        found = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if found:
            values[found.group(1)] = "".join(shlex.split(found.group(2)))
    return values


def vps_import(env, tag):
    """Have the VPS import CI's release TAG; blocks until it is baked."""
    for key in ("SSH_USER", "SSH_HOST", "SSH_PORT", "VPS_IMPORT"):
        if not env.get(key):
            raise ReleaseError(f".env sets no {key} (.env.example)")
    run(["ssh", "-o", "BatchMode=yes", "-p", env["SSH_PORT"],
         f"{env['SSH_USER']}@{env['SSH_HOST']}",
         shlex.join([env["VPS_IMPORT"], tag])], capture=False)


def git(channel, *args, capture=True):
    return run(["git", "-C", str(channel), *args], capture=capture)


def publish_manifest(channel, commit, document):
    """Commit DOCUMENT as release.json on COMMIT, signed, and move main."""
    git(channel, "checkout", "--quiet", "--detach", commit)
    (channel / MANIFEST).write_text(json.dumps(document, indent=2) + "\n")
    git(channel, "add", MANIFEST)
    git(channel, "commit", "--quiet", "--gpg-sign",
        "-m", f"Release {commit[:12]}", capture=False)
    changed = git(channel, "diff", "--name-only", commit, "HEAD").split()
    if changed != [MANIFEST]:
        raise ReleaseError(f"the manifest commit changes {changed}, "
                           f"not only {MANIFEST}")
    head = git(channel, "rev-parse", "HEAD").strip()
    # A plain push only fast-forwards: a release that landed meanwhile wins.
    git(channel, "push", "--quiet", "origin", f"{head}:refs/heads/main",
        capture=False)
    git(channel, "push", "--quiet", "origin", "--delete", f"release/{commit}",
        capture=False)
    return head


def plan(try_roguix, pin, channel, env, roguix):
    ssh = (f"ssh {env['SSH_USER']}@{env['SSH_HOST']} {env['VPS_IMPORT']} TAG"
           if all(env.get(k) for k in ("SSH_USER", "SSH_HOST", "VPS_IMPORT"))
           else "ssh: .env lacks SSH_USER, SSH_HOST or VPS_IMPORT")
    return "\n".join([
        f"try-roguix {try_roguix}, Guix {pin}, channel checkout {channel}",
        "1. guest/guix/publish-channel: signed commit C, pushed to release/C",
        f"2. gh workflow run {WORKFLOW} -R {CI_REPO} -f channel_commit=C,"
        " gh run watch RUN --exit-status, gh run download RUN",
        f"3. for each architecture's CI release: {ssh};"
        f" every package item served by {BORDEAUX} or {roguix}",
        f"4. {MANIFEST} signed on C, pushed to main; release/C deleted",
    ])


def release(args):
    channel = args.channel.resolve()
    roguix = roguix_server()
    pin = guix_pin()
    if run(["git", "-C", str(ROOT), "status", "--porcelain", "--",
            "guest/guix"]).strip():
        raise ReleaseError("commit guest/guix in try-roguix first")
    try_roguix = run(["git", "-C", str(ROOT), "rev-parse", "HEAD"]).strip()
    env = read_env(ROOT / ".env") if (ROOT / ".env").is_file() else {}
    if args.dry_run:
        print(plan(try_roguix, pin, channel, env, roguix))
        return

    output = run([str(HERE / "publish-channel")],
                 env={**os.environ, "ROGUIX_CHANNEL_DIR": str(channel)})
    commit = channel_commit(output)
    if commit is None:
        print("release: the channel already matches try-roguix")
        return
    number = run_id(run(["gh", "workflow", "run", WORKFLOW, "-R", CI_REPO,
                         "-f", f"channel_commit={commit}"]))
    # gh polls GitHub's API until the run ends (external polling).
    # delay: GitHub API polling, one request a minute for a run of hours.
    run(["gh", "run", "watch", number, "-R", CI_REPO, "--exit-status",
         "--compact", "--interval", "60"], capture=False)
    ci_run = json.loads(run(["gh", "run", "view", number, "-R", CI_REPO,
                             "--json", "databaseId,url,headSha,conclusion"]))
    if ci_run["conclusion"] != "success":
        raise ReleaseError(f"CI run {number} ended {ci_run['conclusion']}")
    with tempfile.TemporaryDirectory(prefix="roguix-release-") as tmp:
        run(["gh", "run", "download", number, "-R", CI_REPO, "-D", tmp])
        builds = read_builds(Path(tmp), commit, pin)
    for build in builds.values():
        if build["release"]:
            vps_import(env, build["release"])
    served = coverage(builds, roguix)
    head = publish_manifest(
        channel, commit, manifest(commit, try_roguix, pin, ci_run, builds, served))
    print(f"release: channel main is {head}, built by {ci_run['url']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--channel", type=Path,
        default=Path(os.environ.get("ROGUIX_CHANNEL_DIR",
                                    ROOT.parent / "roguix-channel")),
        help="the roguix channel checkout (ROGUIX_CHANNEL_DIR)")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the steps and change nothing")
    args = parser.parse_args()
    try:
        release(args)
    except ReleaseError as error:
        sys.exit(f"release: {error}; the channel's main did not move")


if __name__ == "__main__":
    main()
