"""Artifact layout and packaging contracts on small synthetic GPT disks."""

import argparse
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid
import zlib

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import artifact  # noqa: E402
import package  # noqa: E402

SECTORS = 8192  # 4 MiB
ROOT_FIRST = 4096


def gpt_disk(path, *, partitions=None, root_label=b"Guix_image", corrupt=None):
    """Write a disk shaped like `guix system image --image-type=efi-raw`."""
    last = SECTORS - 1
    last_usable = last - 1 - artifact.GPT_ENTRY_SECTORS
    if partitions is None:
        partitions = [
            (artifact.ESP_TYPE, artifact.ESP_FIRST_LBA, ROOT_FIRST - 1, "GNU-ESP"),
            (artifact.LINUX_FS_TYPE, ROOT_FIRST, last_usable, "Guix_image"),
        ]
    disk = bytearray(SECTORS * artifact.SECTOR)
    disk[446 + 4] = 0xEE
    disk[446 + 8:446 + 12] = struct.pack("<I", 1)
    disk[510:512] = b"\x55\xaa"

    entries = bytearray(artifact.GPT_ENTRIES * artifact.GPT_ENTRY_SIZE)
    for index, (kind, first, end, name) in enumerate(partitions):
        entry = (kind.bytes_le + uuid.uuid4().bytes_le
                 + struct.pack("<QQQ", first, end, 0)
                 + name.encode("utf-16-le").ljust(72, b"\0"))
        entries[index * 128:(index + 1) * 128] = entry
    disk_guid = uuid.uuid4().bytes_le

    def header(current, backup, entries_lba):
        fields = [b"EFI PART", 0x10000, 92, 0, 0, current, backup,
                  2 + artifact.GPT_ENTRY_SECTORS, last_usable, disk_guid,
                  entries_lba, 128, 128, zlib.crc32(entries)]
        raw = struct.pack("<8sIIIIQQQQ16sQIII", *fields)
        fields[3] = zlib.crc32(raw)
        return struct.pack("<8sIIIIQQQQ16sQIII", *fields)

    backup_entries = last - artifact.GPT_ENTRY_SECTORS
    disk[512:604] = header(1, last, 2)
    disk[1024:1024 + len(entries)] = entries
    disk[backup_entries * 512:backup_entries * 512 + len(entries)] = entries
    disk[last * 512:last * 512 + 92] = header(last, 1, backup_entries)

    esp = artifact.ESP_FIRST_LBA * 512
    disk[esp + 0x36:esp + 0x3e] = b"FAT16   "
    disk[esp + 510:esp + 512] = b"\x55\xaa"
    superblock = ROOT_FIRST * 512 + 1024
    disk[superblock + 0x04:superblock + 0x08] = struct.pack("<I", 1024)  # 1 KiB blocks
    disk[superblock + 0x38:superblock + 0x3a] = b"\x53\xef"
    disk[superblock + 0x68:superblock + 0x78] = uuid.uuid4().bytes
    disk[superblock + 0x78:superblock + 0x88] = root_label.ljust(16, b"\0")
    if corrupt is not None:
        disk[corrupt] ^= 0xFF
    path.write_bytes(disk)
    return path


class InspectDiskTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "disk.raw"

    def test_accepts_the_guix_efi_layout(self):
        layout = artifact.inspect_disk(gpt_disk(self.path))
        self.assertEqual(layout["bytes"], SECTORS * 512)
        esp, root = layout["partitions"]
        self.assertEqual((esp["role"], esp["fileSystem"], esp["firstLBA"]), ("esp", "vfat", 2048))
        self.assertEqual((root["role"], root["fileSystemLabel"]), ("root", "Guix_image"))
        self.assertEqual(root["lastLBA"], SECTORS - 2 - artifact.GPT_ENTRY_SECTORS)

    def test_rejects_corruption_and_foreign_layouts(self):
        last_usable = SECTORS - 2 - artifact.GPT_ENTRY_SECTORS
        cases = {
            "protective MBR": {"corrupt": 510},
            "primary header CRC": {"corrupt": 512 + 40},
            "partition array CRC": {"corrupt": 1024 + 40},
            "backup header": {"corrupt": (SECTORS - 1) * 512 + 40},
            "root label": {"root_label": b"omarchy"},
            "no ext4": {"corrupt": ROOT_FIRST * 512 + 1024 + 0x38},
            "no FAT": {"corrupt": 2048 * 512 + 0x36},
            "third partition": {"partitions": [
                (artifact.ESP_TYPE, 2048, 3071, "GNU-ESP"),
                (artifact.LINUX_FS_TYPE, ROOT_FIRST, last_usable - 8, "Guix_image"),
                (artifact.LINUX_FS_TYPE, last_usable - 7, last_usable, "extra")]},
            "swapped types": {"partitions": [
                (artifact.LINUX_FS_TYPE, 2048, ROOT_FIRST - 1, "GNU-ESP"),
                (artifact.ESP_TYPE, ROOT_FIRST, last_usable, "Guix_image")]},
            "outside usable area": {"partitions": [
                (artifact.ESP_TYPE, 2048, ROOT_FIRST - 1, "GNU-ESP"),
                (artifact.LINUX_FS_TYPE, ROOT_FIRST, last_usable + 1, "Guix_image")]},
        }
        for name, options in cases.items():
            with self.subTest(name):
                gpt_disk(self.path, **options)
                with self.assertRaises(artifact.ArtifactError):
                    artifact.inspect_disk(self.path)

    def test_rejects_truncated_image_missing_its_backup_gpt(self):
        gpt_disk(self.path)
        with open(self.path, "r+b") as stream:
            stream.truncate((SECTORS - 1) * 512)
        with self.assertRaises(artifact.ArtifactError):
            artifact.inspect_disk(self.path)


def git(directory, *arguments):
    return subprocess.run(["git", "-C", str(directory), *arguments], check=True,
                          capture_output=True, text=True,
                          env=package.builder.git_environment()).stdout


def guest_sources(root):
    """Another app's guest in a Git repository: a system file and a load path."""
    git(root, "init", "-q")
    system = root / "other.scm"
    system.write_text("(use-modules (other system))\n")
    load_path = root / "lib"
    (load_path / "other/data").mkdir(parents=True)
    (load_path / "other/system.scm").write_text("(define-module (other system))\n")
    (load_path / "other/data/seed").write_text("seed\n")
    (root / ".gitignore").write_text("__pycache__/\n.DS_Store\n")
    git(root, "add", ".")
    return system, load_path


class BuildInputsTests(unittest.TestCase):
    """systemFilesSHA256 covers what `guix system image` reads (build.py)."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.system, self.load_path = guest_sources(self.root)

    def digest(self):
        return package.system_files_sha256(self.system, self.load_path)

    def test_default_inputs_are_the_system_file_and_its_tracked_load_path(self):
        builder = package.builder
        self.assertEqual((builder.SYSTEM, builder.LOAD_PATH), (HERE / "system.scm", HERE / "modules"))
        output = io.StringIO()
        args = argparse.Namespace(source=HERE, output=Path("/nonexistent/image.raw"),
                                  dry_run=True, check=False,
                                  system=builder.SYSTEM, load_path=builder.LOAD_PATH)
        with patch.object(builder.subprocess, "check_output",
                          side_effect=[builder.COMMIT, "", "a" * 40]), \
                contextlib.redirect_stdout(output):
            builder.build(args)
        command = output.getvalue().splitlines()[-1]
        self.assertIn(f"--load-path={HERE / 'modules'} ", command)
        self.assertTrue(command.endswith(f" {HERE / 'system.scm'}"))
        tracked = git(HERE / "modules", "ls-files", "-z", "--", ".").split("\0")
        self.assertEqual(package.builder.inputs(),
                         {"system.scm": HERE / "system.scm",
                          **{"modules/" + name: HERE / "modules" / name
                             for name in sorted(tracked) if name}})
        # Files in subdirectories, which modules read with local-file, count.
        self.assertIn("modules/roguix/settings/roguix-settings", package.builder.inputs())
        self.assertIn("modules/roguix/battery-module/Makefile", package.builder.inputs())

    def test_digest_follows_every_input_of_the_image_being_packaged(self):
        digest = self.digest()
        self.assertNotEqual(digest, package.system_files_sha256())
        self.assertEqual(digest, self.digest())
        seed = self.load_path / "other/data/seed"

        def add():
            (self.load_path / "other/new.scm").write_text("x\n")
            git(self.root, "add", "lib/other/new.scm")

        for name, change in {
            "system file": lambda: self.system.write_text("changed\n"),
            "nested file": lambda: seed.write_text("x\n"),
            "added file": add,
            "renamed file": lambda: git(self.root, "mv", "lib/other/data/seed",
                                        "lib/other/data/seed2"),
            "executable bit": lambda: (self.load_path / "other/system.scm").chmod(0o755),
            "system file's executable bit": lambda: self.system.chmod(0o755),
        }.items():
            with self.subTest(name):
                before = self.digest()
                change()
                self.assertNotEqual(self.digest(), before)

    def test_ignored_files_are_not_inputs(self):
        before = self.digest()
        (self.load_path / "other/__pycache__").mkdir()
        (self.load_path / "other/__pycache__/system.cpython.pyc").write_text("junk\n")
        (self.load_path / ".DS_Store").write_text("junk\n")
        self.assertEqual(self.digest(), before)
        self.assertNotIn("lib/.DS_Store", package.builder.inputs(self.system, self.load_path))

    def test_untracked_file_is_refused(self):
        (self.load_path / "other/stray.scm").write_text("x\n")
        with self.assertRaisesRegex(artifact.ArtifactError, "untracked file"):
            self.digest()

    def test_symlinked_input_is_refused(self):
        (self.load_path / "other/link").symlink_to(self.system)
        git(self.root, "add", "lib/other/link")
        with self.assertRaises(artifact.ArtifactError):
            self.digest()

    def test_missing_or_symlinked_roots_are_refused(self):
        link = self.root / "link"
        for name, (system, load_path) in {
            "missing system file": (self.root / "missing.scm", self.load_path),
            "missing load path": (self.system, self.root / "missing"),
            "load path outside Git": (self.system, Path(tempfile.mkdtemp(dir=self.root.parent))),
            "symlinked system file": (link.with_suffix(".scm"), self.load_path),
            "symlinked load path": (self.system, link),
        }.items():
            with self.subTest(name):
                if name == "symlinked system file":
                    link.with_suffix(".scm").symlink_to(self.system)
                if name == "symlinked load path":
                    link.symlink_to(self.load_path)
                if name == "load path outside Git":
                    self.addCleanup(shutil.rmtree, load_path)
                with self.assertRaises(artifact.ArtifactError):
                    package.system_files_sha256(system, load_path)

    def test_deleted_tracked_file_is_refused(self):
        (self.load_path / "other/data/seed").unlink()
        with self.assertRaises(artifact.ArtifactError):
            self.digest()


@unittest.skipUnless(shutil.which("zstd") or package.ZSTD.is_file(), "needs zstd")
class PackageTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.zstd = package.ZSTD if package.ZSTD.is_file() else Path(shutil.which("zstd"))
        self.image = gpt_disk(self.root / "image.raw")
        self.output = self.root / "build/guix"

    def packaged(self, credentials="first-boot"):
        return package.package(self.image, self.output, self.zstd, credentials)

    def test_credentials_policies(self):
        self.assertEqual(artifact.CREDENTIALS, {"first-boot", "preset"})
        manifest = self.packaged("preset")
        self.assertEqual(manifest["guest"]["credentials"], "preset")
        self.assertEqual(artifact.validate_artifacts(self.output, self.zstd), manifest)
        layout = artifact.inspect_disk(self.image)
        with self.assertRaises(artifact.ArtifactError):
            artifact.manifest_for(layout, "0" * 64, self.image, "0" * 40, "0" * 64, "none")
        # Another policy does not relax the layout checks.
        for options in ({"root_label": b"omarchy"}, {"corrupt": 512 + 40}):
            for credentials in sorted(artifact.CREDENTIALS):
                with self.subTest(credentials=credentials, **options):
                    image = gpt_disk(self.root / "bad.raw", **options)
                    with self.assertRaises(artifact.ArtifactError):
                        package.package(image, self.root / f"bad-{credentials}",
                                        self.zstd, credentials)
                    self.assertFalse(os.path.lexists(self.root / f"bad-{credentials}"))

    def test_records_the_inputs_of_the_image_being_packaged(self):
        sources = self.root / "sources"
        sources.mkdir()
        system, load_path = guest_sources(sources)
        manifest = package.package(self.image, self.output, self.zstd, "preset",
                                   system, load_path)
        self.assertEqual(manifest["source"]["systemFilesSHA256"],
                         package.system_files_sha256(system, load_path))

    def test_round_trip_records_layout_source_and_checksums(self):
        manifest = self.packaged()
        self.assertEqual(sorted(p.name for p in self.output.iterdir()), sorted(artifact.FILES))
        self.assertEqual(artifact.validate_artifacts(self.output, self.zstd), manifest)
        self.assertEqual(manifest["disk"]["sha256"], artifact.sha256_file(self.image))
        self.assertEqual(manifest["bootABI"], "uefi-gpt-v1")
        self.assertEqual(manifest["source"]["guixCommit"], package.guix_commit())
        self.assertEqual(manifest["source"]["systemFilesSHA256"], package.system_files_sha256())
        self.assertEqual(manifest["guest"]["credentials"], "first-boot")
        self.assertEqual([p for p in self.root.iterdir() if p.name.startswith(".guix-package")], [])

    def test_launch_record_matches_the_launcher_contract(self):
        manifest = self.packaged()
        fields = artifact.launch_record(self.output).split("\t")
        self.assertEqual(len(fields), 6)
        identity, raw_sha, raw_bytes, compressed_bytes, working_bytes, locales = fields
        self.assertEqual(locales, ",".join(artifact.LOCALES))
        self.assertEqual(manifest["guest"]["locales"], list(artifact.LOCALES))
        self.assertEqual(identity, artifact.sha256_file(self.output / artifact.MANIFEST))
        self.assertEqual((raw_sha, int(raw_bytes), int(compressed_bytes)),
                         (manifest["disk"]["sha256"], manifest["disk"]["bytes"],
                          manifest["disk"]["compressedBytes"]))
        self.assertEqual(int(working_bytes), artifact.WORKING_DISK_BYTES)
        import subprocess
        result = subprocess.run([sys.executable, str(HERE / "artifact.py"), "launch-record",
                                 str(self.output)], capture_output=True, text=True)
        self.assertEqual((result.returncode, result.stdout), (0, "\t".join(fields) + "\n"))
        (self.output / artifact.SUMS).chmod(0o644)
        (self.output / artifact.SUMS).write_text("tampered\n")
        result = subprocess.run([sys.executable, str(HERE / "artifact.py"), "launch-record",
                                 str(self.output)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_existing_output_is_never_replaced(self):
        self.output.mkdir(parents=True)
        with self.assertRaises(artifact.ArtifactError):
            self.packaged()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_invalid_image_leaves_no_output(self):
        gpt_disk(self.image, corrupt=512 + 40)
        with self.assertRaises(artifact.ArtifactError):
            self.packaged()
        self.assertFalse(self.output.parent.exists() and any(self.output.parent.iterdir()))

    def test_tampering_is_detected(self):
        self.packaged()
        for entry in self.output.iterdir():
            entry.chmod(0o644)
        manifest_path = self.output / artifact.MANIFEST
        original = manifest_path.read_text()

        def restore():
            manifest_path.write_text(original)
            (self.output / artifact.SUMS).write_text(artifact.sums_text(self.output))

        for name, change in {
            "extra file": lambda: (self.output / "notes.txt").write_text("x"),
            "sums": lambda: (self.output / artifact.SUMS).write_text("0" * 64 + "  disk.raw.zst\n"),
            "unknown key": lambda: manifest_path.write_text(
                artifact.canonical_json(dict(json.loads(original), extra=1))),
            "foreign kind": lambda: manifest_path.write_text(
                artifact.canonical_json(dict(json.loads(original), kind="try-omarchy-guest-artifacts"))),
            "non-canonical": lambda: manifest_path.write_text(json.dumps(json.loads(original))),
            "credentials": lambda: manifest_path.write_text(artifact.canonical_json(
                json.loads(original) | {"guest": dict(json.loads(original)["guest"], credentials="none")})),
        }.items():
            with self.subTest(name):
                change()
                if name not in ("extra file", "sums"):
                    (self.output / artifact.SUMS).write_text(artifact.sums_text(self.output))
                with self.assertRaises((artifact.ArtifactError, ValueError)):
                    artifact.validate_artifacts(self.output)
                (self.output / "notes.txt").unlink(missing_ok=True)
                restore()
        artifact.validate_artifacts(self.output)

    def test_raw_disk_mismatch_is_detected_by_full_validation(self):
        manifest = self.packaged()
        for entry in self.output.iterdir():
            entry.chmod(0o644)
        manifest["disk"]["sha256"] = "0" * 64
        (self.output / artifact.MANIFEST).write_text(artifact.canonical_json(manifest))
        (self.output / artifact.SUMS).write_text(artifact.sums_text(self.output))
        artifact.validate_artifacts(self.output)
        with self.assertRaises(artifact.ArtifactError):
            artifact.validate_artifacts(self.output, self.zstd)


if __name__ == "__main__":
    unittest.main()
