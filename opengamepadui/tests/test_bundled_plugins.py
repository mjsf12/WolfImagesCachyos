#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path
from zipfile import BadZipFile, ZipFile


EXPECTED = {
    "wolf-desktop-input": {
        "version": "1.0.19",
        "required": ["plugin.json", "profiles/desktop_mouse.json"],
    },
    "wolf-gamescope-session": {
        "version": "1.0.0",
        "required": [
            "plugin.json",
            "core/overlay_policy.gd.remap",
            "core/overlay_reconciler.gd.remap",
            "core/overlay_transition.gd.remap",
        ],
    },
    "lutris": {
        "version": "2.0.1",
        "required": ["plugin.json", "core/library.tscn.remap"],
    },
    "heroic": {
        "version": "0.1.1",
        "required": [
            "plugin.json",
            "core/library.tscn.remap",
            "scripts/heroic-list.py",
        ],
    },
    "bottles": {
        "version": "0.1.2",
        "required": ["plugin.json", "core/library.tscn.remap"],
    },
}


def verify_archive(build_dir: Path, plugin_id: str, contract: dict) -> list[str]:
    errors = []
    archive = build_dir / f"{plugin_id}.zip"
    if not archive.is_file():
        return [f"missing archive: {archive}"]
    try:
        with ZipFile(archive) as package:
            names = set(package.namelist())
            root = f"plugins/{plugin_id}/"
            foreign = sorted(
                name
                for name in names
                if name.startswith("plugins/") and not name.startswith(root)
            )
            if foreign:
                errors.append(f"{archive.name}: contains foreign plugin files: {foreign}")
            tests = sorted(name for name in names if "_test.gd" in name)
            if tests:
                errors.append(f"{archive.name}: contains test sources: {tests}")
            metadata_path = root + "plugin.json"
            if metadata_path not in names:
                errors.append(f"{archive.name}: missing {metadata_path}")
                return errors
            metadata = json.loads(package.read(metadata_path))
            if metadata.get("plugin.id") != plugin_id:
                errors.append(f"{archive.name}: plugin.id is {metadata.get('plugin.id')!r}")
            if metadata.get("plugin.version") != contract["version"]:
                errors.append(
                    f"{archive.name}: version is {metadata.get('plugin.version')!r}, "
                    f"expected {contract['version']!r}"
                )
            entrypoint = metadata.get("entrypoint", "")
            entrypoint_candidates = {
                root + entrypoint,
                root + entrypoint.removesuffix(".gd") + ".gdc",
                root + entrypoint + ".remap",
            }
            if not names.intersection(entrypoint_candidates):
                errors.append(f"{archive.name}: compiled entrypoint is missing")
            for required in contract["required"]:
                if root + required not in names:
                    errors.append(f"{archive.name}: missing {root + required}")
            if plugin_id == "heroic":
                if any(name.endswith(".base64") for name in names):
                    errors.append("heroic.zip: encoded source icon leaked into package")
                if not any(name.endswith("heroic.png.import") for name in names):
                    errors.append("heroic.zip: imported Heroic icon is missing")
    except (BadZipFile, OSError, ValueError, json.JSONDecodeError) as error:
        errors.append(f"{archive.name}: invalid package: {error}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("build_dir", type=Path)
    args = parser.parse_args()
    errors = []
    for plugin_id, contract in EXPECTED.items():
        errors.extend(verify_archive(args.build_dir, plugin_id, contract))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Verified {len(EXPECTED)} isolated OpenGamepadUI plugin archives")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
