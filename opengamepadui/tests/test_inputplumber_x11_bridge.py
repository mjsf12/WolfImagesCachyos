#!/usr/bin/env python3

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "scripts" / "inputplumber_x11_bridge.py"
SPEC = importlib.util.spec_from_file_location("inputplumber_x11_bridge", SCRIPT)
BRIDGE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(BRIDGE)


class BridgeHelpersTest(unittest.TestCase):
    def test_pointer_motion_is_clamped_to_the_x11_screen(self):
        self.assertEqual(BRIDGE.next_pointer_position(10, 10, -20, 200, 100, 80), (0, 79))

    def test_linux_mouse_buttons_map_to_x11_details(self):
        self.assertEqual(BRIDGE.mouse_button_detail(BRIDGE.ecodes.BTN_LEFT), 1)
        self.assertEqual(BRIDGE.mouse_button_detail(BRIDGE.ecodes.BTN_MIDDLE), 2)
        self.assertEqual(BRIDGE.mouse_button_detail(BRIDGE.ecodes.BTN_RIGHT), 3)
        self.assertIsNone(BRIDGE.mouse_button_detail(BRIDGE.ecodes.KEY_ENTER))


if __name__ == "__main__":
    unittest.main()
