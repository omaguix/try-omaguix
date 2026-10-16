"""Omaguix's substitute server and channel are named in (omaguix trust) only."""

from pathlib import Path
import re
import unittest

HERE = Path(__file__).parent
TRUST = HERE / "modules" / "omaguix" / "trust.scm"
ROOT = HERE.parent.parent


def record_values():
    """The string literals of %omaguix-trust: substitute URL, key file,
    channel URL, introduction and signer, in that order."""
    source = TRUST.read_text()
    body = source[source.index("(define %omaguix-trust"):]
    return re.findall(r'"([^"]*)"', body)


class TrustRecordTests(unittest.TestCase):
    def test_record_holds_the_published_values(self):
        substitute, key, channel, introduction, signer = record_values()
        self.assertEqual(substitute, "https://roguix.frolow.dev")
        self.assertTrue((TRUST.parent / key).is_file(), key)
        self.assertEqual(channel, "https://github.com/omaguix/omaguix-channel")
        self.assertRegex(introduction, r"^[0-9a-f]{40}$")
        self.assertRegex(signer.replace(" ", ""), r"^[0-9A-F]{40}$")

    def test_guest_code_names_them_nowhere_else(self):
        substitute, key, *channel = record_values()
        # The host and key file names also appear in comments and
        # messages; only their quoted forms are the trusted values.
        quoted = [f'"{substitute}"', f'"{key}"']
        for path in sorted(HERE.rglob("*")):
            if (not path.is_file() or path == TRUST
                    or path.name.startswith("test_")
                    or path.suffix in (".md", ".patch", ".pub")):
                continue
            text = path.read_text(errors="replace")
            for value in quoted + channel:
                self.assertFalse(value in text, f"{path}: {value}")

    def test_system_and_update_use_the_record(self):
        modules = HERE / "modules" / "omaguix"
        system = (modules / "system.scm").read_text()
        omarchy = (modules / "omarchy.scm").read_text()
        for accessor in ("omaguix-trust-substitute-url",
                         "omaguix-trust-substitute-key"):
            self.assertIn(f"({accessor} %omaguix-trust)", system)
        for accessor in ("omaguix-trust-channel-url",
                         "omaguix-trust-channel-introduction",
                         "omaguix-trust-channel-signer"):
            self.assertIn(f"({accessor} %omaguix-trust)", omarchy)

    def test_channel_decision_states_the_same_channel(self):
        _, _, channel, introduction, signer = record_values()
        decision = (ROOT / "docs" / "decisions"
                    / "0004-roguix-channel.md").read_text()
        for value in (channel, introduction, signer):
            self.assertIn(value, decision)


if __name__ == "__main__":
    unittest.main()
