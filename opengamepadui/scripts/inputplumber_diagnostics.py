#!/usr/bin/env python3
"""Record the complete Wolf/OpenGamepadUI input route as JSON lines."""

from __future__ import annotations

import datetime
import glob
import hashlib
import json
import os
import select
import signal
import subprocess
import sys
import time
from typing import Any

from evdev import InputDevice, ecodes
from Xlib import display


SERVICE = "org.shadowblip.InputPlumber"
COMPOSITE_INTERFACE = "org.shadowblip.Input.CompositeDevice"
PROFILE_PATH = (
    "/home/gow/.local/share/opengamepadui/data/gamepad/profiles/"
    "wolf_desktop_mouse.json"
)
TRACE_PATH = os.environ.get(
    "WOLF_INPUT_TRACE_PATH",
    "/home/gow/.local/state/opengamepadui/wolf-input-trace.jsonl",
)
DEFAULT_MAX_TRACE_BYTES = 50 * 1024 * 1024


def device_kind(name: str) -> str:
    if name.startswith("Wolf "):
        return "source_gamepad"
    if name == "InputPlumber Mouse":
        return "target_mouse"
    if name == "InputPlumber Keyboard":
        return "target_keyboard"
    if name.startswith("InputPlumber "):
        return "target_gamepad"
    return ""


def event_code_name(event_type: int, code: int) -> str:
    name = ecodes.bytype.get(event_type, {}).get(code, str(code))
    if isinstance(name, (list, tuple)):
        return "/".join(name)
    return str(name)


def should_trace_event(kind: str, event_type: int, code: int) -> bool:
    if event_type == ecodes.EV_KEY:
        return True
    if kind == "source_gamepad" and event_type == ecodes.EV_ABS:
        return code in {
            ecodes.ABS_X,
            ecodes.ABS_Y,
            ecodes.ABS_RX,
            ecodes.ABS_RY,
            ecodes.ABS_Z,
            ecodes.ABS_RZ,
            ecodes.ABS_HAT0X,
            ecodes.ABS_HAT0Y,
        }
    if kind == "target_mouse" and event_type == ecodes.EV_REL:
        return True
    return False


def parse_property_lines(output: str) -> dict[str, str]:
    lines = output.splitlines()
    names = ("intercept_mode", "profile_name", "target_devices", "source_devices")
    return {
        name: lines[index] if index < len(lines) else "<missing>"
        for index, name in enumerate(names)
    }


class TraceWriter:
    def __init__(self, path: str, max_bytes: int | None = None) -> None:
        self.started = time.monotonic()
        self.path = path
        if max_bytes is None:
            try:
                max_bytes = int(
                    os.environ.get(
                        "WOLF_INPUT_TRACE_MAX_BYTES",
                        str(DEFAULT_MAX_TRACE_BYTES),
                    )
                )
            except ValueError:
                max_bytes = DEFAULT_MAX_TRACE_BYTES
        self.max_bytes = max(1024, max_bytes)
        self.file = None
        self._open()

    def _open(self) -> None:
        try:
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            self.file = open(self.path, "a", encoding="utf-8", buffering=1)
        except OSError as error:
            print(
                f"[wolf-input-trace] unable to open {self.path}: {error}",
                flush=True,
            )

    def _rotate_if_needed(self) -> None:
        if self.file is None or self.file.tell() < self.max_bytes:
            return
        try:
            self.file.close()
            os.replace(self.path, self.path + ".previous")
            self.file = None
            self._open()
        except OSError as error:
            self.file = None
            print(f"[wolf-input-trace] unable to rotate trace: {error}", flush=True)

    def emit(self, event: str, *, console: bool = True, **fields: Any) -> None:
        payload = {
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(
                timespec="milliseconds"
            ),
            "monotonic_ms": round((time.monotonic() - self.started) * 1000),
            "pid": os.getpid(),
            "event": event,
            **fields,
        }
        line = json.dumps(payload, ensure_ascii=False, sort_keys=True)
        if console:
            print(f"[wolf-input-trace] {line}", flush=True)
        if self.file is not None:
            try:
                self._rotate_if_needed()
                if self.file is None:
                    return
                self.file.write(line + "\n")
            except OSError:
                self.file = None

    def close(self) -> None:
        if self.file is not None:
            self.file.close()


class InputDiagnostics:
    def __init__(self, trace: TraceWriter, display_name: str) -> None:
        self.trace = trace
        self.display_name = display_name
        self.running = True
        self.devices: dict[str, InputDevice] = {}
        self.device_kinds: dict[int, str] = {}
        self.composites: list[str] = []
        self.snapshots: dict[str, dict[str, str]] = {}
        self.profile_digest = ""
        self.xdisplay = None
        self.last_pointer: tuple[int, int] | None = None
        self.dbus_monitor = None
        self.dbus_message: list[str] = []

    def stop(self, *_args: Any) -> None:
        self.running = False

    def _run(self, *args: str, timeout: float = 1.0) -> str:
        result = subprocess.run(
            args,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        if result.returncode != 0:
            return ""
        return result.stdout.strip()

    def scan_devices(self) -> None:
        discovered: set[str] = set()
        for sysfs_path in sorted(glob.glob("/sys/class/input/event*")):
            try:
                with open(
                    os.path.join(sysfs_path, "device/name"),
                    encoding="utf-8",
                ) as name_file:
                    name = name_file.read().strip()
            except OSError:
                continue
            kind = device_kind(name)
            if not kind:
                continue
            path = os.path.join("/dev/input", os.path.basename(sysfs_path))
            if not os.path.exists(path):
                continue
            discovered.add(path)
            if path in self.devices:
                continue
            try:
                device = InputDevice(path)
            except OSError as error:
                self.trace.emit("evdev_open_failed", path=path, name=name, error=str(error))
                continue
            self.devices[path] = device
            self.device_kinds[device.fd] = kind
            self.trace.emit(
                "evdev_attached",
                path=path,
                name=name,
                kind=kind,
                phys=device.phys,
            )

        for path in list(self.devices):
            if path in discovered:
                continue
            device = self.devices.pop(path)
            self.device_kinds.pop(device.fd, None)
            device.close()
            self.trace.emit("evdev_detached", path=path)

    def scan_composites(self) -> None:
        output = self._run(
            "busctl",
            "--system",
            "--list",
            "tree",
            SERVICE,
            timeout=2.0,
        )
        found = sorted(
            line.strip()
            for line in output.splitlines()
            if line.strip().startswith(
                "/org/shadowblip/InputPlumber/CompositeDevice"
            )
        )
        if found != self.composites:
            self.composites = found
            self.trace.emit("composites_changed", paths=found)

    def poll_properties(self) -> None:
        for path in self.composites:
            output = self._run(
                "busctl",
                "--system",
                "get-property",
                SERVICE,
                path,
                COMPOSITE_INTERFACE,
                "InterceptMode",
                "ProfileName",
                "TargetDevices",
                "SourceDevicePaths",
                timeout=2.0,
            )
            snapshot = parse_property_lines(output)
            if snapshot == self.snapshots.get(path):
                continue
            previous = self.snapshots.get(path)
            self.snapshots[path] = snapshot
            self.trace.emit(
                "composite_state",
                path=path,
                previous=previous,
                current=snapshot,
            )

    def poll_profile(self) -> None:
        try:
            with open(PROFILE_PATH, "rb") as profile_file:
                contents = profile_file.read()
        except OSError:
            return
        digest = hashlib.sha256(contents).hexdigest()
        if digest == self.profile_digest:
            return
        self.profile_digest = digest
        summary: dict[str, Any] = {"sha256": digest, "size": len(contents)}
        try:
            profile = json.loads(contents)
            summary.update(
                name=profile.get("name"),
                version=profile.get("version"),
                mappings=[item.get("name") for item in profile.get("mapping", [])],
                profile=profile,
            )
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            summary["parse_error"] = str(error)
        self.trace.emit("desktop_profile_file", **summary)

    def start_dbus_monitor(self) -> None:
        if self.dbus_monitor is not None and self.dbus_monitor.poll() is None:
            return
        self.dbus_monitor = subprocess.Popen(
            [
                "dbus-monitor",
                "--system",
                (
                    "type='signal',interface='org.shadowblip.Input.DBusDevice',"
                    "member='InputEvent'"
                ),
                (
                    "type='signal',interface='org.freedesktop.DBus.Properties',"
                    "member='PropertiesChanged',"
                    "path_namespace='/org/shadowblip/InputPlumber/CompositeDevice'"
                ),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        self.dbus_message.clear()
        self.trace.emit("dbus_monitor_started", child_pid=self.dbus_monitor.pid)

    def read_dbus_line(self) -> None:
        if self.dbus_monitor is None or self.dbus_monitor.stdout is None:
            return
        line = self.dbus_monitor.stdout.readline()
        if line == "":
            return
        stripped = line.rstrip()
        if stripped:
            self.dbus_message.append(stripped)
            return
        if self.dbus_message:
            self.trace.emit("dbus_signal", message="\n".join(self.dbus_message))
            self.dbus_message.clear()

    def poll_pointer(self) -> None:
        if self.xdisplay is None:
            try:
                self.xdisplay = display.Display(self.display_name)
                self.trace.emit("x11_connected", display=self.display_name)
            except Exception:
                return
        try:
            pointer = self.xdisplay.screen().root.query_pointer()
            position = (pointer.root_x, pointer.root_y)
        except Exception as error:
            self.trace.emit("x11_disconnected", error=str(error))
            try:
                self.xdisplay.close()
            except Exception:
                pass
            self.xdisplay = None
            self.last_pointer = None
            return
        if position != self.last_pointer:
            previous = self.last_pointer
            self.last_pointer = position
            self.trace.emit(
                "x11_pointer",
                console=False,
                previous=previous,
                current=position,
            )

    def read_evdev(self, device: InputDevice) -> None:
        kind = self.device_kinds.get(device.fd, "unknown")
        try:
            events = device.read()
        except OSError as error:
            self.trace.emit("evdev_read_failed", path=device.path, error=str(error))
            return
        for event in events:
            if not should_trace_event(kind, event.type, event.code):
                continue
            self.trace.emit(
                "evdev_event",
                console=False,
                path=device.path,
                name=device.name,
                kind=kind,
                event_type=ecodes.EV.get(event.type, str(event.type)),
                code=event_code_name(event.type, event.code),
                value=event.value,
            )

    def loop(self) -> None:
        self.trace.emit(
            "trace_started",
            display=self.display_name,
            trace_path=self.trace.path,
        )
        next_devices = 0.0
        next_composites = 0.0
        next_properties = 0.0
        next_profile = 0.0
        next_pointer = 0.0
        next_heartbeat = 0.0
        while self.running:
            now = time.monotonic()
            if now >= next_devices:
                self.scan_devices()
                next_devices = now + 1.0
            if now >= next_composites:
                self.scan_composites()
                next_composites = now + 2.0
            if now >= next_properties:
                self.poll_properties()
                next_properties = now + 0.2
            if now >= next_profile:
                self.poll_profile()
                next_profile = now + 1.0
            if now >= next_pointer:
                self.poll_pointer()
                next_pointer = now + 0.1
            if now >= next_heartbeat:
                self.trace.emit(
                    "heartbeat",
                    evdev_paths=sorted(self.devices),
                    composites=self.composites,
                )
                next_heartbeat = now + 10.0

            self.start_dbus_monitor()
            readers: list[Any] = list(self.devices.values())
            if self.dbus_monitor is not None and self.dbus_monitor.stdout is not None:
                readers.append(self.dbus_monitor.stdout)
            try:
                readable, _, _ = select.select(readers, [], [], 0.05)
            except (OSError, ValueError):
                continue
            for reader in readable:
                if self.dbus_monitor is not None and reader is self.dbus_monitor.stdout:
                    self.read_dbus_line()
                else:
                    self.read_evdev(reader)

        self.trace.emit("trace_stopped")
        if self.dbus_monitor is not None:
            self.dbus_monitor.terminate()
        for device in self.devices.values():
            device.close()
        if self.xdisplay is not None:
            self.xdisplay.close()


def main() -> int:
    display_name = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("DISPLAY", ":1")
    trace = TraceWriter(TRACE_PATH)
    diagnostics = InputDiagnostics(trace, display_name)
    signal.signal(signal.SIGTERM, diagnostics.stop)
    signal.signal(signal.SIGINT, diagnostics.stop)
    try:
        diagnostics.loop()
    finally:
        trace.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
