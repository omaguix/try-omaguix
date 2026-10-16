"""omaguix-update: release checks, the descendant check and its cursor,
same-pin updates and moves to another Guix.

The script is the `omaguix-update' shim in modules/omaguix/omarchy.scm; it is
extracted from there and run against a local Git channel, with stand-ins for
guix, df and uname.
"""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

OMARCHY = Path(__file__).with_name("modules") / "omaguix" / "omarchy.scm"
OLD_PIN = "7e74121a40a8308166e328a23647cf6f3768e6c8"
NEW_PIN = "84ff1865b81d8a56eec5b4015faa5787d024f9f1"
# The commit CI made of NEW_PIN plus guix-skip-forward-check.patch, which the
# release's Guix reports in `guix describe'.
PATCHED = "5a7c4e0d1f2b3a4c5d6e7f8091a2b3c4d5e6f708"
HASH = "0123456789abcdfghijklmnpqrsvwxyz"


def scheme_string(text, start):
    """Return the Scheme string literal at TEXT[START] and the index after it."""
    assert text[start] == '"'
    out, i = [], start + 1
    while text[i] != '"':
        if text[i] == "\\":
            i += 1
            out.append({"n": "\n"}.get(text[i], text[i]))
        else:
            out.append(text[i])
        i += 1
    return "".join(out), i + 1


def sexp_end(text, start):
    """Return the index after the s-expression or symbol at TEXT[START]."""
    if text[start] != "(":
        return re.match(r"[^\s()\"]+", text[start:]).end() + start
    depth, i = 0, start
    while True:
        if text[i] == '"':
            i = scheme_string(text, i)[1]
            continue
        depth += {"(": 1, ")": -1}.get(text[i], 0)
        i += 1
        if depth == 0:
            return i


def definition(source, name):
    """Return the string value of (define NAME "...")."""
    start = source.index(f'(define {name} "') + len(f"(define {name} ")
    return scheme_string(source, start)[0]


def omaguix_update_script(substitutions):
    """Return the shim's shell text, each #$ expression from SUBSTITUTIONS."""
    source = OMARCHY.read_text()
    marker = '(shim "omaguix-update" (string-append '
    i = source.index(marker) + len(marker)
    parts = []
    while True:
        while source[i].isspace():
            i += 1
        if source[i] == ")":
            return "".join(parts)
        if source[i] == '"':
            text, i = scheme_string(source, i)
            parts.append(text)
        else:
            assert source.startswith("#$", i), source[i:i + 40]
            end = sexp_end(source, i + 2)
            parts.append(substitutions[source[i + 2:end]])
            i = end


class OmaguixUpdateTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = root = Path(directory.name)
        self.log = root / "log"
        self.log.touch()
        self.store = root / "store"
        self.store.mkdir()
        self.gcroots = root / "gcroots"
        self.gcroots.mkdir()
        self.installed = root / "etc-omaguix"
        (self.installed / "modules" / "omaguix").mkdir(parents=True)
        (self.installed / "modules" / "omaguix" / "guix-commit").write_text(OLD_PIN + "\n")
        self.git_env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.git_env.update(GIT_CONFIG_GLOBAL=str(root / "gitconfig"),
                            GIT_CONFIG_NOSYSTEM="1", GIT_AUTHOR_NAME="t",
                            GIT_AUTHOR_EMAIL="t@example.com", GIT_COMMITTER_NAME="t",
                            GIT_COMMITTER_EMAIL="t@example.com")
        self.work = root / "work"
        self.git("init", "--quiet", "--initial-branch=main", str(self.work), cwd=root)
        self.git("commit", "--quiet", "--allow-empty", "-m", "introduction")
        self.git("branch", "keyring")
        self.introduction = self.git("rev-parse", "HEAD")
        # The image was built from the channel's first commit.
        self.record = self.installed / "channel-commit"
        self.record.write_text(self.introduction + "\n")
        self.state = root / "state"
        self.channel = self.state / "channel"
        self.cursor = self.state / "channel-commit"
        self.state.mkdir()
        self.locked = False
        self.free_kib = 64 * 1024 * 1024
        self.describes = PATCHED
        self.reconfigure_fails = False
        self.guix_profile = self.store / f"{HASH}-profile"
        self.substitutable = True
        self.make_bin()
        self.make_script()

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.work, env=self.git_env,
                              check=True, capture_output=True, text=True).stdout.strip()

    def stub(self, path, body):
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)

    def make_bin(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        self.stub(bin_dir / "id", "echo 0")
        self.stub(bin_dir / "uname", "echo aarch64")
        # macOS's mktemp ignores TMPDIR; keep its file in the test directory.
        # With a template, the real one makes the file the template names.
        self.stub(bin_dir / "mktemp", f'''\
[ $# -gt 0 ] && exec /usr/bin/mktemp "$@"
f="{self.root}/tmp.$$.$RANDOM"; : > "$f"; echo "$f"''')
        # sync FILE: record which file was flushed, and what it held.
        self.stub(bin_dir / "sync", f'''\
for f; do
  if [ -f "$f" ]; then echo "$f $(cat "$f")"; else echo "$f"; fi
done >> "{self.root}/synced"''')
        # flock -n 9: fails while another run holds the lock.
        self.stub(bin_dir / "flock", f'[ "$*" = "-n 9" ] && [ ! -e "{self.root}/locked" ]')
        self.stub(bin_dir / "df", f"""\
echo 'Filesystem 1024-blocks Used Available Capacity Mounted on'
echo "/dev/vda2 0 0 $(cat "{self.root}/free") 0% /\"""")
        # The VM's Guix: authenticates, reconfigures (failing when the test
        # says so), and its repl realizes a store item as substitution would,
        # as a Guix that describes itself as the patched commit.
        self.stub(self.root / "guix", f"""\
case "$1" in
  repl) echo "guix OMAGUIX_GUIX=${{OMAGUIX_GUIX:-}} repl $2 SCRIPT $4" >> "{self.log}"
        echo "script: $(cat "$3")" >> "{self.log}" ;;
  *) echo "guix OMAGUIX_GUIX=${{OMAGUIX_GUIX:-}} $*" >> "{self.log}" ;;
esac
case "$1" in
  repl)
    [ -e "{self.root}/substitutable" ] || exit 1
    mkdir -p "$4/bin"
    printf '%s\\n' '#!/bin/bash' \\
      'case "$1" in describe) echo "    commit: $(cat "{self.root}/describes")";;' \\
      '  *) echo "new-guix OMAGUIX_GUIX=$OMAGUIX_GUIX $*" >> "{self.log}"' \\
      '     echo "channel commit: $OMAGUIX_CHANNEL_COMMIT" >> "{self.log}"' \\
      '     [ ! -e "{self.root}/reconfigure-fails" ];; esac' > "$4/bin/guix"
    chmod 755 "$4/bin/guix"
    echo "root during repl: $(readlink "{self.gcroots}/omaguix-guix-next")" >> "{self.log}" ;;
  system)
    echo "channel commit: $OMAGUIX_CHANNEL_COMMIT" >> "{self.log}"
    [ ! -e "{self.root}/reconfigure-fails" ] ;;
esac""")
        self.env = dict(self.git_env, PATH=f"{bin_dir}:{os.environ['PATH']}")

    def make_script(self):
        source = OMARCHY.read_text()
        script = omaguix_update_script({
            "%build-gate": definition(source, "%build-gate"),
            "%guix-move-free-gib": definition(source, "%guix-move-free-gib"),
            '(file-append git "/bin/git")': "git",
            '(file-append jq "/bin/jq")': "jq",
            '(file-append util-linux "/bin/flock")': str(self.root / "bin" / "flock"),
            "(omaguix-trust-channel-url %omaguix-trust)": str(self.work),
            "(omaguix-trust-channel-introduction %omaguix-trust)": "2222",
            "(omaguix-trust-channel-signer %omaguix-trust)": "AAAA BBBB",
        })
        for path, replacement in (
                ("state=/var/lib/omaguix", f"state={self.state}"),
                ("/etc/omaguix/channel-commit", str(self.record)),
                ("/var/guix/gcroots/omaguix-guix/bin/guix", str(self.root / "guix")),
                ("/var/guix/gcroots/omaguix-guix-next", str(self.gcroots / "omaguix-guix-next")),
                ("/etc/omaguix/modules/omaguix", str(self.installed / "modules" / "omaguix")),
                ("/gnu/store", str(self.store))):
            self.assertIn(path, script)
            script = script.replace(path, replacement)
        self.script = self.root / "omaguix-update"
        self.script.write_text("#!/bin/bash\n" + script)

    def release(self, pin, guix=None, manifest_pin=None, extra=None,
                patched=PATCHED):
        """Commit modules at PIN (C), then release.json on top (M) as main;
        return M."""
        modules = self.work / "modules" / "omaguix"
        modules.mkdir(parents=True, exist_ok=True)
        (modules / "guix-commit").write_text(pin + "\n")
        self.git("add", "-A")
        self.git("commit", "--quiet", "--allow-empty", "-m", "C")
        released = self.git("rev-parse", "HEAD")
        guix = str(self.guix_profile) if guix is None else guix
        (self.work / "release.json").write_text(json.dumps({
            "channel-commit": released,
            "guix-commit": manifest_pin or pin,
            "guix-patched-commit": patched,
            "architectures": {"aarch64-linux": {"guix": guix},
                              "x86_64-linux": {"guix": guix}}}))
        if extra:
            (self.work / extra).write_text("x\n")
        self.git("add", "-A")
        self.git("commit", "--quiet", "-m", "M")
        return self.git("rev-parse", "HEAD")

    def run_update(self):
        self.log.write_text("")
        (self.root / "free").write_text(str(self.free_kib))
        (self.root / "describes").write_text(self.describes)
        (self.root / "synced").write_text("")
        for name, on in (("substitutable", self.substitutable),
                         ("reconfigure-fails", self.reconfigure_fails),
                         ("locked", self.locked)):
            (self.root / name).unlink(missing_ok=True)
            if on:
                (self.root / name).touch()
        result = subprocess.run(["bash", str(self.script)], env=self.env,
                                capture_output=True, text=True)
        log = self.log.read_text().splitlines()
        return result, [line for line in log if " authenticate " not in line]

    def reconfigure(self, head, guix="guix OMAGUIX_GUIX=", flag=""):
        return [f"{guix} system reconfigure {flag}--max-jobs=0 --no-offload "
                f"-L {self.channel}/modules /etc/config.scm",
                f"channel commit: {head}"]

    def cursor_commit(self):
        return self.cursor.read_text() if self.cursor.exists() else None

    def assert_refused(self, result, log, message):
        self.assertEqual(result.returncode, 1)
        self.assertIn(message, result.stderr)
        self.assertEqual(log, [])

    def test_same_pin_reconfigures_with_the_vms_guix(self):
        head = self.release(OLD_PIN)
        result, log = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        # Guix's own forward check runs as usual: no flag on the same pin.
        self.assertEqual(log, self.reconfigure(head))
        self.assertEqual(self.cursor_commit(), head + "\n")

    def test_new_pin_substitutes_the_releases_guix_and_pins_it(self):
        head = self.release(NEW_PIN)
        result, log = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log, [
            # The VM's Guix only substitutes the release's Guix: ensure-path
            # fails on an item no server has, where a build would start.
            f"guix OMAGUIX_GUIX= repl -- SCRIPT {self.store}/{HASH}-profile",
            "script: (use-modules (guix store)) "
            "(with-store store (ensure-path store (cadr (command-line))))",
            f"root during repl: {self.store}/{HASH}-profile",
            # Only then, and only on a pin move, the check is skipped.
            *self.reconfigure(head, f"new-guix OMAGUIX_GUIX={self.store}/{HASH}-profile",
                              "--no-check-forward-update ")])
        # The new system pins the new Guix; the temporary root is gone.
        self.assertFalse((self.gcroots / "omaguix-guix-next").is_symlink())
        self.assertEqual(self.cursor_commit(), head + "\n")

    def test_the_cursor_is_flushed_under_a_unique_name_before_it_moves(self):
        head = self.release(OLD_PIN)
        result, _ = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        temporary, written = (self.root / "synced").read_text().splitlines()[0].split()
        self.assertRegex(temporary, "^" + re.escape(f"{self.cursor}.") + r"[A-Za-z0-9]{6}$")
        self.assertEqual(written, head)
        self.assertFalse(Path(temporary).exists())
        self.assertEqual(sorted(p.name for p in self.state.iterdir()),
                         ["channel", "channel-commit", "update.lock"])

    def test_main_must_descend_from_the_systems_record(self):
        older = self.release(NEW_PIN)
        newer = self.release(NEW_PIN)
        self.git("branch", "older", older)
        cases = {
            # The record is older than main: a normal update.
            "newer main": (older, newer, 0),
            # The same commit: a normal update that changes nothing.
            "same main": (newer, newer, 0),
            # main went back to an ancestor of the record.
            "older main": (newer, older, 1),
        }
        for name, (record, main, code) in cases.items():
            with self.subTest(name):
                self.cursor.unlink(missing_ok=True)
                self.record.write_text(record + "\n")
                self.git("update-ref", "refs/heads/main", main)
                result, log = self.run_update()
                if code:
                    self.assert_refused(result, log, f"does not descend from {record}")
                    self.assertIsNone(self.cursor_commit())
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("--no-check-forward-update", log[3])
                    self.assertEqual(self.cursor_commit(), main + "\n")

    def test_a_diverged_main_changes_nothing(self):
        applied = self.release(NEW_PIN)
        self.git("branch", "applied", applied)
        self.git("update-ref", "refs/heads/main", self.introduction)
        self.git("checkout", "--quiet", "--force", "main")
        self.git("commit", "--quiet", "--allow-empty", "-m", "another history")
        self.release(NEW_PIN)
        for cursor in (False, True):
            with self.subTest(cursor=cursor):
                self.record.write_text((self.introduction if cursor else applied) + "\n")
                if cursor:
                    self.cursor.write_text(applied + "\n")
                result, log = self.run_update()
                self.assert_refused(result, log, f"does not descend from {applied}")
                self.assertEqual(self.cursor_commit(), applied + "\n" if cursor else None)

    def test_the_cursor_keeps_main_from_going_back_after_a_roll_back(self):
        # After `guix system roll-back' the running system's record is older
        # than what omaguix-update applied; main may not go back to it.
        older = self.release(NEW_PIN)
        newer = self.release(NEW_PIN)
        self.record.write_text(older + "\n")
        self.cursor.write_text(newer + "\n")
        self.git("update-ref", "refs/heads/main", older)
        result, log = self.run_update()
        self.assert_refused(result, log, f"does not descend from {newer}")
        self.assertEqual(self.cursor_commit(), newer + "\n")

    def test_a_crash_after_activation_before_the_cursor_is_harmless(self):
        # The new system (its record: newest) is active, but the cursor still
        # names the release before it. A release in between is refused; the
        # newest one is a normal update that moves the cursor up.
        oldest = self.release(OLD_PIN)
        middle = self.release(OLD_PIN)
        newest = self.release(OLD_PIN)
        self.record.write_text(newest + "\n")
        self.cursor.write_text(oldest + "\n")
        self.git("update-ref", "refs/heads/main", middle)
        result, log = self.run_update()
        self.assert_refused(result, log, f"does not descend from {newest}")
        self.assertEqual(self.cursor_commit(), oldest + "\n")
        self.git("update-ref", "refs/heads/main", newest)
        result, log = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log, self.reconfigure(newest))
        self.assertEqual(self.cursor_commit(), newest + "\n")

    def test_a_garbled_cursor_falls_back_to_the_systems_record(self):
        older = self.release(OLD_PIN)
        newer = self.release(OLD_PIN)
        self.record.write_text(older + "\n")
        for cursor in ("", "garbage\n", older[:20]):
            with self.subTest(cursor=cursor):
                self.cursor.write_text(cursor)
                # The record still stands: main may not go back before it.
                self.git("update-ref", "refs/heads/main", self.introduction)
                self.git("commit", "--quiet", "--allow-empty", "-m", "x")
                self.git("update-ref", "refs/heads/main", newer)
                result, log = self.run_update()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("holds no commit", result.stderr)
                self.assertIn(f"record {older} stands", result.stderr)
                self.assertEqual(log, self.reconfigure(newer))
                self.assertEqual(self.cursor_commit(), newer + "\n")
        self.cursor.write_text("garbage\n")
        self.git("update-ref", "refs/heads/main", older)
        self.record.write_text(newer + "\n")
        result, log = self.run_update()
        self.assert_refused(result, log, f"does not descend from {newer}")

    def test_a_system_without_a_record_changes_nothing(self):
        self.release(NEW_PIN)
        for record in (None, "", "not a commit\n"):
            with self.subTest(record=record):
                if record is None:
                    self.record.unlink(missing_ok=True)
                else:
                    self.record.write_text(record)
                result, log = self.run_update()
                self.assert_refused(result, log, "records no channel commit")
                self.assertFalse(self.channel.exists())
                self.assertIsNone(self.cursor_commit())

    def test_a_system_without_a_guix_pin_changes_nothing(self):
        # Never counted as a move to another pin.
        self.release(OLD_PIN)
        pin = self.installed / "modules" / "omaguix" / "guix-commit"
        for content in (None, "", "HEAD\n"):
            with self.subTest(content=content):
                if content is None:
                    pin.unlink(missing_ok=True)
                else:
                    pin.write_text(content)
                result, log = self.run_update()
                self.assert_refused(result, log, "records no Guix pin")
                self.assertFalse(self.channel.exists())

    def test_a_second_run_changes_nothing_while_one_holds_the_lock(self):
        self.release(OLD_PIN)
        self.locked = True
        result, log = self.run_update()
        self.assert_refused(result, log, "another omaguix-update is running")
        self.assertFalse(self.channel.exists())
        self.assertIsNone(self.cursor_commit())

    def test_a_failed_reconfigure_keeps_the_cursor(self):
        self.reconfigure_fails = True
        for pin in (OLD_PIN, NEW_PIN):
            with self.subTest(pin=pin):
                self.release(pin)
                result, log = self.run_update()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"channel commit: {self.git('rev-parse', 'HEAD')}", log)
                self.assertIsNone(self.cursor_commit())
                self.assertEqual(sorted(p.name for p in self.state.iterdir()),
                                 ["channel", "update.lock"])

    def test_a_guix_that_is_not_the_patched_commit_is_never_run(self):
        self.describes = NEW_PIN
        self.release(NEW_PIN)
        result, log = self.run_update()
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"is not the patched Guix {PATCHED}", result.stderr)
        self.assertFalse(any("reconfigure" in line for line in log), log)
        self.assertIsNone(self.cursor_commit())

    def test_a_commit_that_is_not_a_release_changes_nothing(self):
        for name, kwargs in (("another file", {"extra": "modules/omaguix/x.scm"}),
                             ("another pin", {"manifest_pin": OLD_PIN})):
            with self.subTest(name):
                self.release(NEW_PIN, **kwargs)
                result, log = self.run_update()
                self.assertEqual(result.returncode, 1)
                self.assertIn("is not a release", result.stderr)
                self.assertEqual(log, [])

    def test_a_release_without_a_valid_guix_changes_nothing(self):
        for guix, patched in (("", PATCHED), ("/etc/passwd", PATCHED),
                              (f"{self.store}/{HASH}-profile/../../x", PATCHED),
                              (None, ""), (None, "HEAD")):
            with self.subTest(guix=guix, patched=patched):
                self.release(NEW_PIN, guix=guix, patched=patched)
                result, log = self.run_update()
                self.assertEqual(result.returncode, 1)
                self.assertIn("names no Guix for aarch64-linux", result.stderr)
                self.assertEqual(log, [])

    def test_new_pin_without_room_stops_before_fetching_guix(self):
        self.free_kib = 1024 * 1024
        self.release(NEW_PIN)
        result, log = self.run_update()
        self.assertEqual(result.returncode, 1)
        self.assertIn("1 GiB are", result.stderr)
        self.assertEqual(log, [])

    def test_an_unknown_free_space_stops_before_fetching_guix(self):
        self.release(NEW_PIN)
        for free in ("", "lots"):
            with self.subTest(free=free):
                self.free_kib = free
                result, log = self.run_update()
                self.assert_refused(result, log, "cannot tell the free space")

    def test_an_unserved_guix_stops_before_the_reconfigure(self):
        self.substitutable = False
        self.release(NEW_PIN)
        result, log = self.run_update()
        self.assertEqual(result.returncode, 1)
        self.assertIn("/dev/vda2", result.stderr)
        self.assertEqual(len(log), 2, log)
        self.assertTrue(log[0].startswith("guix OMAGUIX_GUIX= repl"), log)
        self.assertFalse((self.gcroots / "omaguix-guix-next").is_symlink())


class GuixPatchTests(unittest.TestCase):
    """guix-skip-forward-check.patch, which CI applies to the pinned Guix
    for the Guix VMs move with (docs/decisions/0007): Guix's downgrade
    check stays on unless --no-check-forward-update is given."""

    PATCH = OMARCHY.with_name("guix-skip-forward-check.patch")

    def lines(self, sign):
        return [line[1:].strip() for line in self.PATCH.read_text().splitlines()
                if line.startswith(sign) and not line.startswith(sign * 3)]

    def test_only_the_new_option_turns_the_check_off(self):
        text = self.PATCH.read_text()
        self.assertEqual(re.findall(r"^diff --git a/(\S+)", text, re.M),
                         ["guix/scripts/system.scm"])
        added, removed = self.lines("+"), self.lines("-")
        # The one call still runs whenever a validator is set, and the
        # default validator, ensure-forward-reconfigure, aborts a downgrade.
        self.assertEqual(removed, ["(check-forward-update validate-reconfigure))"])
        self.assertIn("(when validate-reconfigure", added)
        self.assertIn("(check-forward-update validate-reconfigure)))", added)
        self.assertNotIn("ensure-forward-reconfigure", text)
        self.assertNotIn("%default-options", text)
        self.assertEqual([line for line in added if "validate-reconfigure #f" in line],
                         ["(alist-cons 'validate-reconfigure #f result)))"])
        self.assertIn("(option '(\"no-check-forward-update\") #f #f", added)

    def test_applies_to_the_pinned_guix(self):
        # GUIX_CHECKOUT: a Git clone of Guix that has the pin.
        checkout = os.environ.get("GUIX_CHECKOUT")
        if not checkout:
            self.skipTest("GUIX_CHECKOUT is not set")
        pin = OMARCHY.with_name("guix-commit").read_text().strip()
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "guix" / "scripts" / "system.scm"
            target.parent.mkdir(parents=True)
            target.write_bytes(subprocess.run(
                ["git", "-C", checkout, "show", f"{pin}:guix/scripts/system.scm"],
                check=True, capture_output=True).stdout)
            subprocess.run(["git", "apply", "--check", str(self.PATCH)], cwd=tmp,
                           check=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
