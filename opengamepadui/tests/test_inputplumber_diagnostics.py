#!/usr/bin/env python3

import importlib.util
import os
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(
    os.environ.get(
        "INPUTPLUMBER_DIAGNOSTICS",
        pathlib.Path(__file__).parents[1] / "scripts" / "inputplumber_diagnostics.py",
    )
)
SPEC = importlib.util.spec_from_file_location("inputplumber_diagnostics", SCRIPT)
DIAGNOSTICS = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(DIAGNOSTICS)


class DiagnosticsHelpersTest(unittest.TestCase):
    def test_classifies_wolf_and_desktop_targets(self):
        self.assertEqual(
            DIAGNOSTICS.device_kind("Wolf X-Box One (virtual) pad"),
            "source_gamepad",
        )
        self.assertEqual(
            DIAGNOSTICS.device_kind("InputPlumber Mouse"),
            "target_mouse",
        )
        self.assertEqual(
            DIAGNOSTICS.device_kind("InputPlumber Keyboard"),
            "target_keyboard",
        )

    def test_filters_relevant_source_and_mouse_events(self):
        self.assertTrue(
            DIAGNOSTICS.should_trace_event(
                "source_gamepad",
                DIAGNOSTICS.ecodes.EV_KEY,
                DIAGNOSTICS.ecodes.BTN_START,
            )
        )
        self.assertTrue(
            DIAGNOSTICS.should_trace_event(
                "source_gamepad",
                DIAGNOSTICS.ecodes.EV_ABS,
                DIAGNOSTICS.ecodes.ABS_RX,
            )
        )
        self.assertTrue(
            DIAGNOSTICS.should_trace_event(
                "target_mouse",
                DIAGNOSTICS.ecodes.EV_REL,
                DIAGNOSTICS.ecodes.REL_X,
            )
        )
        self.assertFalse(
            DIAGNOSTICS.should_trace_event(
                "target_mouse",
                DIAGNOSTICS.ecodes.EV_SYN,
                DIAGNOSTICS.ecodes.SYN_REPORT,
            )
        )

    def test_parses_composite_property_snapshot_in_request_order(self):
        actual = DIAGNOSTICS.parse_property_lines(
            'u 1\ns "Wolf Desktop Mouse"\nas 2 "mouse" "keyboard"\nas 1 "event9"'
        )
        self.assertEqual(actual["intercept_mode"], "u 1")
        self.assertEqual(actual["profile_name"], 's "Wolf Desktop Mouse"')
        self.assertEqual(actual["target_devices"], 'as 2 "mouse" "keyboard"')
        self.assertEqual(actual["source_devices"], 'as 1 "event9"')

    def test_rotates_trace_without_losing_new_events(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "trace.jsonl")
            writer = DIAGNOSTICS.TraceWriter(path, max_bytes=1024)
            writer.emit("large", console=False, payload="x" * 1100)
            writer.emit("after_rotation", console=False)
            writer.close()

            self.assertTrue(os.path.exists(path + ".previous"))
            with open(path, encoding="utf-8") as trace_file:
                self.assertIn('"event": "after_rotation"', trace_file.read())


if __name__ == "__main__":
    unittest.main()
