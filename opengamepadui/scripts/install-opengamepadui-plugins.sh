#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:-/usr/share/opengamepadui/plugins}"
target_dir="${2:-${HOME}/.local/share/opengamepadui/plugins}"

mkdir -p "${target_dir}"
installed=0
for plugin_source in "${source_dir}"/*.zip; do
    if [ ! -f "${plugin_source}" ]; then
        continue
    fi
    install -m 0644 \
        "${plugin_source}" \
        "${target_dir}/$(basename "${plugin_source}")"
    installed=$((installed + 1))
done

if [ "${installed}" -eq 0 ]; then
    echo "No bundled OpenGamepadUI plugins found in ${source_dir}" >&2
    exit 1
fi

echo "Installed ${installed} bundled OpenGamepadUI plugin archives"
