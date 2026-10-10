#!/usr/bin/env python3
"""Behavior tests for the guest side of the clipboard bridge."""

from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
import io
import os
from pathlib import Path
import threading
import unittest
from unittest.mock import patch


BRIDGE_PATH = Path(__file__).resolve().parent / "modules/roguix/clipboard-bridge"
LOADER = SourceFileLoader("omarchy_native_clipboard_bridge", str(BRIDGE_PATH))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot import {BRIDGE_PATH}")
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class WatcherInputTests(unittest.TestCase):
    def test_large_watcher_input_is_drained_before_querying_owner(self) -> None:
        # The owner feeds the watcher callback's stdin; until that ends it
        # cannot answer the callback's own request (Try Omarchy 6d480d1).
        reader, writer = os.pipe()
        delivered = threading.Event()
        payload = b"\x89PNG\r\n" + b"x" * (1024 * 1024)

        def supply_selection():
            try:
                offset = 0
                while offset < len(payload):
                    offset += os.write(writer, payload[offset:])
                delivered.set()
            except BrokenPipeError:
                pass
            finally:
                os.close(writer)

        def query_owner():
            if not delivered.is_set():
                raise AssertionError("queried the owner while it was still feeding stdin")
            return bridge.PNG_FORMAT, payload

        thread = threading.Thread(target=supply_selection)
        thread.start()
        output = io.StringIO()
        try:
            with os.fdopen(reader, "rb") as incoming:
                with patch.object(bridge.sys, "stdin", incoming), \
                        patch.object(bridge.sys, "stdout", output), \
                        patch.object(bridge, "wl_paste_selection", query_owner):
                    self.assertEqual(bridge.emit_selection(), 0)
        finally:
            thread.join()
        self.assertEqual(bridge.parse_watch_line(output.getvalue().strip().encode()),
                         (bridge.PNG_FORMAT, payload))


if __name__ == "__main__":
    unittest.main()
