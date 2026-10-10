"""omarchy-menu-jq.patch: Omarchy's menu payload encoded with jq, not perl.

The patch's added lines are the jq encoding and its removed lines are
upstream's perl encoding. Each test runs those lines of both scripts with
the same arguments and compares the payloads; the perl side runs only where
the host has perl with JSON::PP.
"""

import json
from pathlib import Path
import shutil
import subprocess
import unittest

HERE = Path(__file__).parent
PATCH = HERE / "modules" / "roguix" / "omarchy-menu-jq.patch"

# The variables the scripts set before encoding, from the test's arguments.
# The scripts run with set -u; bash before 4.4 (macOS's 3.2) counts an empty
# "${options[@]}" as unbound, so there it is left out.
PRELUDE = """set -eo pipefail
(( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 404 )) && set -u
prompt=$1 menu_width=$2 menu_maxheight=$3 selection_file=$4 done_file=$5
shift 5
options=("$@")
"""


def hunks():
    """{script: {"+": new lines, "-": old lines}} from the patch."""
    scripts = {}
    current = None
    for line in PATCH.read_text().splitlines():
        if line.startswith("+++ b/bin/"):
            current = scripts.setdefault(line[len("+++ b/bin/"):], {"+": [], "-": []})
        elif current is None or line.startswith(("--- ", "@@")):
            continue
        elif line[:1] in "+-":
            current[line[0]].append(line[1:])
    return scripts


HAS_PERL = shutil.which("perl") is not None and subprocess.run(
    ["perl", "-MEncode", "-MJSON::PP", "-e", "1"], capture_output=True).returncode == 0
SCRIPTS = hunks()


def encode(script, side, prompt, options=(), width="", maxheight=""):
    """Run SIDE ("+" jq, "-" perl) of SCRIPT's encoding; return the result."""
    body = PRELUDE + "\n".join(SCRIPTS[script][side]) + '\nprintf "%s" "$payload"\n'
    arguments = [prompt, width, maxheight, "/tmp/selection", "/tmp/done", *options]
    return subprocess.run(
        ["bash", "-c", body, "encode",
         *(a if isinstance(a, bytes) else a.encode() for a in arguments)],
        capture_output=True)


@unittest.skipUnless(shutil.which("jq"), "needs jq")
class MenuPayloadTests(unittest.TestCase):
    OPTIONS = [
        "plain",
        "\tLabel\tsub text",
        'with "quotes"',
        "back\\slash",
        "two\nlines",
        "",
        "-n",
        "--",
        "--width",
        "ünïcødé 台北",
        "\x7f control \x01",
    ]

    def payload(self, script, *args, **kwargs):
        result = encode(script, "+", *args, **kwargs)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return json.loads(result.stdout)

    def test_select_keeps_every_option_in_order(self):
        payload = self.payload("omarchy-menu-select", "Pick", self.OPTIONS,
                               width="520", maxheight="0400")
        self.assertEqual(payload, {
            "mode": "select", "prompt": "Pick", "options": self.OPTIONS,
            "selectionFile": "/tmp/selection", "doneFile": "/tmp/done",
            "width": 520, "maxHeight": 400})

    def test_select_omits_unset_sizes_and_encodes_an_empty_list(self):
        payload = self.payload("omarchy-menu-select", "Pick")
        self.assertEqual(payload["options"], [])
        self.assertNotIn("width", payload)
        self.assertNotIn("maxHeight", payload)

    def test_input_payload(self):
        self.assertEqual(self.payload("omarchy-menu-input", 'Say "hi"\t\\', width="400"), {
            "mode": "input", "prompt": 'Say "hi"\t\\',
            "selectionFile": "/tmp/selection", "doneFile": "/tmp/done", "width": 400})
        self.assertNotIn("width", self.payload("omarchy-menu-input", "Input"))

    def test_sizes_must_be_whole_numbers(self):
        for script, kwargs in (("omarchy-menu-select", {"width": "52x"}),
                               ("omarchy-menu-select", {"maxheight": "-1"}),
                               ("omarchy-menu-select", {"width": "1e3"}),
                               ("omarchy-menu-input", {"width": "wide"})):
            with self.subTest(script=script, **kwargs):
                result = encode(script, "+", "Pick", ["a"], **kwargs)
                self.assertEqual(result.returncode, 1)
                self.assertIn(b"whole number", result.stderr)
                self.assertEqual(result.stdout, b"")

    def test_malformed_utf8_is_replaced_not_fatal(self):
        bad = [b"caf\xe9", b"\xff\xfe", b"ok \xe2\x82"]
        for script in ("omarchy-menu-select", "omarchy-menu-input"):
            with self.subTest(script=script):
                payload = self.payload(script, b"pr\xc3ompt", bad)
                self.assertIn("�", payload["prompt"])
                if script == "omarchy-menu-select":
                    self.assertEqual(len(payload["options"]), 3)
                    for option in payload["options"]:
                        self.assertIn("�", option)

    @unittest.skipUnless(HAS_PERL, "needs perl with JSON::PP")
    def test_same_payload_as_perl(self):
        cases = [
            ("omarchy-menu-select", ("Pick", self.OPTIONS), {"width": "520", "maxheight": "400"}),
            ("omarchy-menu-select", ("Set timezone", ["Europe/Warsaw", "UTC"]), {}),
            ("omarchy-menu-input", ('Say "hi"\t\\\n',), {"width": "400"}),
            ("omarchy-menu-input", ("Input",), {}),
        ]
        for script, args, kwargs in cases:
            with self.subTest(script=script, args=args):
                perl = encode(script, "-", *args, **kwargs)
                self.assertEqual(perl.returncode, 0, perl.stderr.decode())
                self.assertEqual(self.payload(script, *args, **kwargs), json.loads(perl.stdout))

    @unittest.skipUnless(HAS_PERL, "needs perl with JSON::PP")
    def test_malformed_utf8_differs_from_perl_only_in_replacements(self):
        # Both replace bytes that are not UTF-8 with U+FFFD; they may count a
        # broken sequence as one or several. Everything else is the same.
        options = [b"caf\xe9 bar", b"\xff\xfe", b"ok \xe2\x82 end"]
        perl = json.loads(encode("omarchy-menu-select", "-", "Pick", options).stdout)
        jq = self.payload("omarchy-menu-select", "Pick", options)

        def squeeze(text):
            while "��" in text:
                text = text.replace("��", "�")
            return text

        self.assertEqual([squeeze(o) for o in jq["options"]],
                         [squeeze(o) for o in perl["options"]])


if __name__ == "__main__":
    unittest.main()
