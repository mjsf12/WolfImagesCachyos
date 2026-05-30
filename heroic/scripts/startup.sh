#!/bin/bash
set -e

source /opt/gow/bash-lib/utils.sh

if [ -n "$DISPLAY" ]; then
    gow_log "Waiting for X Server $DISPLAY to be available"
    /opt/gow/wait-x11
fi

gow_log "Starting Heroic Games Launcher..."

source /opt/gow/launch-comp.sh

configure_heroic_close_behavior() {
    if [ "${HEROIC_EXIT_ON_WINDOW_CLOSE:-1}" != "1" ]; then
        return
    fi

    local config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/heroic"
    local config_file tmp

    for config_file in "${config_dir}/config.json" "${config_dir}/store/config.json"; do
        [ -f "${config_file}" ] || continue

        tmp="$(mktemp)"
        if jq '
            if has("defaultSettings") then
                .defaultSettings.noTrayIcon = true |
                .defaultSettings.exitToTray = false |
                .defaultSettings.startInTray = false |
                .defaultSettings.minimizeOnLaunch = false
            else . end |
            if has("settings") then
                .settings.noTrayIcon = true |
                .settings.exitToTray = false |
                .settings.startInTray = false |
                .settings.minimizeOnLaunch = false
            else . end
        ' "${config_file}" > "${tmp}"; then
            mv "${tmp}" "${config_file}"
            gow_log "Configured Heroic to exit when its window closes: ${config_file}"
        else
            rm -f "${tmp}"
            gow_log "WARN: Failed to update Heroic close behavior in ${config_file}"
        fi
    done
}

configure_heroic_close_behavior

cleanup() {
    if [ -n "${input_chmod_pid:-}" ]; then
        kill "${input_chmod_pid}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

(while true; do
    chmod a+rw /dev/input/event* 2>/dev/null || true
    sleep 2
done) &
input_chmod_pid=$!

heroic_args=(/usr/bin/heroic --no-sandbox)
if [ -n "${HEROIC_STARTUP_FLAGS:-}" ]; then
    # HEROIC_STARTUP_FLAGS comes from the Wolf app profile and is controlled by the host config.
    read -r -a startup_flags <<< "${HEROIC_STARTUP_FLAGS}"
    heroic_args+=("${startup_flags[@]}")
else
    heroic_args+=(--ozone-platform=x11 --enable-features=UseOzonePlatform,WaylandWindowDecorations GenericName=gs_hgl)
fi

launcher "${heroic_args[@]}"
