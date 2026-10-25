"""vm-run against a stand-in serial console that runs the guest's commands in
a local bash; no builder VM is started."""

import contextlib
import importlib.machinery
import importlib.util
import io
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock

HERE = Path(__file__).parent
loader = importlib.machinery.SourceFileLoader("vm_run", str(HERE / "vm-run"))
spec = importlib.util.spec_from_loader(loader.name, loader)
vm_run = importlib.util.module_from_spec(spec)
loader.exec_module(vm_run)


class Console:
    """Answers each command line like the builder's serial console: the
    echoed input, then bash's output. The guest job does not run when vm-run
    starts it; it runs to its end inside the first poll, right after that
    poll's first statement: between reading the log's size and the status,
    or the other way round, which is the interleaving under test."""

    def __init__(self, root):
        self.root = root
        self.socket_path = root / "serial.sock"
        self.deferred = root / "deferred"
        bin_dir = root / "bin"
        bin_dir.mkdir()
        # setsid records the detached job instead of starting it.
        (bin_dir / "setsid").write_text(f"#!/bin/bash\nprintf '%q ' \"$@\" > {self.deferred}\n")
        (bin_dir / "setsid").chmod(0o755)
        self.path = f"{bin_dir}:/usr/bin:/bin"
        self.polls = 0
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(str(self.socket_path))
        self.server.listen()
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self):
        while True:
            try:
                connection, _ = self.server.accept()
            except OSError:
                return
            with connection:
                data = b""
                while not data.endswith(b"\n"):
                    chunk = connection.recv(65536)
                    if not chunk:
                        break
                    data += chunk
                line = data.decode()
                # The detached start returns at once; run it in the foreground,
                # so the job is recorded before vm-run polls.
                command = line.replace(" &) && echo started", ") && echo started")
                if ".status" in line and "setsid" not in line:
                    self.polls += 1
                    if self.polls == 1:
                        # After the marker and the poll's first statement.
                        marker, first, rest = line.split("; ", 2)
                        command = f'{marker}; {first}; eval "$(cat {self.deferred})"; {rest}'
                output = subprocess.run(["bash", "-c", command], capture_output=True,
                                        text=True, env={"PATH": self.path}).stdout
                connection.sendall((line + output).encode())

    def close(self):
        self.server.close()


class VMRunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name).resolve()
        self.console = Console(root)
        self.addCleanup(self.console.close)
        for name, value in (("SOCKET", self.console.socket_path),
                            ("GUEST_DIR", str(root / "guest"))):
            patch = mock.patch.object(vm_run, name, value)
            patch.start()
            self.addCleanup(patch.stop)

    def run_job(self, command):
        output = io.StringIO()
        with mock.patch.object(sys, "argv", ["vm-run", "--poll", "0", command]), \
                contextlib.redirect_stdout(output):
            code = vm_run.main()
        return code, output.getvalue()

    def test_a_job_that_ends_during_a_poll_prints_all_its_output(self):
        code, output = self.run_job("for i in $(seq 1 100); do echo line-$i; done; exit 3")
        lines = [line for line in output.splitlines() if not line.startswith("vm-run:")]
        self.assertEqual(lines, [f"line-{i}" for i in range(1, 101)])
        self.assertEqual(code, 3)
        self.assertGreaterEqual(self.console.polls, 2)

    def test_output_larger_than_a_poll_comes_whole_and_in_order(self):
        with mock.patch.object(vm_run, "CHUNK", 100):
            code, output = self.run_job("for i in $(seq 1 100); do echo line-$i; done")
        text = "".join(line for line in output.splitlines() if not line.startswith("vm-run:"))
        # A poll may end inside a line, which then prints as two.
        self.assertEqual(text, "".join(f"line-{i}" for i in range(1, 101)))
        self.assertEqual(code, 0)


if __name__ == "__main__":
    unittest.main()
