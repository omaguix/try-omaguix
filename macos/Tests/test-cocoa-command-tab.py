#!/usr/bin/env python3
"""Feed recorded modifier sequences to the patched Command-Tab hand-back."""
import hashlib
import platform
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / 'macos/patches/qemu-cocoa-command-tab.patch'
DIAGNOSTICS = ROOT / 'macos/patches/qemu-cocoa-full-grab-diagnostics.patch'


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def added(patch):
    return '\n'.join(line[1:] for line in patch.read_text().splitlines()
                     if line.startswith(('+', ' ')) and not line.startswith('+++'))


class CommandTabTests(unittest.TestCase):
    def test_build_uses_verified_patches(self):
        builder = (ROOT / 'macos/build-qemu-gpu-runtime.sh').read_text()
        for name, patch in (('command_tab', PATCH),
                            ('full_grab_diagnostics', DIAGNOSTICS)):
            digest = hashlib.sha256(patch.read_bytes()).hexdigest()
            self.assertIn(f'{name}_patch_sha256={digest}', builder)

    @unittest.skipUnless(platform.system() == 'Darwin', 'requires CoreGraphics')
    def test_recorded_sequences(self):
        harness = (ROOT / 'macos/Tests/cocoa-command-tab-harness.c').read_text()
        harness = harness.replace('/* TRACK */', block(
            added(PATCH), 'static bool trackCommandTabRelease('))
        harness = harness.replace('/* ROUTE */', block(
            added(PATCH), 'static bool commandTabGoesToMacOS('))
        harness = harness.replace('/* LOG */', block(
            added(DIAGNOSTICS), 'static void cocoa_tap_log_command_tab_release('))
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'test.c'
            binary = Path(directory) / 'test'
            source.write_text(harness)
            subprocess.run(['xcrun', 'clang', '-Werror', '-framework',
                            'ApplicationServices', str(source), '-o', str(binary)],
                           check=True)
            result = subprocess.run([str(binary)], check=True,
                                    capture_output=True, text=True)
        log = result.stderr.splitlines()
        self.assertIn('[event-tap] Command-Tab hand-back armed by Control-Option', log)
        self.assertIn('[event-tap] Command-Tab hand-back released: '
                      'Command-Tab goes to macOS', log)
        self.assertIn('[event-tap] Command-Tab hand-back disarmed: a key was pressed', log)
        self.assertIn('[event-tap] Command-Tab hand-back disarmed: '
                      'another modifier joined Control-Option', log)
        # Modifier changes name their key code and flags; typed keys never do.
        self.assertIn('[event-tap] Command-Tab hand-back: modifier key code 58, '
                      'flags 0xc0121', log)
        self.assertFalse([line for line in log if 'key code 17' in line])


if __name__ == '__main__':
    unittest.main()
