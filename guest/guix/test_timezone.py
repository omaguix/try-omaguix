"""omaguix-timezone: following the Mac's zone, fixed choices and resuming."""

import base64
import importlib.machinery
import importlib.util
import os
import re
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).parent
path = HERE / "modules" / "omaguix" / "timezone"
loader = importlib.machinery.SourceFileLoader("omaguix_timezone", str(path))
spec = importlib.util.spec_from_loader("omaguix_timezone", loader)
timezone = importlib.util.module_from_spec(spec)
loader.exec_module(timezone)

setup_path = HERE / "modules" / "omaguix" / "omaguix-setup"
setup_loader = importlib.machinery.SourceFileLoader("omaguix_setup", str(setup_path))
setup = importlib.util.module_from_spec(
    importlib.util.spec_from_loader("omaguix_setup", setup_loader))
setup_loader.exec_module(setup)


class TimezoneTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.zoneinfo = self.root / "zoneinfo"
        for zone in ("Europe/Warsaw", "Asia/Tokyo", "America/New_York", "UTC"):
            (self.zoneinfo / zone).parent.mkdir(parents=True, exist_ok=True)
            (self.zoneinfo / zone).write_text(zone)
        self.localtime = self.root / "localtime"
        self.settings = self.root / "machine-settings.scm"

    def write_settings(self, zone, follows):
        """The settings file exactly as omaguix-setup writes it."""
        self.settings.write_text(setup.machine_settings(
            "studio", zone, follows, setup.LAYOUTS[0], "ko_KR.utf8"))

    def values(self):
        return dict(timezone.read_settings(str(self.settings)))

    def follow(self, zone):
        return timezone.follow(zone, str(self.settings), str(self.localtime),
                               str(self.zoneinfo))

    def select(self, choice, latest=None):
        return timezone.select(choice, str(self.settings), str(self.localtime),
                               str(self.zoneinfo), latest)

    def current(self):
        return os.path.relpath(os.readlink(self.localtime), self.zoneinfo)

    def test_following_applies_each_mac_change_and_records_it(self):
        self.write_settings("Europe/Warsaw", True)
        self.assertTrue(self.follow("Asia/Tokyo"))
        self.assertEqual(self.current(), "Asia/Tokyo")
        self.assertEqual(self.values()["timezone"], "Asia/Tokyo")
        # The host repeats its zone every five seconds: nothing changes.
        self.assertFalse(self.follow("Asia/Tokyo"))
        self.assertTrue(self.follow("America/New_York"))
        self.assertEqual(self.current(), "America/New_York")

    def test_other_settings_survive_a_change_in_order(self):
        self.write_settings("Europe/Warsaw", True)
        before = timezone.read_settings(str(self.settings))
        self.follow("Asia/Tokyo")
        after = timezone.read_settings(str(self.settings))
        self.assertEqual([key for key, _ in after], [key for key, _ in before])
        self.assertEqual({k: v for k, v in after if k != "timezone"},
                         {k: v for k, v in before if k != "timezone"})
        self.assertEqual(self.settings.read_text().splitlines()[0],
                         ";; Written by omaguix-setup; read by /etc/config.scm and at boot.")

    def test_a_fixed_zone_ignores_the_mac(self):
        self.write_settings("Europe/Warsaw", False)
        self.assertFalse(self.follow("Asia/Tokyo"))
        self.assertFalse(self.localtime.exists())
        self.assertEqual(self.values()["timezone"], "Europe/Warsaw")

    def test_settings_from_before_following_keep_their_zone(self):
        self.settings.write_text(';; Written by omaguix-setup.\n((host-name . "studio")\n'
                                 ' (timezone . "Europe/Warsaw"))\n')
        self.assertFalse(self.follow("Asia/Tokyo"))
        self.assertEqual(self.values(), {"host-name": "studio", "timezone": "Europe/Warsaw"})

    def test_no_settings_before_the_setup_means_no_change(self):
        self.assertFalse(self.follow("Asia/Tokyo"))
        self.assertFalse(self.settings.exists())
        with self.assertRaises(ValueError):
            self.select("Asia/Tokyo")

    def test_choosing_a_zone_stops_following_even_the_macs_own(self):
        self.write_settings("Asia/Tokyo", True)
        self.follow("Asia/Tokyo")
        self.select("Asia/Tokyo")
        self.assertEqual(self.values()["timezone-follows-mac"], "no")
        self.assertFalse(self.follow("Europe/Warsaw"))
        self.assertEqual(self.current(), "Asia/Tokyo")

    def test_same_as_macos_resumes_from_the_latest_mac_zone(self):
        self.write_settings("Europe/Warsaw", False)
        self.assertTrue(self.select(timezone.FOLLOW_MAC_LABEL, latest="Asia/Tokyo"))
        self.assertEqual(self.current(), "Asia/Tokyo")
        self.assertEqual(self.values()["timezone"], "Asia/Tokyo")
        self.assertEqual(self.values()["timezone-follows-mac"], "yes")
        self.assertTrue(self.follow("America/New_York"))

    def test_settings_written_by_the_service_are_read_by_the_setup_reader(self):
        self.write_settings("Europe/Warsaw", True)
        self.select("America/New_York")
        # The Guile readers match ((symbol . "string") ...); the setup's
        # field regular expression stands in for them here.
        text = self.settings.read_text()
        self.assertEqual(text, setup.machine_settings(
            "studio", "America/New_York", False, setup.LAYOUTS[0], "ko_KR.utf8"))

    def test_invalid_zones_change_nothing(self):
        self.write_settings("Europe/Warsaw", False)
        before = self.settings.read_text()
        for zone in ("../../etc/passwd", "Mars/Base", "", "Europe//Warsaw", "a b"):
            with self.assertRaises(ValueError):
                self.select(zone)
            with self.assertRaises(ValueError):
                self.follow(zone)
        self.assertEqual(self.settings.read_text(), before)
        self.assertFalse(self.localtime.exists())

    def test_resuming_needs_a_zone_from_the_mac(self):
        self.write_settings("Europe/Warsaw", False)
        original = timezone.HOST_ZONE, timezone.HOST_SETTINGS
        timezone.HOST_ZONE = str(self.root / "no-host-zone")
        timezone.HOST_SETTINGS = str(self.root / "no-host-settings")
        self.addCleanup(lambda: (setattr(timezone, "HOST_ZONE", original[0]),
                                 setattr(timezone, "HOST_SETTINGS", original[1])))
        with self.assertRaises(ValueError):
            self.select(timezone.FOLLOW_MAC_LABEL)

    def test_host_zone_prefers_the_latest_message_over_the_launch_hint(self):
        hint = base64.urlsafe_b64encode(b"Europe/Warsaw").decode().rstrip("=")
        settings = self.root / "host-settings"
        settings.write_text(f"omarchy.qemu_virgl=1 tryomarchy.timezone={hint}\n")
        latest = self.root / "host-timezone"
        zoneinfo = str(self.zoneinfo)
        self.assertEqual(timezone.host_zone(str(latest), str(settings), zoneinfo),
                         "Europe/Warsaw")
        timezone.record_host_zone("Asia/Tokyo", str(latest))
        self.assertEqual(timezone.host_zone(str(latest), str(settings), zoneinfo),
                         "Asia/Tokyo")
        latest.write_text("Mars/Base\n")
        self.assertIsNone(timezone.host_zone(str(latest), str(settings), zoneinfo))

    def test_host_messages_are_exactly_the_bridge_format(self):
        original = timezone.ZONEINFO
        timezone.ZONEINFO = str(self.zoneinfo)
        self.addCleanup(setattr, timezone, "ZONEINFO", original)
        self.assertEqual(timezone.message_zone(b'{"type":"timezone","zone":"Asia/Tokyo"}\n'),
                         "Asia/Tokyo")
        for line in (b'{"type":"timezone","zone":"Asia/Tokyo"}',
                     b'{"type":"battery","zone":"Asia/Tokyo"}\n',
                     b'{"type":"timezone","zone":"Asia/Tokyo","x":1}\n',
                     b'{"type":"timezone","zone":"../../etc/shadow"}\n',
                     b'["timezone"]\n', b'not json\n',
                     b'{"type":"timezone","zone":"' + b"A" * 5000 + b'"}\n'):
            with self.assertRaises(ValueError):
                timezone.message_zone(line)

    def test_the_menu_lists_the_setups_zones(self):
        self.assertEqual(timezone.zones(str(self.zoneinfo)),
                         setup.zones(str(self.zoneinfo)))


class MenuAndSudoTests(unittest.TestCase):
    """The pieces of omarchy.scm and system.scm that must agree."""

    COMMAND = "/run/current-system/profile/bin/omaguix-timezone"

    def sudoers_rule(self):
        system = (HERE / "modules" / "omaguix" / "system.scm").read_text()
        block = system[system.index("(sudoers-file"):]
        block = block[:block.index("\n\n")]
        return "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', block)[1:])

    def test_menu_runs_the_command_sudoers_allows(self):
        omarchy = (HERE / "modules" / "omaguix" / "omarchy.scm").read_text()
        self.assertIn(f"sudo -n {self.COMMAND} --select", omarchy)
        self.assertTrue(self.sudoers_rule().startswith(
            f"%wheel ALL=(root) NOPASSWD: {self.COMMAND} ^--select "))

    def test_sudoers_allows_every_menu_choice_and_nothing_else(self):
        rule = self.sudoers_rule()
        self.assertTrue(rule.endswith("$\\n"), rule)
        pattern = rule[rule.index("^"):-len("\\n")]
        for choice in (timezone.FOLLOW_MAC_LABEL, "UTC", "Asia/Tokyo",
                       "America/Argentina/Buenos_Aires", "Etc/GMT+1"):
            self.assertTrue(re.fullmatch(pattern, f"--select {choice}"), choice)
        for choice in ("../../etc/shadow", "Asia/../../x", "Asia/Tokyo extra",
                       "Same as macOS; id", "-x", ""):
            self.assertFalse(re.fullmatch(pattern, f"--select {choice}"), choice)


if __name__ == "__main__":
    unittest.main()
