"""The release step moves the channel's main only for a fully served build
of the commit it published (docs/decisions/0006-one-roguix-release-step.md)."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
import release  # noqa: E402

COMMIT = "c" * 40
PIN = release.guix_pin()
ITEM = "/gnu/store/{}-{}"


def item(n, name="pkg"):
    return ITEM.format(f"{n:032d}", name)


GUIX = item(9, "profile")
PATCH_SHA256 = release.guix_patch_sha256()
PATCHED = "b" * 40


def write_artifact(directory, system, commit=COMMIT, pin=PIN, tag="",
                   publish=(), closure=(item(1), item(2), GUIX), guix=GUIX,
                   patch_sha256=PATCH_SHA256, patched=PATCHED):
    artifact = directory / f"split-{release.ARCHITECTURES[system]}"
    artifact.mkdir(parents=True)
    (artifact / "channel-commit.txt").write_text(commit + "\n")
    (artifact / "guix-commit.txt").write_text(pin + "\n")
    (artifact / "system.txt").write_text(system + "\n")
    if tag:
        (artifact / "release-tag.txt").write_text(tag + "\n")
    if guix:
        (artifact / "guix-profile.txt").write_text(guix + "\n")
    for name, value in (("guix-patch-sha256.txt", patch_sha256),
                        ("guix-patched-commit.txt", patched)):
        if value:
            (artifact / name).write_text(value + "\n")
    for name, lines in (("publish.txt", publish),
                        ("package-closure.txt", closure)):
        if lines:
            (artifact / name).write_text("".join(f"{x}\n" for x in lines))


class OutputParsingTests(unittest.TestCase):
    def test_channel_commit_is_the_last_marker_line(self):
        self.assertEqual(release.channel_commit(f"noise\nchannel-commit {COMMIT}\n"),
                         COMMIT)
        self.assertIsNone(release.channel_commit(""))
        self.assertIsNone(release.channel_commit("channel-commit abc\n"))

    def test_run_id_comes_from_the_ci_repositorys_run_url(self):
        output = ("✓ Created workflow_dispatch event for build-desktop.yml\n"
                  "https://github.com/omaguix/omaguix/actions/runs/123456\n")
        self.assertEqual(release.run_id(output), "123456")
        for other in ("", "https://github.com/someone/else/actions/runs/1"):
            with self.assertRaises(release.ReleaseError):
                release.run_id(other)

    def test_env_values_lose_their_quotes(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / ".env"
            path.write_text('# comment\nSSH_USER="user"\nSSH_PORT=22\n'
                            "VPS_IMPORT='/srv/omaguix/scripts/vps-import'\n")
            self.assertEqual(release.read_env(path), {
                "SSH_USER": "user", "SSH_PORT": "22",
                "VPS_IMPORT": "/srv/omaguix/scripts/vps-import"})


class ReadBuildsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_both_architectures_with_and_without_a_release(self):
        write_artifact(self.dir, "aarch64-linux", tag="aarch64-desktop-x",
                       publish=[item(2)])
        write_artifact(self.dir, "x86_64-linux")
        builds = release.read_builds(self.dir, COMMIT, PIN, PATCH_SHA256)
        self.assertEqual(builds["aarch64-linux"]["release"], "aarch64-desktop-x")
        self.assertEqual(builds["aarch64-linux"]["publish.txt"], [item(2)])
        self.assertIsNone(builds["x86_64-linux"]["release"])
        self.assertEqual(builds["x86_64-linux"]["vps-fetch.txt"], [])
        self.assertEqual(builds["x86_64-linux"]["guix"], GUIX)
        self.assertEqual(builds["x86_64-linux"]["guix-patched-commit"], PATCHED)

    def test_the_guix_is_the_pin_plus_this_patch_in_one_commit(self):
        # VMs run that Guix with --no-check-forward-update, which only the
        # patch adds, after checking `guix describe' names the commit.
        for kwargs, error in (({"patch_sha256": ""}, "guix-patch-sha256"),
                              ({"patch_sha256": "0" * 64}, "guix-patch-sha256"),
                              ({"patched": ""}, "not a commit"),
                              ({"patched": "B" * 40}, "not a commit"),
                              ({"patched": "d" * 40}, "different commits")):
            with self.subTest(**kwargs), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                write_artifact(directory, "aarch64-linux", **kwargs)
                write_artifact(directory, "x86_64-linux")
                with self.assertRaisesRegex(release.ReleaseError, error):
                    release.read_builds(directory, COMMIT, PIN, PATCH_SHA256)

    def test_the_patch_is_the_one_in_the_channel(self):
        self.assertEqual(release.GUIX_PATCH,
                         "modules/omaguix/guix-skip-forward-check.patch")
        self.assertTrue((HERE / release.GUIX_PATCH).is_file())

    def test_the_guix_profile_is_a_checked_store_item(self):
        # VMs substitute it by its path, so it must be one item of the
        # closure whose every item the release checks is served.
        for guix, error in (("", "not a store item"),
                            ("/gnu/store/../etc/passwd", "not a store item"),
                            (item(8, "profile"), "not in package-closure")):
            with self.subTest(guix=guix), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                write_artifact(directory, "aarch64-linux", guix=guix)
                write_artifact(directory, "x86_64-linux")
                with self.assertRaisesRegex(release.ReleaseError, error):
                    release.read_builds(directory, COMMIT, PIN, PATCH_SHA256)

    def test_every_architecture_must_have_built(self):
        write_artifact(self.dir, "aarch64-linux")
        with self.assertRaisesRegex(release.ReleaseError, "split-x86_64"):
            release.read_builds(self.dir, COMMIT, PIN, PATCH_SHA256)

    def test_a_build_of_another_commit_or_pin_is_refused(self):
        for kwargs in ({"commit": "d" * 40}, {"pin": "e" * 40}):
            with self.subTest(**kwargs), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                write_artifact(directory, "aarch64-linux", **kwargs)
                write_artifact(directory, "x86_64-linux")
                with self.assertRaises(release.ReleaseError):
                    release.read_builds(directory, COMMIT, PIN, PATCH_SHA256)

    def test_a_release_tag_goes_with_items_to_publish(self):
        write_artifact(self.dir, "aarch64-linux", publish=[item(2)])
        write_artifact(self.dir, "x86_64-linux")
        with self.assertRaisesRegex(release.ReleaseError, "release tag"):
            release.read_builds(self.dir, COMMIT, PIN, PATCH_SHA256)


class CoverageTests(unittest.TestCase):
    OMAGUIX = "https://omaguix.example"

    def builds(self, *items):
        return {"aarch64-linux": {"package-closure.txt": list(items)}}

    def test_counts_where_each_item_is_served(self):
        asked = []

        def status(server, path):
            asked.append((server, path))
            return 200 if (server == release.BORDEAUX) == (path == item(1)) else 404
        served = release.coverage(self.builds(item(1), item(2)), self.OMAGUIX, status)
        self.assertEqual(served, {"aarch64-linux": {"bordeaux": 1, "omaguix": 1}})
        # Omaguix's server is not asked about what bordeaux serves.
        self.assertNotIn((self.OMAGUIX, item(1)), asked)

    def test_an_item_served_nowhere_stops_the_release(self):
        with self.assertRaisesRegex(release.ReleaseError, item(3)):
            release.coverage(self.builds(item(3)), self.OMAGUIX,
                             lambda server, path: 404)


class ManifestTests(unittest.TestCase):
    def test_names_the_commit_its_builds_and_their_servers(self):
        builds = {"aarch64-linux": {"release": "aarch64-desktop-x", "guix": GUIX,
                                    "guix-patched-commit": PATCHED,
                                    "publish.txt": [item(2)]},
                  "x86_64-linux": {"release": None, "guix": GUIX,
                                   "guix-patched-commit": PATCHED,
                                   "publish.txt": []}}
        served = {"aarch64-linux": {"bordeaux": 5, "omaguix": 2},
                  "x86_64-linux": {"bordeaux": 7, "omaguix": 0}}
        ci_run = {"databaseId": 42, "url": "https://example/runs/42",
                  "headSha": "f" * 40}
        fork = {"url": "https://codeberg.org/someone/guix", "commit": "e" * 40}
        document = release.manifest(COMMIT, "a" * 40, PIN, fork, PATCH_SHA256,
                                    ci_run, builds, served)
        self.assertEqual(document["channel-commit"], COMMIT)
        self.assertEqual(document["guix-commit"], PIN)
        self.assertEqual(document["guix-fork"], fork)
        self.assertEqual(document["guix-patch"],
                         {"file": release.GUIX_PATCH, "sha256": PATCH_SHA256})
        self.assertEqual(document["guix-patched-commit"], PATCHED)
        self.assertEqual(document["ci"]["run-id"], 42)
        self.assertEqual(document["architectures"]["aarch64-linux"],
                         {"guix": GUIX, "release": "aarch64-desktop-x", "published": 1,
                          "served-by-bordeaux": 5, "served-by-omaguix": 2})
        self.assertIsNone(document["architectures"]["x86_64-linux"]["release"])
        json.dumps(document)


def plain_git(directory, *args):
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
               GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.com",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com")
    return subprocess.run(["git", "-C", str(directory), *args], env=env,
                          check=True, capture_output=True, text=True).stdout.strip()


class GuixMovesForwardTests(unittest.TestCase):
    """A release never names an older Guix than the previous release."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.guix = Path(self.tmp.name) / "guix"
        plain_git(self.tmp.name, "init", "--quiet", "--initial-branch=master",
                  str(self.guix))

        def commit(message):
            plain_git(self.guix, "commit", "--quiet", "--allow-empty", "-m", message)
            return plain_git(self.guix, "rev-parse", "HEAD")
        self.old = commit("old")
        self.new = commit("new")
        plain_git(self.guix, "checkout", "--quiet", "-b", "side", self.old)
        self.side = commit("side")

    def check(self, previous, pin, checkout="checkout"):
        release.check_guix_moves_forward(
            previous, pin, str(self.guix) if checkout == "checkout" else checkout)

    def test_a_newer_or_the_same_pin_passes(self):
        self.check(self.old, self.new)
        self.check(self.new, self.new, checkout=None)
        self.check(None, self.new, checkout=None)

    def test_an_older_or_diverged_pin_is_refused(self):
        for previous, pin in ((self.new, self.old), (self.new, self.side)):
            with self.subTest(pin=pin), \
                    self.assertRaisesRegex(release.ReleaseError, "does not descend"):
                self.check(previous, pin)

    def test_a_moved_pin_needs_a_clone_that_has_both_commits(self):
        with self.assertRaisesRegex(release.ReleaseError, "GUIX_CHECKOUT"):
            self.check(self.old, self.new, checkout=None)
        with self.assertRaisesRegex(release.ReleaseError, "lacks Guix commit"):
            self.check(self.old, "e" * 40)

    def channel(self):
        """A channel whose first commit predates releases, then a release
        and a commit C on it; return the channel, the release and C."""
        channel = Path(self.tmp.name) / "channel"
        plain_git(self.tmp.name, "init", "--quiet", str(channel))
        plain_git(channel, "commit", "--quiet", "--allow-empty", "-m", "first")
        (channel / release.MANIFEST).write_text(json.dumps({"guix-commit": self.old}))
        plain_git(channel, "add", release.MANIFEST)
        plain_git(channel, "commit", "--quiet", "-m", "Release")
        released = plain_git(channel, "rev-parse", "HEAD")
        plain_git(channel, "commit", "--quiet", "--allow-empty", "-m", "C")
        return channel, released, plain_git(channel, "rev-parse", "HEAD")

    def test_the_previous_pin_is_the_parent_releases(self):
        channel, released, commit = self.channel()
        self.assertEqual(release.previous_pin(channel, commit), self.old)
        # The first release: no earlier commit ever held a release.json.
        self.assertIsNone(release.previous_pin(channel, released))

    def test_a_repository_error_is_never_the_first_release(self):
        channel, _, commit = self.channel()
        for target, where in ((channel, "e" * 40),
                              (Path(self.tmp.name) / "missing", commit)):
            with self.subTest(target=target, commit=where), \
                    self.assertRaises(release.ReleaseError):
                release.previous_pin(target, where)
        # main dropped release.json after a release: not a first release.
        plain_git(channel, "rm", "--quiet", release.MANIFEST)
        plain_git(channel, "commit", "--quiet", "-m", "drop")
        plain_git(channel, "commit", "--quiet", "--allow-empty", "-m", "C2")
        with self.assertRaisesRegex(release.ReleaseError, "which an earlier commit had"):
            release.previous_pin(channel, plain_git(channel, "rev-parse", "HEAD"))
        # A broken manifest stops the release too.
        (channel / release.MANIFEST).write_text("{")
        plain_git(channel, "add", release.MANIFEST)
        plain_git(channel, "commit", "--quiet", "-m", "broken")
        plain_git(channel, "commit", "--quiet", "--allow-empty", "-m", "C3")
        with self.assertRaisesRegex(release.ReleaseError, "names no guix-commit"):
            release.previous_pin(channel, plain_git(channel, "rev-parse", "HEAD"))

    def test_the_release_commit_has_exactly_one_parent(self):
        channel, released, commit = self.channel()
        root = plain_git(channel, "rev-list", "--max-parents=0", "HEAD")
        plain_git(channel, "checkout", "--quiet", "-b", "side", root)
        plain_git(channel, "commit", "--quiet", "--allow-empty", "-m", "side")
        plain_git(channel, "merge", "--quiet", "--no-ff", "--no-edit", commit)
        merge = plain_git(channel, "rev-parse", "HEAD")
        for target, parents in ((root, 0), (merge, 2)):
            with self.subTest(parents=parents), self.assertRaisesRegex(
                    release.ReleaseError, f"has {parents} parents, not one"):
                release.previous_pin(channel, target)


class PublishManifestTests(unittest.TestCase):
    """Against a local bare repository, with a stand-in for gpg."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        tmp = Path(self.tmp.name)
        gpg = tmp / "gpg"
        gpg.write_text("#!/bin/sh\ncat > /dev/null\n"
                       "echo '[GNUPG:] SIG_CREATED D 22 8 00 0 0 0 X' >&2\n"
                       "printf -- '-----BEGIN PGP SIGNATURE-----\\n\\n"
                       "stand-in\\n-----END PGP SIGNATURE-----\\n'\n")
        gpg.chmod(0o755)
        # An inherited GIT_DIR and the like would point git elsewhere.
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith("GIT_")}
        self.env.update(GIT_CONFIG_GLOBAL=str(tmp / "gitconfig"),
                        GIT_CONFIG_NOSYSTEM="1")
        self.old_environ = dict(os.environ)
        os.environ.clear()
        os.environ.update(self.env)
        self.git("config", "--global", "gpg.program", str(gpg), cwd=tmp)
        self.git("config", "--global", "user.name", "Test", cwd=tmp)
        self.git("config", "--global", "user.email", "test@example.com", cwd=tmp)
        self.git("config", "--global", "init.defaultBranch", "main", cwd=tmp)
        self.remote = tmp / "remote.git"
        self.git("init", "--quiet", "--bare", str(self.remote), cwd=tmp)
        self.channel = tmp / "channel"
        self.git("clone", "--quiet", str(self.remote), str(self.channel), cwd=tmp)
        (self.channel / "modules").mkdir()
        (self.channel / "modules" / "a.scm").write_text("old\n")
        self.git("add", "-A")
        self.git("commit", "--quiet", "-m", "base")
        self.git("push", "--quiet", "origin", "HEAD:refs/heads/main")
        (self.channel / "modules" / "a.scm").write_text("new\n")
        self.git("commit", "--quiet", "-am", "Omaguix from try-omaguix x")
        self.commit = self.git("rev-parse", "HEAD").strip()
        self.git("push", "--quiet", "origin",
                 f"{self.commit}:refs/heads/release/{self.commit}")

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.old_environ)
        self.tmp.cleanup()

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.channel,
                              check=True, text=True, capture_output=True,
                              env=os.environ).stdout

    def remote_ref(self, ref):
        return subprocess.run(["git", "--git-dir", str(self.remote), "rev-parse",
                               "--verify", "--quiet", ref], text=True,
                              capture_output=True).stdout.strip()

    def test_main_moves_to_the_manifest_on_top_of_the_built_commit(self):
        head = release.publish_manifest(self.channel, self.commit, {"x": 1})
        self.assertEqual(self.remote_ref("refs/heads/main"), head)
        self.assertEqual(self.git("rev-parse", f"{head}^").strip(), self.commit)
        self.assertEqual(json.loads(self.git("show", f"{head}:release.json")),
                         {"x": 1})
        self.assertEqual(self.remote_ref(f"refs/heads/release/{self.commit}"), "")

    def test_a_release_that_landed_meanwhile_is_never_overwritten(self):
        other = self.git("commit-tree", "-p", "origin/main", "-m", "other",
                         "HEAD^{tree}").strip()
        self.git("push", "--quiet", "origin", f"{other}:refs/heads/main")
        with self.assertRaises(release.ReleaseError):
            release.publish_manifest(self.channel, self.commit, {"x": 1})
        self.assertEqual(self.remote_ref("refs/heads/main"), other)
        self.assertEqual(self.remote_ref(f"refs/heads/release/{self.commit}"),
                         self.commit)


class ResumeTests(unittest.TestCase):
    """--resume takes the channel commit from the run and the rest from it."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def test_the_run_names_one_channel_commit(self):
        for system in release.ARCHITECTURES:
            write_artifact(self.dir / "same", system)
        self.assertEqual(release.run_commit(self.dir / "same"), COMMIT)

    def test_splits_of_different_or_missing_commits_are_refused(self):
        systems = list(release.ARCHITECTURES)
        write_artifact(self.dir / "mixed", systems[0])
        write_artifact(self.dir / "mixed", systems[1], commit="d" * 40)
        write_artifact(self.dir / "half", systems[0])
        for name in ("mixed", "half"):
            with self.assertRaises(release.ReleaseError):
                release.run_commit(self.dir / name)

    def test_pin_patch_and_try_omaguix_come_from_the_channel_commit(self):
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1",
                   GIT_AUTHOR_NAME="T", GIT_AUTHOR_EMAIL="t@example.com",
                   GIT_COMMITTER_NAME="T", GIT_COMMITTER_EMAIL="t@example.com")
        channel = self.dir / "channel"
        pin_file = channel / release.PIN_FILE
        pin_file.parent.mkdir(parents=True)
        pin_file.write_text("a" * 40 + "\n")
        (channel / release.GUIX_PATCH).write_bytes(b"a patch\n")
        head = subprocess.run(["git", "-C", str(release.ROOT), "rev-parse",
                               "HEAD"], text=True, capture_output=True,
                              check=True).stdout.strip()
        for command in (["init", "--quiet"], ["add", "-A"],
                        ["commit", "--quiet", "-m",
                         f"Omaguix from try-omaguix {head[:9]}"]):
            subprocess.run(["git", "-C", str(channel), *command], env=env,
                           check=True, capture_output=True)
        commit = subprocess.run(["git", "-C", str(channel), "rev-parse", "HEAD"],
                                text=True, capture_output=True,
                                check=True).stdout.strip()
        pin, sha256, try_omaguix = release.channel_inputs(channel, commit)
        self.assertEqual(pin, "a" * 40)
        self.assertEqual(sha256, hashlib.sha256(b"a patch\n").hexdigest())
        self.assertEqual(try_omaguix, head)
        self.assertIsNone(release.guix_fork(channel, commit))
        fork_file = channel / release.FORK_FILE
        for content, expected in (
                ("https://codeberg.org/someone/guix " + "e" * 40 + "\n",
                 {"url": "https://codeberg.org/someone/guix",
                  "commit": "e" * 40}),
                ("https://codeberg.org/someone/guix\n", None),
                ("https://codeberg.org/someone/guix " + "e" * 40 + "\nmore\n",
                 None)):
            fork_file.write_text(content)
            for command in (["add", "-A"], ["commit", "--quiet", "-m", "fork"]):
                subprocess.run(["git", "-C", str(channel), *command], env=env,
                               check=True, capture_output=True)
            forked = subprocess.run(["git", "-C", str(channel), "rev-parse",
                                     "HEAD"], text=True, capture_output=True,
                                    check=True).stdout.strip()
            if expected:
                self.assertEqual(release.guix_fork(channel, forked), expected)
            else:
                with self.assertRaises(release.ReleaseError):
                    release.guix_fork(channel, forked)

    def test_resume_takes_a_run_id(self):
        args = type("Args", (), {"resume": "latest", "channel": self.dir})
        with self.assertRaises(release.ReleaseError):
            release.resume(args, {}, "https://omaguix.example")


class DryRunTests(unittest.TestCase):
    def test_names_the_steps_and_changes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run(
                [sys.executable, str(HERE / "release.py"), "--dry-run",
                 "--channel", tmp], text=True, capture_output=True)
            if "commit guest/guix" in result.stderr:
                self.skipTest("guest/guix has uncommitted changes")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("channel_commit=C", result.stdout)
            self.assertIn(release.omaguix_server(), result.stdout)
            self.assertEqual(os.listdir(tmp), [])

    def test_a_resume_dry_run_changes_nothing_either(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run(
                [sys.executable, str(HERE / "release.py"), "--dry-run",
                 "--resume", "123", "--channel", tmp],
                text=True, capture_output=True,
                env={**os.environ, "PATH": tmp})  # no gh, git or ssh to run
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("--resume RUN", result.stdout)
            self.assertEqual(os.listdir(tmp), [])


if __name__ == "__main__":
    unittest.main()
