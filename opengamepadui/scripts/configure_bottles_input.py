#!/usr/bin/env python3
"""Configure Bottles to pass the authoritative InputPlumber controller route."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from typing import Any


EXPECTED_ENVIRONMENT = {
    "PROTON_DISABLE_HIDRAW": "1",
    "PROTON_PREFER_SDL": "1",
    "PROTON_USE_SDL": "1",
    "SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT": "0x045E/0x0B12",
}


def pending_updates(bottles: dict[str, Any]) -> list[tuple[str, str, str]]:
    updates: list[tuple[str, str, str]] = []
    for bottle_name, config in bottles.items():
        if not isinstance(config, dict):
            continue
        environment = config.get("Environment_Variables", {})
        if not isinstance(environment, dict):
            environment = {}
        for key, value in EXPECTED_ENVIRONMENT.items():
            if str(environment.get(key, "")) != value:
                updates.append((bottle_name, key, value))
    return updates


def self_test() -> int:
    configured = {"Configured": {"Environment_Variables": EXPECTED_ENVIRONMENT.copy()}}
    assert pending_updates(configured) == []

    updates = pending_updates({"Needs Input": {"Environment_Variables": {}}})
    assert updates == [
        ("Needs Input", key, value) for key, value in EXPECTED_ENVIRONMENT.items()
    ]
    print("Bottles input route self-test passed")
    return 0


def configure() -> int:
    bottles_cli = os.environ.get("BOTTLES_CLI", "bottles-cli")
    executable = shutil.which(bottles_cli)
    if executable is None:
        print("bottles-cli is not installed; skipping Bottles input route", file=sys.stderr)
        return 0

    listed = subprocess.run(
        [executable, "--json", "list", "bottles"],
        check=False,
        capture_output=True,
        text=True,
    )
    if listed.returncode != 0:
        print(
            "unable to list Bottles: " + (listed.stderr.strip() or "unknown error"),
            file=sys.stderr,
        )
        return 1

    try:
        bottles = json.loads(listed.stdout)
    except json.JSONDecodeError as error:
        print(f"unable to parse Bottles list: {error}", file=sys.stderr)
        return 1
    if not isinstance(bottles, dict):
        print("unexpected Bottles list response", file=sys.stderr)
        return 1

    updates = pending_updates(bottles)
    for bottle_name, key, value in updates:
        edited = subprocess.run(
            [
                executable,
                "edit",
                "--bottle",
                bottle_name,
                "--env-var",
                f"{key}={value}",
            ],
            check=False,
        )
        if edited.returncode != 0:
            print(f"failed to configure Bottles input for {bottle_name}", file=sys.stderr)
            return edited.returncode

    if updates:
        configured_names = sorted({name for name, _key, _value in updates})
        print("Configured Bottles input route: " + ", ".join(configured_names))
    else:
        print("Bottles input route is already configured")
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        raise SystemExit(self_test())
    if sys.argv[1:]:
        print(f"usage: {sys.argv[0]} [--self-test]", file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(configure())
