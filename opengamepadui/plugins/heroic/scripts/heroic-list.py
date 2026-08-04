#!/usr/bin/env python3
"""List installed Heroic games in a stable, machine-readable format."""

import argparse
import json
import os
import sys
from pathlib import Path


STORE_LABELS = {
    "legendary": "Epic Games",
    "gog": "GOG",
    "nile": "Amazon Prime Games",
    "sideload": "Jogos Manuais (Sideload)",
}


def expand_path(path_str):
    return Path(os.path.expanduser(os.path.expandvars(path_str.strip())))


def load_json_safe(filepath):
    if not filepath.is_file():
        return None
    try:
        with filepath.open("r", encoding="utf-8") as stream:
            return json.load(stream)
    except (OSError, ValueError) as error:
        print(f"[heroic-list] Erro ao ler {filepath}: {error}", file=sys.stderr)
        return None


def make_game(store, app_id, title=None, install_path=None):
    app_id = str(app_id or "").strip()
    if not app_id:
        return None

    title = str(title or "").strip()
    install_path = str(install_path or "").strip()
    if not title and install_path:
        title = Path(install_path).name
    if not title:
        title = app_id

    return {
        "provider_app_id": f"{store}:{app_id}",
        "app_id": app_id,
        "name": title,
        "store": store,
        "uri": f"heroic://launch/{store}/{app_id}",
        "install_path": install_path,
    }


def iter_records(data):
    if isinstance(data, dict):
        for key, value in data.items():
            if isinstance(value, dict):
                yield str(key), value
    elif isinstance(data, list):
        for value in data:
            if isinstance(value, dict):
                yield "", value


def process_epic(config_dir):
    paths = [
        config_dir / "legendaryConfig" / "legendary" / "installed.json",
        config_dir / "store" / "installed.json",
        config_dir / "installed.json",
    ]
    for path in paths:
        data = load_json_safe(path)
        if not data:
            continue

        games = []
        for key, item in iter_records(data):
            if item.get("is_dlc") is True or item.get("is_installed") is False:
                continue
            app_id = item.get("app_name") or item.get("appName") or key
            game = make_game(
                "legendary",
                app_id,
                item.get("title"),
                item.get("install_path") or item.get("path"),
            )
            if game:
                games.append(game)
        return games
    return []


def _gog_title_map(config_dir):
    paths = [
        config_dir / "gog_store" / "library.json",
        config_dir / "store_cache" / "gog_library.json",
    ]
    for path in paths:
        data = load_json_safe(path)
        if not isinstance(data, dict):
            continue
        mapping = {}
        for item in data.get("games", []):
            if not isinstance(item, dict):
                continue
            app_id = item.get("app_name") or item.get("appName") or item.get("id")
            if app_id and item.get("title"):
                mapping[str(app_id)] = str(item["title"])
        if mapping:
            return mapping
    return {}


def process_gog(config_dir):
    data = load_json_safe(config_dir / "gog_store" / "installed.json")
    if not isinstance(data, dict):
        return []

    installed = data.get("installed", [])
    if not isinstance(installed, list):
        return []

    # Most installed entries already have enough information. Only read the
    # larger library cache if at least one title cannot be inferred.
    needs_title_map = any(
        isinstance(item, dict)
        and not item.get("title")
        and not (item.get("install_path") or item.get("path"))
        for item in installed
    )
    title_map = _gog_title_map(config_dir) if needs_title_map else {}

    games = []
    for item in installed:
        if not isinstance(item, dict) or item.get("is_installed") is False:
            continue
        app_id = item.get("appName") or item.get("app_name") or item.get("id")
        title = item.get("title") or title_map.get(str(app_id))
        game = make_game(
            "gog",
            app_id,
            title,
            item.get("install_path") or item.get("path"),
        )
        if game:
            games.append(game)
    return games


def process_amazon(config_dir):
    paths = [
        config_dir / "nile_config" / "nile" / "installed.json",
        config_dir / "nile_store" / "installed.json",
    ]
    for path in paths:
        data = load_json_safe(path)
        if not data:
            continue

        games = []
        for key, item in iter_records(data):
            if item.get("is_installed") is False:
                continue
            app_id = item.get("id") or item.get("app_name") or item.get("appName") or key
            game = make_game(
                "nile",
                app_id,
                item.get("title"),
                item.get("path") or item.get("install_path"),
            )
            if game:
                games.append(game)
        return games
    return []


def _sideload_items(data):
    if isinstance(data, dict) and isinstance(data.get("games"), list):
        return data["games"]
    if isinstance(data, dict):
        return [value for value in data.values() if isinstance(value, dict)]
    if isinstance(data, list):
        return data
    return []


def process_sideload(config_dir):
    games = []
    sideload_dir = config_dir / "sideload_apps"
    library_file = sideload_dir / "library.json"

    data = load_json_safe(library_file)
    for item in _sideload_items(data):
        if not isinstance(item, dict) or item.get("is_installed") is False:
            continue
        app_id = item.get("app_name") or item.get("appName") or item.get("id")
        game = make_game(
            "sideload",
            app_id,
            item.get("title"),
            item.get("install_path") or item.get("path"),
        )
        if game:
            games.append(game)

    if sideload_dir.is_dir():
        for json_file in sorted(sideload_dir.glob("*.json")):
            if json_file.name == "library.json":
                continue
            item = load_json_safe(json_file)
            if not isinstance(item, dict) or item.get("is_installed") is False:
                continue
            app_id = item.get("app_name") or item.get("appName") or item.get("id")
            game = make_game(
                "sideload",
                app_id,
                item.get("title"),
                item.get("install_path") or item.get("path"),
            )
            if game:
                games.append(game)

    legacy = load_json_safe(config_dir / "sideload_apps.json")
    for item in _sideload_items(legacy):
        if not isinstance(item, dict) or item.get("is_installed") is False:
            continue
        app_id = item.get("app_name") or item.get("appName") or item.get("id")
        game = make_game(
            "sideload",
            app_id,
            item.get("title"),
            item.get("install_path") or item.get("path"),
        )
        if game:
            games.append(game)

    return games


def collect_games(config_dirs):
    games_by_id = {}
    for config_dir in config_dirs:
        if not config_dir.is_dir():
            print(
                f"[heroic-list] Diretório inexistente ou inválido: {config_dir}",
                file=sys.stderr,
            )
            continue
        for processor in (process_epic, process_gog, process_amazon, process_sideload):
            for game in processor(config_dir):
                games_by_id.setdefault(game["provider_app_id"], game)

    return sorted(
        games_by_id.values(),
        key=lambda game: (game["name"].casefold(), game["provider_app_id"]),
    )


def print_report(games, config_dirs, heroic_bin):
    print("=== Leitor de Jogos Instalados - Heroic CLI ===")
    print("Configuração:", ", ".join(str(path) for path in config_dirs))
    print("=" * 60)
    for store, label in STORE_LABELS.items():
        store_games = [game for game in games if game["store"] == store]
        print(f"\n  [{label}] ({len(store_games)} jogos)")
        print("-" * 60)
        if not store_games:
            print("  Nenhum jogo instalado encontrado nesta categoria.")
        for game in store_games:
            print(f"  Jogo:    {game['name']}")
            print(
                f"  Comando: {heroic_bin} --no-gui {game['uri']}\n"
            )
    print("=" * 60)
    print(f"Total mapeado: {len(games)}")


def default_config_dir():
    override = os.environ.get("HEROIC_CONFIG_DIR")
    if override:
        return expand_path(override)
    xdg_config = os.environ.get("XDG_CONFIG_HOME")
    if xdg_config:
        return expand_path(xdg_config) / "heroic"
    return Path.home() / ".config" / "heroic"


def parse_args():
    parser = argparse.ArgumentParser(
        description="Lista os jogos instalados no Heroic Games Launcher."
    )
    parser.add_argument(
        "config_dirs",
        nargs="*",
        type=expand_path,
        help="Pastas de configuração do Heroic (padrão: ~/.config/heroic).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="as_json",
        help="Imprime somente um array JSON em stdout.",
    )
    parser.add_argument(
        "--heroic-bin",
        default="/usr/sbin/heroic",
        help="Binário mostrado no relatório humano.",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    config_dirs = args.config_dirs or [default_config_dir()]
    games = collect_games(config_dirs)
    if args.as_json:
        json.dump(games, sys.stdout, ensure_ascii=False, separators=(",", ":"))
        sys.stdout.write("\n")
    else:
        print_report(games, config_dirs, args.heroic_bin)


if __name__ == "__main__":
    main()

