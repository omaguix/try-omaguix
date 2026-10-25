#!/usr/bin/env python3
"""Release Omaguix: the signed channel commit, CI's builds of it and a manifest.

docs/decisions/0006-one-roguix-release-step.md: publish-channel pushes the
channel commit C to release/C, omaguix/omaguix's CI builds C for every
architecture, the VPS imports CI's releases, every package item is checked on
a server, and only then a signed release.json on top of C moves the channel's
main. Any failure stops before main moves. `--resume RUN` finishes from a
CI run of a commit already on release/C, so a failed VPS import or coverage
check does not need another build.

A release must not name an older Guix than the previous one
(docs/decisions/0007): when the pin changed, .env's GUIX_CHECKOUT, a Git
clone of Guix holding both commits, decides that the new pin descends from
the previous release's.
"""

import argparse
import concurrent.futures
import hashlib
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
CI_REPO = "omaguix/omaguix"
WORKFLOW = "build-desktop.yml"
WORKFLOW_NAME = "build-desktop"
# Matrix system -> artifact and release prefix in CI's workflow.
ARCHITECTURES = {"aarch64-linux": "aarch64-desktop",
                 "x86_64-linux": "x86_64-desktop"}
BORDEAUX = "https://bordeaux.guix.gnu.org"
MANIFEST = "release.json"
# Lists in each `split-PREFIX` artifact, as CI's desktop-split names them.
ARTIFACT_LISTS = ("publish.txt", "vps-fetch.txt", "vps-has.txt",
                  "package-closure.txt")
# The patch CI applies to the pinned Guix before building the Guix that VMs
# move to another pin with (docs/decisions/0007): its path in the channel.
GUIX_PATCH = "modules/omaguix/guix-skip-forward-check.patch"
PIN_FILE = "modules/omaguix/guix-commit"
# A Guix fork commit on top of the pin, for a fix not yet in Guix: CI makes
# G' on it (omaguix/omaguix scripts/guix-base).
FORK_FILE = "modules/omaguix/guix-fork"
COMMIT_ID = re.compile(r"[0-9a-f]{40}")
# A direct store item, as Guix names one (nix-base32 hash).
STORE_ITEM = re.compile(r"/gnu/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._?=-]+")
# delay: external deadline, a substitute server that accepts the connection
# but never answers a narinfo request.
NARINFO_TIMEOUT = 60


class ReleaseError(Exception):
    pass


def omaguix_server():
    """The substitute URL of %omaguix-trust, its only definition."""
    source = (HERE / "modules" / "omaguix" / "trust.scm").read_text()
    body = source[source.index("(define %omaguix-trust"):]
    return re.findall(r'"([^"]*)"', body)[0]


def guix_pin():
    return (HERE / PIN_FILE).read_text().strip()


def guix_patch_sha256():
    """SHA-256 of the Guix patch, as publish-channel copies it into C."""
    return hashlib.sha256((HERE / GUIX_PATCH).read_bytes()).hexdigest()


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


def read_builds(directory, commit, pin, patch_sha256):
    """Each architecture's lists from `gh run download`, checked to be CI's
    build of COMMIT at PIN for that architecture, with a Guix built from PIN
    plus the patch whose SHA-256 is PATCH_SHA256."""
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
        # The Guix profile whose guix built the system in CI: VMs
        # on another pin substitute it (docs/decisions/0007), so it is
        # checked and served like the packages.
        guix_path = artifact / "guix-profile.txt"
        guix = guix_path.read_text().strip() if guix_path.is_file() else ""
        if not STORE_ITEM.fullmatch(guix):
            raise ReleaseError(f"split-{prefix}/guix-profile.txt is {guix!r}, "
                               "not a store item")
        if guix not in lists["package-closure.txt"]:
            raise ReleaseError(f"split-{prefix}: the Guix profile {guix} is "
                               "not in package-closure.txt")
        # That Guix is PIN plus GUIX_PATCH, committed by CI; `guix describe'
        # in it names that commit, which VMs check before running it.
        found = {}
        for name in ("guix-patch-sha256.txt", "guix-patched-commit.txt"):
            path = artifact / name
            found[name] = path.read_text().strip() if path.is_file() else ""
        if found["guix-patch-sha256.txt"] != patch_sha256:
            raise ReleaseError(f"split-{prefix}/guix-patch-sha256.txt is "
                               f"{found['guix-patch-sha256.txt']!r}, expected "
                               f"{patch_sha256!r} ({GUIX_PATCH})")
        patched = found["guix-patched-commit.txt"]
        if not COMMIT_ID.fullmatch(patched):
            raise ReleaseError(f"split-{prefix}/guix-patched-commit.txt is "
                               f"{patched!r}, not a commit")
        tag_path = artifact / "release-tag.txt"
        tag = tag_path.read_text().strip() if tag_path.is_file() else ""
        if bool(tag) != bool(lists["publish.txt"]):
            raise ReleaseError(f"split-{prefix}: release tag {tag!r} with "
                               f"{len(lists['publish.txt'])} items to publish")
        builds[system] = {"release": tag or None, "guix": guix,
                          "guix-patched-commit": patched, **lists}
    patched = {build["guix-patched-commit"] for build in builds.values()}
    if len(patched) != 1:
        raise ReleaseError("the architectures' Guix come from different "
                           f"commits: {' '.join(sorted(patched))}")
    return builds


def previous_pin(channel, commit):
    """The Guix pin of the release COMMIT is made on (its one parent, the
    channel's main), or None when no commit before COMMIT has ever held a
    release. Any Git failure stops the release: it never counts as the
    first one."""
    parents = git(channel, "rev-list", "--parents", "-n", "1", commit).split()[1:]
    if len(parents) != 1:
        raise ReleaseError(f"channel commit {commit} has {len(parents)} parents, "
                           "not one (the channel's main)")
    parent = parents[0]
    if not git(channel, "ls-tree", "--name-only", parent, "--", MANIFEST):
        if git(channel, "log", "-n", "1", "--format=%H", parent, "--", MANIFEST):
            raise ReleaseError(f"the channel's main {parent} lacks {MANIFEST}, "
                               "which an earlier commit had")
        return None
    try:
        pin = json.loads(git(channel, "show", f"{parent}:{MANIFEST}"))["guix-commit"]
    except (ValueError, KeyError, TypeError) as error:
        raise ReleaseError(f"{parent}:{MANIFEST} names no guix-commit: {error}")
    if not isinstance(pin, str) or not COMMIT_ID.fullmatch(pin):
        raise ReleaseError(f"{parent}:{MANIFEST} has guix-commit {pin!r}")
    return pin


def check_guix_moves_forward(previous, pin, checkout):
    """Refuse PIN unless it is PREVIOUS or descends from it in the Guix
    clone CHECKOUT: VMs move to a release's Guix without Guix's own
    downgrade check (docs/decisions/0007)."""
    if previous is None or previous == pin:
        return
    if not checkout:
        raise ReleaseError(f"the Guix pin moves from {previous} to {pin}; "
                           ".env sets no GUIX_CHECKOUT, a Guix clone to check "
                           "that it moves forward")
    for commit in (previous, pin):
        if subprocess.run(["git", "-C", checkout, "cat-file", "-e",
                           f"{commit}^{{commit}}"],
                          capture_output=True).returncode != 0:
            raise ReleaseError(f"GUIX_CHECKOUT {checkout} lacks Guix commit "
                               f"{commit}; fetch it there first")
    result = subprocess.run(["git", "-C", checkout, "merge-base",
                             "--is-ancestor", previous, pin])
    if result.returncode == 1:
        raise ReleaseError(f"the Guix pin {pin} does not descend from the "
                           f"previous release's {previous}")
    if result.returncode != 0:
        raise ReleaseError(f"git merge-base exited with {result.returncode}")


def narinfo_status(server, item):
    """HTTP status of ITEM's narinfo on SERVER."""
    store_hash = Path(item).name.split("-", 1)[0]
    try:
        with urllib.request.urlopen(f"{server}/{store_hash}.narinfo",
                                    timeout=NARINFO_TIMEOUT) as reply:
            return reply.status
    except urllib.error.HTTPError as error:
        return error.code


def coverage(builds, omaguix, status=narinfo_status):
    """Per architecture, how many package items each server serves.
    Omaguix's server is asked only about items bordeaux lacks, as
    desktop-split does. Raises when an item is served nowhere."""
    def where(item):
        if status(BORDEAUX, item) == 200:
            return "bordeaux"
        return "omaguix" if status(omaguix, item) == 200 else None

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
                              "omaguix": places.count("omaguix")}
    return result


def manifest(commit, try_omaguix, pin, fork, patch_sha256, ci_run, builds,
             served):
    return {
        "channel-commit": commit,
        "try-omaguix-commit": try_omaguix,
        "guix-commit": pin,
        "guix-fork": fork,
        "guix-patch": {"file": GUIX_PATCH, "sha256": patch_sha256},
        "guix-patched-commit": next(iter(builds.values()))["guix-patched-commit"],
        "ci": {"repository": CI_REPO, "run-id": ci_run["databaseId"],
               "url": ci_run["url"], "commit": ci_run["headSha"]},
        "architectures": {
            system: {"guix": build["guix"],
                     "release": build["release"],
                     "published": len(build["publish.txt"]),
                     "served-by-bordeaux": served[system]["bordeaux"],
                     "served-by-omaguix": served[system]["omaguix"]}
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


def plan(try_omaguix, pin, channel, env, omaguix):
    ssh = (f"ssh {env['SSH_USER']}@{env['SSH_HOST']} {env['VPS_IMPORT']} TAG"
           if all(env.get(k) for k in ("SSH_USER", "SSH_HOST", "VPS_IMPORT"))
           else "ssh: .env lacks SSH_USER, SSH_HOST or VPS_IMPORT")
    return "\n".join([
        f"try-omaguix {try_omaguix}, Guix {pin}, channel checkout {channel}",
        "1. guest/guix/publish-channel: signed commit C, pushed to release/C;"
        " a changed Guix pin must descend from the previous release's"
        " (GUIX_CHECKOUT)",
        f"2. gh workflow run {WORKFLOW} -R {CI_REPO} -f channel_commit=C,"
        " gh run watch RUN --exit-status, gh run download RUN",
        f"3. for each architecture's CI release: {ssh};"
        f" every package item served by {BORDEAUX} or {omaguix}",
        f"4. {MANIFEST} signed on C, pushed to main; release/C deleted",
        "--resume RUN: steps 3 and 4 from finished CI run RUN of a published"
        " C, with the pin, patch and try-omaguix commit C carries",
    ])


def release(args):
    channel = args.channel.resolve()
    omaguix = omaguix_server()
    if args.resume:
        env = read_env(ROOT / ".env") if (ROOT / ".env").is_file() else {}
        if args.dry_run:
            print(plan("(from C)", "(from C)", channel, env, omaguix))
            return
        resume(args, env, omaguix)
        return
    pin = guix_pin()
    patch_sha256 = guix_patch_sha256()
    if run(["git", "-C", str(ROOT), "status", "--porcelain", "--",
            "guest/guix"]).strip():
        raise ReleaseError("commit guest/guix in try-omaguix first")
    try_omaguix = run(["git", "-C", str(ROOT), "rev-parse", "HEAD"]).strip()
    env = read_env(ROOT / ".env") if (ROOT / ".env").is_file() else {}
    if args.dry_run:
        print(plan(try_omaguix, pin, channel, env, omaguix))
        return

    output = run([str(HERE / "publish-channel")],
                 env={**os.environ, "OMAGUIX_CHANNEL_DIR": str(channel)})
    commit = channel_commit(output)
    if commit is None:
        print("release: the channel already matches try-omaguix")
        return
    check_guix_moves_forward(previous_pin(channel, commit), pin,
                             env.get("GUIX_CHECKOUT"))
    number = run_id(run(["gh", "workflow", "run", WORKFLOW, "-R", CI_REPO,
                         "-f", f"channel_commit={commit}"]))
    ci_run = wait_for_run(number)
    with tempfile.TemporaryDirectory(prefix="omaguix-release-") as tmp:
        download_splits(number, tmp)
        builds = read_builds(Path(tmp), commit, pin, patch_sha256)
    finish(channel, commit, try_omaguix, pin, patch_sha256, ci_run, builds,
           env, omaguix)


def wait_for_run(number):
    """CI run NUMBER of WORKFLOW once it ended successfully."""
    view = ["gh", "run", "view", number, "-R", CI_REPO, "--json",
            "databaseId,url,headSha,conclusion,workflowName"]
    # Before hours of watching: a run of another workflow is refused at once.
    workflow = json.loads(run(view))["workflowName"]
    if workflow != WORKFLOW_NAME:
        raise ReleaseError(f"CI run {number} is {workflow!r}, "
                           f"not {WORKFLOW_NAME!r}")
    # gh polls GitHub's API until the run ends (external polling).
    # delay: GitHub API polling, one request a minute for a run of hours.
    run(["gh", "run", "watch", number, "-R", CI_REPO, "--exit-status",
         "--compact", "--interval", "60"], capture=False)
    ci_run = json.loads(run(view))
    if ci_run["conclusion"] != "success":
        raise ReleaseError(f"CI run {number} ended {ci_run['conclusion']}")
    return ci_run


def download_splits(number, directory):
    """Only the split-PREFIX lists: the run's other artifacts hold archives."""
    run(["gh", "run", "download", number, "-R", CI_REPO, "-D", str(directory),
         "--pattern", "split-*"])


def finish(channel, commit, try_omaguix, pin, patch_sha256, ci_run, builds,
           env, omaguix):
    """The VPS imports, the coverage check and the manifest that moves main."""
    for build in builds.values():
        if build["release"]:
            vps_import(env, build["release"])
    served = coverage(builds, omaguix)
    head = publish_manifest(
        channel, commit,
        manifest(commit, try_omaguix, pin, guix_fork(channel, commit),
                 patch_sha256, ci_run, builds, served))
    print(f"release: channel main is {head}, built by {ci_run['url']}")


def run_commit(directory):
    """The one channel commit the downloaded splits were built from."""
    found = set()
    for prefix in ARCHITECTURES.values():
        path = Path(directory) / f"split-{prefix}" / "channel-commit.txt"
        found.add(path.read_text().strip() if path.is_file() else None)
    if len(found) != 1 or not COMMIT_ID.fullmatch(next(iter(found)) or ""):
        raise ReleaseError("the run's splits name no single channel commit: "
                           f"{sorted(map(str, found))}")
    return found.pop()


def guix_fork(channel, commit):
    """The Guix fork commit that channel commit COMMIT names, as {"url",
    "commit"}, or None."""
    if not git(channel, "ls-tree", "--name-only", commit, FORK_FILE).strip():
        return None
    # One line, as omaguix/omaguix's scripts/guix-base reads it.
    lines = git(channel, "show", f"{commit}:{FORK_FILE}").splitlines()
    fields = lines[0].split() if len(lines) == 1 else []
    if (len(fields) != 2 or not COMMIT_ID.fullmatch(fields[1])
            or not re.fullmatch(r"(https|file)://[A-Za-z0-9./_-]+", fields[0])):
        raise ReleaseError(f"{commit}:{FORK_FILE} is not 'URL COMMIT': "
                           f"{fields}")
    return {"url": fields[0], "commit": fields[1]}


def channel_inputs(channel, commit):
    """The Guix pin, the patch's SHA-256 and the full try-omaguix commit that
    channel commit COMMIT carries, as publish-channel made it."""
    pin = git(channel, "show", f"{commit}:{PIN_FILE}").strip()
    if not COMMIT_ID.fullmatch(pin):
        raise ReleaseError(f"{commit}:{PIN_FILE} is {pin!r}")
    patch = subprocess.run(["git", "-C", str(channel), "show",
                            f"{commit}:{GUIX_PATCH}"], capture_output=True)
    if patch.returncode != 0:
        raise ReleaseError(f"channel commit {commit} has no {GUIX_PATCH}")
    subject = git(channel, "log", "-1", "--format=%s", commit).strip()
    found = re.fullmatch(r"Omaguix from try-omaguix ([0-9a-f]{7,40})", subject)
    if not found:
        raise ReleaseError(f"channel commit {commit} names no try-omaguix "
                           f"commit: {subject!r}")
    try_omaguix = run(["git", "-C", str(ROOT), "rev-parse", "--verify",
                       f"{found.group(1)}^{{commit}}"]).strip()
    return pin, hashlib.sha256(patch.stdout).hexdigest(), try_omaguix


def resume(args, env, omaguix):
    """Finish a release from CI run args.resume of a published channel
    commit, without publishing or building again."""
    if not args.resume.isdigit():
        raise ReleaseError(f"--resume takes a run id, not {args.resume!r}")
    channel = args.channel.resolve()
    ci_run = wait_for_run(args.resume)
    with tempfile.TemporaryDirectory(prefix="omaguix-release-") as tmp:
        download_splits(args.resume, tmp)
        commit = run_commit(tmp)
        # release/C points at C until C is released: a released run, or a
        # branch that moved, is not resumed.
        remote = git(channel, "ls-remote", "origin",
                     f"refs/heads/release/{commit}").split()
        if remote[:1] != [commit]:
            raise ReleaseError(f"the channel's release/{commit} is "
                               f"{remote[:1] or 'absent'}, not {commit}")
        git(channel, "fetch", "--quiet", "origin", "main", f"release/{commit}")
        pin, patch_sha256, try_omaguix = channel_inputs(channel, commit)
        check_guix_moves_forward(previous_pin(channel, commit), pin,
                                 env.get("GUIX_CHECKOUT"))
        builds = read_builds(Path(tmp), commit, pin, patch_sha256)
    finish(channel, commit, try_omaguix, pin, patch_sha256, ci_run, builds,
           env, omaguix)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--channel", type=Path,
        default=Path(os.environ.get("OMAGUIX_CHANNEL_DIR",
                                    ROOT.parent / "omaguix-channel")),
        help="the omaguix channel checkout (OMAGUIX_CHANNEL_DIR)")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the steps and change nothing")
    parser.add_argument("--resume", metavar="RUN",
                        help="finish from CI run RUN of a published channel "
                        "commit: no new channel commit or build")
    args = parser.parse_args()
    try:
        release(args)
    except ReleaseError as error:
        sys.exit(f"release: {error}; the channel's main did not move")


if __name__ == "__main__":
    main()
