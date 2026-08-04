#!/usr/bin/env python3
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


HELPER = Path(
    os.environ.get(
        "HEROIC_LIST_HELPER",
        Path(__file__).parents[1] / "plugins/heroic/scripts/heroic-list.py",
    )
)
SPEC = importlib.util.spec_from_file_location("heroic_list", HELPER)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class HeroicListTests(unittest.TestCase):
    def test_collects_all_stores_deduplicates_and_sorts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "legendaryConfig/legendary").mkdir(parents=True)
            (root / "legendaryConfig/legendary/installed.json").write_text(
                json.dumps(
                    {
                        "epic-id": {
                            "app_name": "epic-id",
                            "title": "Zulu Epic",
                            "install_path": "/games/epic",
                        }
                    }
                ),
                encoding="utf-8",
            )
            (root / "gog_store").mkdir()
            (root / "gog_store/installed.json").write_text(
                json.dumps(
                    {
                        "installed": [
                            {
                                "appName": "gog-id",
                                "title": "Alpha GOG",
                                "install_path": "/games/gog",
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )
            (root / "nile_config/nile").mkdir(parents=True)
            (root / "nile_config/nile/installed.json").write_text(
                json.dumps(
                    {
                        "amazon-id": {
                            "id": "amazon-id",
                            "title": "Middle Amazon",
                            "path": "/games/amazon",
                        }
                    }
                ),
                encoding="utf-8",
            )
            (root / "sideload_apps").mkdir()
            (root / "sideload_apps/library.json").write_text(
                json.dumps(
                    {
                        "games": [
                            {
                                "id": "manual-id",
                                "title": "Beta Manual",
                                "install_path": "/games/manual",
                            },
                            {
                                "id": "manual-id",
                                "title": "Duplicate",
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )

            games = MODULE.collect_games([root, root])

        self.assertEqual(
            [game["name"] for game in games],
            ["Alpha GOG", "Beta Manual", "Middle Amazon", "Zulu Epic"],
        )
        self.assertEqual(len({game["provider_app_id"] for game in games}), 4)
        self.assertEqual(games[0]["uri"], "heroic://launch/gog/gog-id")

    def test_skips_uninstalled_and_dlc_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "legendaryConfig/legendary"
            target.mkdir(parents=True)
            (target / "installed.json").write_text(
                json.dumps(
                    {
                        "dlc": {"app_name": "dlc", "title": "DLC", "is_dlc": True},
                        "gone": {
                            "app_name": "gone",
                            "title": "Gone",
                            "is_installed": False,
                        },
                    }
                ),
                encoding="utf-8",
            )

            games = MODULE.collect_games([root])

        self.assertEqual(games, [])


if __name__ == "__main__":
    unittest.main()
