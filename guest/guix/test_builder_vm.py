"""Contracts of builder-vm's export share; only --dry-run runs, no VM starts."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
BUILDER_VM = HERE / "builder-vm"
ROOT = HERE.parents[1]
DEFAULT_EXPORT = ROOT / ".build/guix-validation/export"


def dry_run(**env):
    clean = {k: v for k, v in os.environ.items() if not k.startswith("BUILDER_EXPORT")}
    return subprocess.run([str(BUILDER_VM), "--dry-run"], env=clean | env,
                          capture_output=True, text=True)


def export_share(stdout):
    shares = [arg for arg in stdout.split() if "mount_tag=export" in arg]
    assert len(shares) == 1, stdout
    return shares[0].split(",")


class ExportShareTests(unittest.TestCase):
    def test_default_share_is_the_checkouts_export_directory(self):
        result = dry_run()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"path={DEFAULT_EXPORT}", export_share(result.stdout))

    def test_set_directory_is_shared_as_export(self):
        with tempfile.TemporaryDirectory() as directory:
            result = dry_run(BUILDER_EXPORT=directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            share = export_share(result.stdout)
            self.assertIn(f"path={directory}", share)
            self.assertNotIn("readonly=on", share)

    def test_missing_directory_is_refused_and_not_created(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "volume/exports"
            result = dry_run(BUILDER_EXPORT=str(missing))
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("not an existing directory", result.stderr)
            self.assertFalse(missing.parent.exists())

    def test_relative_directory_is_refused(self):
        result = dry_run(BUILDER_EXPORT="exports")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not an absolute path", result.stderr)

    def test_read_only_directory_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            os.chmod(directory, 0o500)
            try:
                result = dry_run(BUILDER_EXPORT=directory)
            finally:
                os.chmod(directory, 0o700)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("not writable", result.stderr)

    def test_other_volume_is_required_when_asked(self):
        # A directory inside the checkout is on the checkout's volume.
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            result = dry_run(BUILDER_EXPORT=directory, BUILDER_EXPORT_OTHER_VOLUME="1")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("checkout's volume", result.stderr)
            self.assertEqual(dry_run(BUILDER_EXPORT=directory).returncode, 0)


if __name__ == "__main__":
    unittest.main()
