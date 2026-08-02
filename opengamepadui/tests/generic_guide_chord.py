#!/usr/bin/env python3
"""Exercise Wolf's generic Guide chord against a running InputPlumber daemon."""

from __future__ import annotations

import re
import subprocess
import threading
import time

from evdev import AbsInfo, UInput, ecodes


SERVICE = "org.shadowblip.InputPlumber"
COMPOSITE_INTERFACE = "org.shadowblip.Input.CompositeDevice"
EXPECTED_EVENTS = [
    ("ui_guide", 1.0),
    ("ui_action", 1.0),
    ("ui_action", 0.0),
    ("ui_guide", 0.0),
]


def run(*args: str) -> str:
    result = subprocess.run(args, check=True, text=True, capture_output=True)
    return result.stdout.strip()


def find_composite(source_path: str, timeout: float = 8.0) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        tree = run("busctl", "--system", "--list", "tree", SERVICE)
        for path in tree.splitlines():
            path = path.strip()
            if not path.startswith("/org/shadowblip/InputPlumber/CompositeDevice"):
                continue
            name = run(
                "busctl",
                "--system",
                "get-property",
                SERVICE,
                path,
                COMPOSITE_INTERFACE,
                "Name",
            )
            if "Wolf Virtual Gamepad" in name:
                sources = run(
                    "busctl",
                    "--system",
                    "get-property",
                    SERVICE,
                    path,
                    COMPOSITE_INTERFACE,
                    "SourceDevicePaths",
                )
                if f'"{source_path}"' in sources:
                    return path
        time.sleep(0.1)
    raise RuntimeError("Wolf Virtual Gamepad composite was not created")


def get_dbus_target(composite: str) -> str:
    value = run(
        "busctl",
        "--system",
        "get-property",
        SERVICE,
        composite,
        COMPOSITE_INTERFACE,
        "DbusDevices",
    )
    match = re.search(r'"([^"]+/devices/target/dbus\d+)"', value)
    if not match:
        raise RuntimeError(f"Composite has no D-Bus target: {value}")
    return match.group(1)


def configure_chord(composite: str, mode: int) -> None:
    run(
        "busctl",
        "--system",
        "call",
        SERVICE,
        composite,
        COMPOSITE_INTERFACE,
        "SetInterceptActivation",
        "ass",
        "2",
        "Gamepad:Button:Start",
        "Gamepad:Button:Select",
        "Gamepad:Button:Guide",
    )
    run(
        "busctl",
        "--system",
        "set-property",
        SERVICE,
        composite,
        COMPOSITE_INTERFACE,
        "InterceptMode",
        "u",
        str(mode),
    )


def capture_chord(
    ui: UInput,
    target: str,
    activation_order: tuple[int, int],
) -> list[tuple[str, float]]:
    output: list[str] = []
    monitor = subprocess.Popen(
        [
            "dbus-monitor",
            "--system",
            f"type='signal',path='{target}',"
            "interface='org.shadowblip.Input.DBusDevice',member='InputEvent'",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert monitor.stdout is not None
    reader = threading.Thread(target=lambda: output.extend(monitor.stdout), daemon=True)
    reader.start()
    time.sleep(0.15)

    first, second = activation_order
    for code, value in (
        (first, 1),
        (second, 1),
        (ecodes.BTN_WEST, 1),
        (ecodes.BTN_WEST, 0),
        (first, 0),
        (second, 0),
    ):
        ui.write(ecodes.EV_KEY, code, value)
        ui.syn()
        time.sleep(0.12)

    time.sleep(0.35)
    monitor.terminate()
    monitor.wait(timeout=2)
    reader.join(timeout=1)

    events: list[tuple[str, float]] = []
    for index, line in enumerate(output):
        event_match = re.search(r'string "([^"]+)"', line)
        if not event_match:
            continue
        for value_line in output[index + 1 : index + 4]:
            value_match = re.search(r"double ([0-9.-]+)", value_line)
            if value_match:
                events.append((event_match.group(1), float(value_match.group(1))))
                break
    return events


def assert_expected(mode_name: str, events: list[tuple[str, float]]) -> None:
    cursor = 0
    for event in events:
        if cursor < len(EXPECTED_EVENTS) and event == EXPECTED_EVENTS[cursor]:
            cursor += 1
    if cursor != len(EXPECTED_EVENTS):
        raise AssertionError(f"{mode_name}: expected {EXPECTED_EVENTS}, received {events}")
    leaked = [event for event in events if event[0] in {"ui_select", "ui_option"}]
    if leaked:
        raise AssertionError(f"{mode_name}: activation buttons leaked: {leaked}")


def main() -> None:
    capabilities = {
        ecodes.EV_KEY: [
            ecodes.BTN_SOUTH,
            ecodes.BTN_EAST,
            ecodes.BTN_NORTH,
            ecodes.BTN_WEST,
            ecodes.BTN_TL,
            ecodes.BTN_TR,
            ecodes.BTN_SELECT,
            ecodes.BTN_START,
            ecodes.BTN_MODE,
        ],
        ecodes.EV_ABS: [
            (ecodes.ABS_X, AbsInfo(0, -32768, 32767, 16, 128, 1)),
            (ecodes.ABS_Y, AbsInfo(0, -32768, 32767, 16, 128, 1)),
        ],
    }
    with UInput(
        capabilities,
        name="Wolf X-Box One (virtual) pad",
        vendor=0x045E,
        product=0x0B13,
        version=0x0517,
        bustype=ecodes.BUS_USB,
    ) as ui:
        composite = find_composite(ui.device.path)
        target = get_dbus_target(composite)
        orders = (
            ("start-select", (ecodes.BTN_START, ecodes.BTN_SELECT)),
            ("select-start", (ecodes.BTN_SELECT, ecodes.BTN_START)),
        )
        for mode_name, mode in (("menu/always", 2), ("game/pass", 1)):
            for order_name, order in orders:
                case_name = f"{mode_name}/{order_name}"
                configure_chord(composite, mode)
                events = capture_chord(ui, target, order)
                assert_expected(case_name, events)
                print(f"PASS {case_name}: {events}")


if __name__ == "__main__":
    main()
