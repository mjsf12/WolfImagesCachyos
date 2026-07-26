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

if [ "${START_INPUTPLUMBER:-1}" = "1" ]; then
    # Wolf hotplugs the Moonlight gamepad only after the application container
    # has started. InputPlumber creates its evdev inotify watcher only when
    # /dev/input already exists, so create the empty directory first.
    mkdir -p /dev/input
    start_daemon inputplumber inputplumber
fi

if [ "${START_POWERSTATION:-0}" = "1" ]; then
    start_daemon powerstation powerstation
fi
