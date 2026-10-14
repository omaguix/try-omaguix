"""The release step moves the channel's main only for a fully served build
of the commit it published (docs/decisions/0006-one-roguix-release-step.md)."""

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


def write_artifact(directory, system, commit=COMMIT, pin=PIN, tag="",
                   publish=(), closure=(item(1), item(2))):
    artifact = directory / f"split-{release.ARCHITECTURES[system]}"
    artifact.mkdir(parents=True)
    (artifact / "channel-commit.txt").write_text(commit + "\n")
    (artifact / "guix-commit.txt").write_text(pin + "\n")
    (artifact / "system.txt").write_text(system + "\n")
    if tag:
        (artifact / "release-tag.txt").write_text(tag + "\n")
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
                            "VPS_IMPORT='/srv/roguix/scripts/vps-import'\n")
            self.assertEqual(release.read_env(path), {
                "SSH_USER": "user", "SSH_PORT": "22",
                "VPS_IMPORT": "/srv/roguix/scripts/vps-import"})


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
        builds = release.read_builds(self.dir, COMMIT, PIN)
        self.assertEqual(builds["aarch64-linux"]["release"], "aarch64-desktop-x")
        self.assertEqual(builds["aarch64-linux"]["publish.txt"], [item(2)])
        self.assertIsNone(builds["x86_64-linux"]["release"])
        self.assertEqual(builds["x86_64-linux"]["vps-fetch.txt"], [])

    def test_every_architecture_must_have_built(self):
        write_artifact(self.dir, "aarch64-linux")
        with self.assertRaisesRegex(release.ReleaseError, "split-x86_64"):
            release.read_builds(self.dir, COMMIT, PIN)

    def test_a_build_of_another_commit_or_pin_is_refused(self):
        for kwargs in ({"commit": "d" * 40}, {"pin": "e" * 40}):
            with self.subTest(**kwargs), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                write_artifact(directory, "aarch64-linux", **kwargs)
                write_artifact(directory, "x86_64-linux")
                with self.assertRaises(release.ReleaseError):
                    release.read_builds(directory, COMMIT, PIN)

    def test_a_release_tag_goes_with_items_to_publish(self):
        write_artifact(self.dir, "aarch64-linux", publish=[item(2)])
        write_artifact(self.dir, "x86_64-linux")
        with self.assertRaisesRegex(release.ReleaseError, "release tag"):
            release.read_builds(self.dir, COMMIT, PIN)


class CoverageTests(unittest.TestCase):
    ROGUIX = "https://roguix.example"

    def builds(self, *items):
        return {"aarch64-linux": {"package-closure.txt": list(items)}}

    def test_counts_where_each_item_is_served(self):
        asked = []

        def status(server, path):
            asked.append((server, path))
            return 200 if (server == release.BORDEAUX) == (path == item(1)) else 404
        served = release.coverage(self.builds(item(1), item(2)), self.ROGUIX, status)
        self.assertEqual(served, {"aarch64-linux": {"bordeaux": 1, "roguix": 1}})
        # roguix.frolow.dev is not asked about what bordeaux serves.
        self.assertNotIn((self.ROGUIX, item(1)), asked)

    def test_an_item_served_nowhere_stops_the_release(self):
        with self.assertRaisesRegex(release.ReleaseError, item(3)):
            release.coverage(self.builds(item(3)), self.ROGUIX,
                             lambda server, path: 404)


class ManifestTests(unittest.TestCase):
    def test_names_the_commit_its_builds_and_their_servers(self):
        builds = {"aarch64-linux": {"release": "aarch64-desktop-x",
                                    "publish.txt": [item(2)]},
                  "x86_64-linux": {"release": None, "publish.txt": []}}
        served = {"aarch64-linux": {"bordeaux": 5, "roguix": 2},
                  "x86_64-linux": {"bordeaux": 7, "roguix": 0}}
        ci_run = {"databaseId": 42, "url": "https://example/runs/42",
                  "headSha": "f" * 40}
        document = release.manifest(COMMIT, "a" * 40, PIN, ci_run, builds, served)
        self.assertEqual(document["channel-commit"], COMMIT)
        self.assertEqual(document["guix-commit"], PIN)
        self.assertEqual(document["ci"]["run-id"], 42)
        self.assertEqual(document["architectures"]["aarch64-linux"],
                         {"release": "aarch64-desktop-x", "published": 1,
                          "served-by-bordeaux": 5, "served-by-roguix": 2})
        self.assertIsNone(document["architectures"]["x86_64-linux"]["release"])
        json.dumps(document)


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
        self.git("commit", "--quiet", "-am", "Roguix from try-roguix x")
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
            self.assertIn(release.roguix_server(), result.stdout)
            self.assertEqual(os.listdir(tmp), [])


if __name__ == "__main__":
    unittest.main()
