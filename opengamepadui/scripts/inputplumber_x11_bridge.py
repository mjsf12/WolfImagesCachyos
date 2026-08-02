#!/usr/bin/env python3
"""Forward InputPlumber desktop targets to Gamescope's game Xwayland."""

from __future__ import annotations

import glob
import os
import select
import sys
import time
from typing import Iterable

from evdev import InputDevice, ecodes
from Xlib import X, XK, display
from Xlib.ext import xtest


MOUSE_DEVICE_NAME = "InputPlumber Mouse"
KEYBOARD_DEVICE_NAME = "InputPlumber Keyboard"

MOUSE_BUTTONS = {
    ecodes.BTN_LEFT: 1,
    ecodes.BTN_MIDDLE: 2,
    ecodes.BTN_RIGHT: 3,
    ecodes.BTN_SIDE: 8,
    ecodes.BTN_EXTRA: 9,
}

KEYBOARD_KEYSYMS = {
    ecodes.KEY_UP: "Up",
    ecodes.KEY_DOWN: "Down",
    ecodes.KEY_LEFT: "Left",
    ecodes.KEY_RIGHT: "Right",
    ecodes.KEY_ENTER: "Return",
    ecodes.KEY_ESC: "Escape",
    ecodes.KEY_TAB: "Tab",
    ecodes.KEY_BACKSPACE: "BackSpace",
    ecodes.KEY_SPACE: "space",
}


def clamp(value: int, lower: int, upper: int) -> int:
    return max(lower, min(value, upper))


def next_pointer_position(
    current_x: int,
    current_y: int,
    delta_x: int,
    delta_y: int,
    width: int,
    height: int,
) -> tuple[int, int]:
    return (
        clamp(current_x + delta_x, 0, width - 1),
        clamp(current_y + delta_y, 0, height - 1),
    )


def mouse_button_detail(code: int) -> int | None:
    return MOUSE_BUTTONS.get(code)


def _log(message: str) -> None:
    print(f"[inputplumber-x11-bridge] {message}", flush=True)


def _device_nodes(device_name: str) -> list[str]:
    nodes: list[str] = []
    for sysfs_path in sorted(glob.glob("/sys/class/input/event*")):
        try:
            with open(os.path.join(sysfs_path, "device/name"), encoding="utf-8") as name_file:
                if name_file.read().strip() != device_name:
                    continue
        except OSError:
            continue
        node = os.path.join("/dev/input", os.path.basename(sysfs_path))
        if os.path.exists(node):
            nodes.append(node)
    return nodes


class X11Bridge:
    def __init__(self, display_name: str) -> None:
        self.display_name = display_name
        self.xdisplay: display.Display | None = None
        self.root = None
        self.width = 0
        self.height = 0
        self.devices: list[InputDevice] = []
        self.device_kinds: dict[int, str] = {}
        self.delta_x = 0
        self.delta_y = 0

    def connect(self) -> None:
        self.xdisplay = display.Display(self.display_name)
        if not self.xdisplay.has_extension("XTEST"):
            raise RuntimeError(f"XTEST is unavailable on {self.display_name}")
        screen = self.xdisplay.screen()
        self.root = screen.root
        self.width = screen.width_in_pixels
        self.height = screen.height_in_pixels

        for node in _device_nodes(MOUSE_DEVICE_NAME):
            device = InputDevice(node)
            self.devices.append(device)
            self.device_kinds[device.fd] = "mouse"
        for node in _device_nodes(KEYBOARD_DEVICE_NAME):
            device = InputDevice(node)
            self.devices.append(device)
            self.device_kinds[device.fd] = "keyboard"
        if not self.devices:
            raise RuntimeError("InputPlumber desktop targets are unavailable")

        names = ", ".join(sorted(device.path for device in self.devices))
        _log(f"forwarding {names} to Xwayland {self.display_name}")

    def close(self) -> None:
        for device in self.devices:
            try:
                device.close()
            except OSError:
                pass
        self.devices.clear()
        self.device_kinds.clear()
        if self.xdisplay is not None:
            try:
                self.xdisplay.close()
            except Exception:
                pass
        self.xdisplay = None
        self.root = None

    def run(self) -> None:
        while True:
            readable, _, _ = select.select(self.devices, [], [], 1.0)
            for device in readable:
                kind = self.device_kinds[device.fd]
                for event in device.read():
                    if kind == "mouse":
                        self._handle_mouse(event.type, event.code, event.value)
                    else:
                        self._handle_keyboard(event.type, event.code, event.value)

    def _handle_mouse(self, event_type: int, code: int, value: int) -> None:
        if event_type == ecodes.EV_REL:
            if code == ecodes.REL_X:
                self.delta_x += value
            elif code == ecodes.REL_Y:
                self.delta_y += value
            elif code == ecodes.REL_WHEEL:
                self._scroll(value, 4, 5)
            elif code == ecodes.REL_HWHEEL:
                self._scroll(value, 7, 6)
            return

        if event_type == ecodes.EV_KEY:
            detail = mouse_button_detail(code)
            if detail is None:
                return
            event = X.ButtonPress if value else X.ButtonRelease
            xtest.fake_input(self.xdisplay, event, detail=detail)
            self.xdisplay.sync()
            return

        if event_type == ecodes.EV_SYN and code == ecodes.SYN_REPORT:
            self._flush_motion()

    def _flush_motion(self) -> None:
        if self.delta_x == 0 and self.delta_y == 0:
            return
        pointer = self.root.query_pointer()
        target_x, target_y = next_pointer_position(
            pointer.root_x,
            pointer.root_y,
            self.delta_x,
            self.delta_y,
            self.width,
            self.height,
        )
        xtest.fake_input(
            self.xdisplay,
            X.MotionNotify,
            root=self.root,
            x=target_x,
            y=target_y,
        )
        self.xdisplay.sync()
        self.delta_x = 0
        self.delta_y = 0

    def _scroll(self, value: int, positive_detail: int, negative_detail: int) -> None:
        detail = positive_detail if value > 0 else negative_detail
        for _ in range(abs(value)):
            xtest.fake_input(self.xdisplay, X.ButtonPress, detail=detail)
            xtest.fake_input(self.xdisplay, X.ButtonRelease, detail=detail)
        self.xdisplay.sync()

    def _handle_keyboard(self, event_type: int, code: int, value: int) -> None:
        if event_type != ecodes.EV_KEY or value not in (0, 1, 2):
            return
        keysym_name = KEYBOARD_KEYSYMS.get(code)
        if keysym_name is None:
            return
        keycode = self.xdisplay.keysym_to_keycode(XK.string_to_keysym(keysym_name))
        if keycode == 0:
            return
        event = X.KeyRelease if value == 0 else X.KeyPress
        xtest.fake_input(self.xdisplay, event, detail=keycode)
        self.xdisplay.sync()


def main(argv: Iterable[str] | None = None) -> int:
    arguments = list(argv if argv is not None else sys.argv[1:])
    display_name = arguments[0] if arguments else os.environ.get("DISPLAY", ":1")
    bridge = X11Bridge(display_name)
    last_error = ""
    while True:
        try:
            bridge.connect()
            last_error = ""
            bridge.run()
        except Exception as error:
            message = str(error)
            if message != last_error:
                _log(f"waiting to reconnect: {message}")
                last_error = message
            bridge.close()
            time.sleep(1)


if __name__ == "__main__":
    raise SystemExit(main())
