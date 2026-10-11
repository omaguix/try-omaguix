"""omarchy-theme-set-store-modes.patch: a theme change replaces the current theme.

omarchy-theme-set stages the official theme in next-theme with `cp -r`,
generates configs into it, then swaps it in for current/theme with
`rm -rf` and `mv`. The tests run the staging and swap lines of the patch's
upstream ("-") and patched ("+") sides against a read-only theme, as Guix's
store holds it, and set a theme twice, as a theme change after the seed's
first theme-set does.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).parent
PATCH = HERE / "modules" / "roguix" / "omarchy-theme-set-store-modes.patch"


def staging_lines(side):
    """SIDE's lines that stage the theme or swap it in, in script order."""
    lines = []
    for line in PATCH.read_text().splitlines():
        if line[:1] not in (" ", side) or line.startswith(side * 3 + " "):
            continue
        line = line[1:]
        if line.split(" ", 1)[0] in ("cp", "chmod", "rm", "mv") and "THEME_PATH" in line:
            lines.append(line)
    return lines


def theme_set_script(side):
    """Stage, generate foot.ini as omarchy-theme-set-templates does, swap in."""
    lines = staging_lines(side)
    swap = next(i for i, line in enumerate(lines) if "CURRENT_THEME_PATH" in line)
    return "\n".join([
        'rm -rf "$NEXT_THEME_PATH"',
        'mkdir -p "$NEXT_THEME_PATH"',
        *lines[:swap],
        'echo "[colors-dark]" >"$NEXT_THEME_PATH/foot.ini"',
        *lines[swap:],
    ])


class ThemeSetTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(self.remove_root)
        store = self.root / "store" / "themes" / "tokyo-night"
        (store / "backgrounds").mkdir(parents=True)
        (store / "colors.toml").write_text('background = "#1a1b26"\n')
        (store / "backgrounds" / "1-quattro.jpg").write_bytes(b"jpg")
        for path in (store / "colors.toml", store / "backgrounds" / "1-quattro.jpg"):
            path.chmod(0o444)
        for path in (store / "backgrounds", store):
            path.chmod(0o555)
        self.current = self.root / "state" / "current"
        self.current.mkdir(parents=True)

    def remove_root(self):
        for path, dirs, _ in os.walk(self.root):
            for name in dirs:
                os.chmod(os.path.join(path, name), 0o755)
        shutil.rmtree(self.root)

    def theme_set(self, side):
        env = {
            "PATH": "/usr/bin:/bin",
            "OMARCHY_THEMES_PATH": str(self.root / "store" / "themes"),
            "THEME_NAME": "tokyo-night",
            "NEXT_THEME_PATH": str(self.current / "next-theme"),
            "CURRENT_THEME_PATH": str(self.current / "theme"),
        }
        subprocess.run(["bash", "-c", theme_set_script(side)], env=env,
                       capture_output=True, check=False)

    def theme_files(self):
        theme = self.current / "theme"
        return sorted(str(path.relative_to(theme)) for path in theme.rglob("*"))

    def test_second_theme_set_replaces_the_current_theme(self):
        expected = ["backgrounds", "backgrounds/1-quattro.jpg", "colors.toml", "foot.ini"]
        self.theme_set("+")
        self.assertEqual(self.theme_files(), expected)
        self.theme_set("+")
        self.assertEqual(self.theme_files(), expected)

    def test_theme_set_repairs_a_theme_staged_before_the_patch(self):
        self.theme_set("-")
        self.theme_set("+")
        self.assertEqual(self.theme_files(),
                         ["backgrounds", "backgrounds/1-quattro.jpg", "colors.toml", "foot.ini"])

    def test_upstream_loses_foot_ini_on_the_second_theme_set(self):
        # Upstream's bug, which the patch fixes.
        self.theme_set("-")
        self.theme_set("-")
        self.assertNotIn("foot.ini", self.theme_files())
        self.assertIn("next-theme/foot.ini", self.theme_files())


if __name__ == "__main__":
    unittest.main()
