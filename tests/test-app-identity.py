#!/usr/bin/env python3
"""The app identity: one file per app, read the same by Make, bash and Python.

The default must reproduce Try Omaguix's installed contracts exactly; a
second identity must change every value without any of the first leaking
into the build scripts.
"""

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("app_identity", ROOT / "macos/apps/identity.py")
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)

# Today's values. Several are deliberately the pre-rename names: installed
# apps keep their VM, logs, grants, preferences and tag series under them.
DEFAULT = {
    "APP_NAME": "Try Omaguix",
    "DEVELOPMENT_APP_NAME": "Try Omaguix Dev",
    "BUNDLE_IDENTIFIER": "dev.tryomaguix.native",
    "DEVELOPMENT_BUNDLE_IDENTIFIER": "dev.tryomaguix.native.development",
    "APPLICATION_SUPPORT_DIRECTORY": "Try Omaguix",
    "LOGS_DIRECTORY": "Try Omaguix",
    "LEGACY_APP_NAMES": "",
    "DEVELOPMENT_CERTIFICATE": "Try Omaguix Development",
    "DEVELOPMENT_KEYCHAIN": "try-omaguix-development.keychain-db",
    "DEVELOPMENT_KEYCHAIN_PASSWORD": "try-omaguix/development-keychain-password",
    "RELEASE_TAG_PREFIX": "try-omaguix-v",
    "RELEASE_DMG": "TryOmaguix.dmg",
    "LEGACY_RELEASE_DMGS": "",
    "RELEASE_REPOSITORY": "omaguix/try-omaguix",
    "ICON": "TryOmaguix.svg",
    "NETWORK_HELPER_SERVICE": "dev.tryomaguix.network",
}

SECOND = {
    "APP_NAME": "Try Omabend",
    "DEVELOPMENT_APP_NAME": "Try Omabend Dev",
    "BUNDLE_IDENTIFIER": "dev.example.omabend",
    "DEVELOPMENT_BUNDLE_IDENTIFIER": "dev.example.omabend.development",
    "APPLICATION_SUPPORT_DIRECTORY": "Try Omabend Data",
    "LOGS_DIRECTORY": "Try Omabend Logs",
    # Older names, so the legacy paths stay covered: Try Omaguix has none.
    "LEGACY_APP_NAMES": "Try Omabend Old",
    "DEVELOPMENT_CERTIFICATE": "Try Omabend Development",
    "DEVELOPMENT_KEYCHAIN": "try-omabend-development.keychain-db",
    "DEVELOPMENT_KEYCHAIN_PASSWORD": "try-omabend/development-keychain-password",
    "RELEASE_TAG_PREFIX": "try-omabend-v",
    "RELEASE_DMG": "TryOmabend.dmg",
    "LEGACY_RELEASE_DMGS": "OldOmabend.dmg",
    "RELEASE_REPOSITORY": "example/try-omabend",
    "ICON": "TryOmabend.svg",
    # No bridged-networking helper: NAT only.
    "NETWORK_HELPER_SERVICE": "",
}

# Scripts that build, sign, release or clean the app: none may carry a value
# of the default identity outside comments.
SCRIPTS = ("Makefile", "macos/build-app.sh", "macos/release.sh",
           "macos/development-signing-identity.sh", "scripts/app_version.py",
           "scripts/build-cache.py", "macos/open-qemu-gpu.sh", "macos/package-dmg.sh",
           "macos/resize-vm-disk.sh", "macos/network-helper/build.sh",
           "macos/network-helper/build-daemon.sh", "macos/network-helper/client.c",
           "macos/Info.plist", "macos/network-helper/launch-daemon.plist")


def write_identity(path, values):
    path.write_text("# A second app.\n" + "".join(
        f"{key}={value}\n" for key, value in values.items()))
    return path


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="app-identity-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.second = write_identity(self.directory / "second.env", SECOND)

    def environment(self, path=None):
        environment = {k: v for k, v in os.environ.items()
                       if k != "APP_IDENTITY" and k not in DEFAULT}
        if path is not None:
            environment["APP_IDENTITY"] = str(path)
        return environment

    def make(self, path, *arguments):
        command = ["make", "--no-print-directory", "-C", str(ROOT), "-n", *arguments]
        if path is not None:
            command.append(f"APP_IDENTITY={path}")
        result = subprocess.run(command, capture_output=True, text=True,
                                env=self.environment())
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def shell(self, path):
        script = ('eval "$(python3 "$1" shell)" || exit 1\n'
                  'for key in ' + " ".join(DEFAULT) + '; do\n'
                  '  printf "%s=%s\\n" "$key" "${!key}"\n'
                  'done\n')
        result = subprocess.run(
            ["/bin/bash", "-c", script, "bash", str(ROOT / "macos/apps/identity.py")],
            capture_output=True, text=True, env=self.environment(path))
        self.assertEqual(result.returncode, 0, result.stderr)
        return dict(line.split("=", 1) for line in result.stdout.splitlines())

    def tag_prefix(self, path):
        result = subprocess.run(
            [sys.executable, "-c",
             "import sys; sys.path.insert(0, sys.argv[1]); import app_version; "
             "print(app_version.release_tag_prefix())", str(ROOT / "scripts")],
            capture_output=True, text=True, env=self.environment(path))
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_default_resolves_to_todays_exact_values(self):
        self.assertEqual(identity.DEFAULT, ROOT / "macos/apps/try-omaguix.env")
        self.assertEqual(identity.load(identity.DEFAULT), DEFAULT)
        self.assertEqual(self.shell(None), DEFAULT)
        self.assertEqual(self.tag_prefix(None), "try-omaguix-v")
        home = os.environ["HOME"]
        install = self.make(None, "install")
        self.assertIn(f'"{ROOT}/build/dev.noindex/Try Omaguix.app" '
                      f'"{home}/Applications/Try Omaguix Dev.app"', install)
        clean = self.make(None, "clean-all")
        self.assertIn("(Try Omaguix|Try Omaguix Dev)[.]app/Contents/",
                      clean)
        for path in (
            "Library/Application Support/Try Omaguix\"",
            "Library/Caches/dev.tryomaguix.native\"",
            "Library/Preferences/dev.tryomaguix.native.plist\"",
            "Library/Saved Application State/dev.tryomaguix.native.savedState\"",
            "Library/Caches/dev.tryomaguix.native.development\"",
            "Library/Preferences/dev.tryomaguix.native.development.plist\"",
            "Library/Saved Application State/dev.tryomaguix.native.development.savedState\"",
        ):
            self.assertIn(path, clean)

    def test_second_identity_changes_every_value_and_nothing_leaks(self):
        for key, value in DEFAULT.items():
            self.assertNotEqual(SECOND[key], value, key)
        self.assertEqual(identity.load(self.second), SECOND)
        self.assertEqual(self.shell(self.second), SECOND)
        self.assertEqual(self.tag_prefix(self.second), "try-omabend-v")
        home = os.environ["HOME"]
        install = self.make(self.second, "install")
        self.assertIn(f'"{ROOT}/build/dev.noindex/Try Omabend.app" '
                      f'"{home}/Applications/Try Omabend Dev.app"', install)
        clean = self.make(self.second, "clean-all")
        self.assertIn("(Try Omabend Old|Try Omabend|Try Omabend Dev)[.]app/Contents/", clean)
        self.assertIn("Library/Application Support/Try Omabend Data\"", clean)
        self.assertIn("Library/Caches/dev.example.omabend.development\"", clean)
        help_text = self.make(self.second, "help")
        for output in (install, clean, help_text):
            for value in DEFAULT.values():
                if value:
                    self.assertNotIn(value, output)

    def test_build_scripts_read_every_value_from_the_identity(self):
        for name in SCRIPTS:
            for number, line in enumerate((ROOT / name).read_text().splitlines(), 1):
                code = line.split("#", 1)[0] if not line.lstrip().startswith("#") else ""
                for value in DEFAULT.values():
                    if value:
                        self.assertNotIn(value, code, f"{name}:{number}")
        build = (ROOT / "macos/build-app.sh").read_text()
        # The identity reaches the bundle for the app and the launcher to read.
        self.assertIn('value["OmaguixApplicationSupportDirectory"] = sys.argv[4]', build)
        self.assertIn('value["OmaguixLogsDirectory"] = sys.argv[5]', build)
        self.assertIn('value["OmaguixApplicationName"] = sys.argv[6]', build)
        self.assertIn('value["OmaguixDevelopmentApplicationName"] = sys.argv[7]', build)
        self.assertIn('value["OmaguixNetworkHelperService"] = sys.argv[8]', build)
        self.assertIn('value["OmaguixReleaseRepository"] = sys.argv[10]', build)
        self.assertIn('value["OmaguixReleaseTagPrefix"] = sys.argv[11]', build)
        self.assertIn('value["OmaguixReleaseDMG"] = sys.argv[12]', build)
        self.assertIn('value["OmaguixLegacyReleaseDMGs"] = sys.argv[13]', build)
        self.assertIn('"$APPLICATION_SUPPORT_DIRECTORY" "$LOGS_DIRECTORY" "$APP_NAME" \\\n'
                      '  "$DEVELOPMENT_APP_NAME" "$NETWORK_HELPER_SERVICE" "$app_icon_name.icns" \\\n'
                      '  "$RELEASE_REPOSITORY" "$RELEASE_TAG_PREFIX" "$RELEASE_DMG" "$LEGACY_RELEASE_DMGS"',
                      build)

    def test_legacy_release_disk_images_may_be_one_several_or_none(self):
        for value in ("", "TryOmaguix.dmg", "TryOmaguix.dmg,Try.Old-1.dmg"):
            with self.subTest(value=value):
                path = write_identity(self.directory / "legacy.env",
                                      {**SECOND, "LEGACY_RELEASE_DMGS": value})
                self.assertEqual(identity.load(path)["LEGACY_RELEASE_DMGS"], value)

    def test_icon_lives_beside_the_identity_file(self):
        default_icon = identity.icon(DEFAULT, identity.DEFAULT)
        self.assertEqual(default_icon, ROOT / "macos/apps/TryOmaguix.svg")
        self.assertTrue(default_icon.is_file())
        self.assertEqual(identity.icon(SECOND, self.second), self.directory.resolve() / "TryOmabend.svg")
        result = subprocess.run(
            [sys.executable, str(ROOT / "macos/apps/identity.py"), "icon"],
            capture_output=True, text=True, env=self.environment(self.second))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.directory.resolve() / "TryOmabend.svg"))

    def test_invalid_identities_are_refused_everywhere(self):
        cases = {
            "missing key": {k: v for k, v in SECOND.items() if k != "LOGS_DIRECTORY"},
            "path in a directory name": {**SECOND, "APPLICATION_SUPPORT_DIRECTORY": "../Library"},
            "slash in a directory name": {**SECOND, "LOGS_DIRECTORY": "a/b"},
            "Make syntax": {**SECOND, "APP_NAME": "Try $(HOME)"},
            "quotes": {**SECOND, "APP_NAME": "'Try'"},
            "trailing space": {**SECOND, "APP_NAME": "Try Omabend "},
            "shared bundle identifier": {**SECOND, "DEVELOPMENT_BUNDLE_IDENTIFIER":
                                         SECOND["BUNDLE_IDENTIFIER"]},
            "empty name": {**SECOND, "APP_NAME": ""},
            "icon in another directory": {**SECOND, "ICON": "../TryOmabend.svg"},
            "icon not an SVG": {**SECOND, "ICON": "TryOmabend.png"},
            "invalid service": {**SECOND, "NETWORK_HELPER_SERVICE": "network"},
            "legacy disk image not a DMG": {**SECOND, "LEGACY_RELEASE_DMGS": "TryOmabend.zip"},
            "legacy disk image in a directory": {**SECOND, "LEGACY_RELEASE_DMGS": "old/TryOmabend.dmg"},
            "legacy disk images with an empty entry": {**SECOND, "LEGACY_RELEASE_DMGS":
                                                       "A.dmg,,B.dmg"},
            "legacy disk images with a trailing comma": {**SECOND, "LEGACY_RELEASE_DMGS": "A.dmg,"},
            "legacy disk images with a space": {**SECOND, "LEGACY_RELEASE_DMGS": "A.dmg, B.dmg"},
        }
        for case, values in cases.items():
            with self.subTest(case=case):
                path = write_identity(self.directory / "bad.env", values)
                with self.assertRaises(identity.IdentityError):
                    identity.load(path)
                result = subprocess.run(
                    ["make", "--no-print-directory", "-C", str(ROOT), "-n", "help",
                     f"APP_IDENTITY={path}"],
                    capture_output=True, text=True, env=self.environment())
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("app-identity:", result.stderr)
        path = self.directory / "unknown.env"
        path.write_text(self.second.read_text() + "EXTRA=1\n")
        with self.assertRaises(identity.IdentityError):
            identity.load(path)

    def refused(self, arguments, environment):
        result = subprocess.run(
            ["make", "--no-print-directory", "-C", str(ROOT), "-n", *arguments],
            capture_output=True, text=True, env=environment)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("app-identity:", result.stderr)
        self.assertEqual(result.stdout, "")
        return result.stderr

    def test_make_refuses_identity_values_from_outside_the_file(self):
        # A command-line value would beat the include, reach clean-all's
        # rm -rf and disagree with what the scripts read from the file.
        for key in DEFAULT:
            with self.subTest(key=key):
                stderr = self.refused(["clean-all", f"{key}=../.."], self.environment())
                self.assertIn(key, stderr)
        stderr = self.refused(["-e", "help"], {**self.environment(),
                                                "APPLICATION_SUPPORT_DIRECTORY": "x"})
        self.assertIn("APPLICATION_SUPPORT_DIRECTORY", stderr)
        # Without -e the file wins over the environment.
        result = subprocess.run(
            ["make", "--no-print-directory", "-C", str(ROOT), "-n", "help"],
            capture_output=True, text=True, env={**self.environment(), "APP_NAME": "x"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Try Omaguix — native", result.stdout)

    def test_empty_selection_is_refused_by_make_and_python(self):
        self.refused(["help", "APP_IDENTITY="], self.environment())
        self.refused(["help"], {**self.environment(), "APP_IDENTITY": ""})
        result = subprocess.run(
            [sys.executable, str(ROOT / "macos/apps/identity.py"), "check"],
            capture_output=True, text=True, env={**self.environment(), "APP_IDENTITY": ""})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("APP_IDENTITY is empty", result.stderr)
        # Unset selects the default in both.
        self.assertEqual(self.shell(None), DEFAULT)
        self.assertIn("Try Omaguix — native", self.make(None, "help"))

    def test_comment_continued_by_a_backslash_is_refused(self):
        # Make would read the next line as part of the comment.
        path = self.directory / "continued.env"
        lines = self.second.read_text().splitlines()
        lines.insert(1, "# continued \\")
        path.write_text("\n".join(lines) + "\n")
        with self.assertRaisesRegex(identity.IdentityError, "backslash"):
            identity.load(path)
        self.refused(["help", f"APP_IDENTITY={path}"], self.environment())


if __name__ == "__main__":
    unittest.main()
