#!/usr/bin/env bash
set -u

source /opt/gow/bash-lib/utils.sh

start_daemon() {
    local process_name="$1"
    local executable="$2"

    if ! command -v "${executable}" >/dev/null 2>&1; then
        gow_log "WARN: ${executable} is not installed; ${process_name} was not started"
        return
    fi

    if pgrep -x "${process_name}" >/dev/null 2>&1; then
        gow_log "${process_name} is already running"
        return
    fi

    gow_log "Starting ${process_name}..."
    "${executable}" &
    local daemon_pid=$!

    # Detecta falhas imediatas sem bloquear a subida do frontend.
    sleep 1
    if kill -0 "${daemon_pid}" 2>/dev/null; then
        gow_log "${process_name} started (pid ${daemon_pid})"
    else
        wait "${daemon_pid}" 2>/dev/null || true
        gow_log "WARN: ${process_name} exited during startup"
    fi
}

maintain_inputplumber_menu_intercept() {
    local current_mode
    local device_path

    # OpenGamepadUI receives menu input from InputPlumber's D-Bus target, but
    # a newly-created composite starts in mode 0 (events go only to regular
    # targets). Wolf can create the controller before Card UI finishes wiring
    # its device-added callback, leaving that initial transition missed.
    #
    # Promote only mode 0 to mode 2. OpenGamepadUI remains free to switch to
    # mode 1 while a game is active and back to mode 2 when the menu returns.
    while true; do
        while IFS= read -r device_path; do
            case "${device_path}" in
                /org/shadowblip/InputPlumber/CompositeDevice*) ;;
                *) continue ;;
            esac

            current_mode="$(
                timeout 2 busctl --system get-property \
                    org.shadowblip.InputPlumber \
                    "${device_path}" \
                    org.shadowblip.Input.CompositeDevice \
                    InterceptMode 2>/dev/null
            )" || continue

            if [ "${current_mode}" != "u 0" ]; then
                continue
            fi

            if timeout 2 busctl --system set-property \
                org.shadowblip.InputPlumber \
                "${device_path}" \
                org.shadowblip.Input.CompositeDevice \
                InterceptMode u 2 >/dev/null 2>&1; then
                gow_log "Enabled InputPlumber D-Bus menu input for ${device_path}"
            fi
        done < <(
            timeout 2 busctl --system --list tree \
                org.shadowblip.InputPlumber 2>/dev/null || true
        )

        sleep 1
    done
}

if [ "${START_INPUTPLUMBER:-1}" = "1" ]; then
    # Wolf hotplugs the Moonlight gamepad only after the application container
    # has started. InputPlumber creates its evdev inotify watcher only when
    # /dev/input already exists, so create the empty directory first.
    mkdir -p /dev/input
    start_daemon inputplumber inputplumber
    maintain_inputplumber_menu_intercept &
fi

if [ "${START_POWERSTATION:-0}" = "1" ]; then
    start_daemon powerstation powerstation
fi
