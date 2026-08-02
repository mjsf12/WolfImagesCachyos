#!/usr/bin/env python3

import importlib.util
import os
import pathlib
import unittest


SCRIPT = pathlib.Path(
    os.environ.get(
        "INPUTPLUMBER_X11_BRIDGE",
        pathlib.Path(__file__).parents[1] / "scripts" / "inputplumber_x11_bridge.py",
    )
)
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

    def test_flush_motion_uses_warp_pointer_for_gamescope_xwayland(self):
        class Pointer:
            root_x = 50
            root_y = 60

        class Root:
            def __init__(self):
                self.warps = []

            def query_pointer(self):
                return Pointer()

            def warp_pointer(self, x, y):
                self.warps.append((x, y))

        class Display:
            def __init__(self):
                self.syncs = 0

            def sync(self):
                self.syncs += 1

        bridge = BRIDGE.X11Bridge(":1")
        bridge.root = Root()
        bridge.xdisplay = Display()
        bridge.width = 100
        bridge.height = 100
        bridge.delta_x = 20
        bridge.delta_y = -10

        bridge._flush_motion()

        self.assertEqual(bridge.root.warps, [(70, 50)])
        self.assertEqual(bridge.xdisplay.syncs, 1)
        self.assertEqual((bridge.delta_x, bridge.delta_y), (0, 0))


if __name__ == "__main__":
    unittest.main()
