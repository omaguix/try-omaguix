"""omarchy-theme-bg-utf8.patch: the background's name, decoded as UTF-8.

The patch's removed line is upstream's perl, which title-cases bytes; its
added line decodes the name as UTF-8 first. Each test runs a line with
BACKGROUND_PATH set, in a UTF-8 and in the C locale. Needs perl with Encode.
"""

from pathlib import Path
import shutil
import subprocess
import unittest

HERE = Path(__file__).parent
PATCH = HERE / "modules" / "omaguix" / "omarchy-theme-bg-utf8.patch"


def command(side):
    """The patch's one added ("+") or removed ("-") script line."""
    lines = [line[1:] for line in PATCH.read_text().splitlines()
             if line[:1] == side and not line.startswith((side * 3 + " "))]
    assert len(lines) == 1, lines
    return lines[0]


def title(side, name, locale="en_US.UTF-8"):
    """Run SIDE's line for a background file NAME; return (stdout, stderr)."""
    path = b"/home/guest/.config/omarchy/backgrounds/" + (
        name if isinstance(name, bytes) else name.encode())
    result = subprocess.run(
        ["bash", "-c", "set -euo pipefail\nBACKGROUND_PATH=$1\n" + command(side),
         "title", path],
        capture_output=True, env={"LC_ALL": locale, "PATH": "/usr/bin:/bin"})
    return result.stdout, result.stderr


HAS_PERL = shutil.which("perl") is not None and subprocess.run(
    ["perl", "-MEncode", "-e", "1"], capture_output=True).returncode == 0


@unittest.skipUnless(HAS_PERL, "needs perl with Encode")
class BackgroundNameTests(unittest.TestCase):
    ASCII = [
        "1-tokyo-night.png",
        "02-kanagawa-wave.jpg",
        "x.tar.gz",
        "noext",
        "trailing.",
        "under_score-name.webp",
        "10-a--b.jpg",
        "3d-render.png",
    ]

    def test_ascii_names_match_upstream(self):
        for locale in ("en_US.UTF-8", "C"):
            for name in self.ASCII:
                with self.subTest(locale=locale, name=name):
                    self.assertEqual(title("+", name, locale), title("-", name, locale))

    def test_accented_names_are_title_cased_by_letter(self):
        cases = {
            "02-über-städte.jpg": "Über Städte",
            "café-au-lait.png": "Café Au Lait",
            "5-élan-vital.jpg": "Élan Vital",
            "台北-night.jpg": "台北 Night",
        }
        for locale in ("en_US.UTF-8", "C"):
            for name, expected in cases.items():
                with self.subTest(locale=locale, name=name):
                    self.assertEqual(title("+", name, locale), (expected.encode(), b""))
        # Upstream's bug, which the patch fixes.
        self.assertEqual(title("-", "02-über-städte.jpg")[0], "üBer StäDte".encode())

    def test_bytes_that_are_not_utf8_still_give_a_name(self):
        out, err = title("+", b"bad-\xff\xfe-name.jpg", "C")
        self.assertEqual((out, err), ("Bad �� Name".encode(), b""))


if __name__ == "__main__":
    unittest.main()
