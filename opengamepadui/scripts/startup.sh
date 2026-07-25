#!/usr/bin/env bash
set -e

source /opt/gow/bash-lib/utils.sh

# Mantém o desktop de manutenção exatamente como na imagem Pegasus.
if [ "${RUN_XFCE:-0}" = "1" ]; then
    exec /opt/gow/startup-pegasus.sh
fi

if [ -n "${DISPLAY:-}" ]; then
    gow_log "Waiting for X Server ${DISPLAY} to be available"
    /opt/gow/wait-x11
fi

session_runner=/usr/share/gamescope-session-plus/gamescope-session-plus
if [ ! -x "${session_runner}" ]; then
    gow_log "FATAL: Official gamescope-session-plus runner was not found"
    exit 1
fi

gow_log "Starting OpenGamepadUI in the official Gamescope session..."

# gamescope-session-plus usa estas variáveis para o tamanho externo e interno.
# Os nomes GAMESCOPE_* continuam compatíveis com as demais imagens do projeto.
export SCREEN_WIDTH="${SCREEN_WIDTH:-${GAMESCOPE_WIDTH:-1920}}"
export SCREEN_HEIGHT="${SCREEN_HEIGHT:-${GAMESCOPE_HEIGHT:-1080}}"
export INTERNAL_WIDTH="${INTERNAL_WIDTH:-${GAMESCOPE_INTERNAL_WIDTH:-${SCREEN_WIDTH}}}"
export INTERNAL_HEIGHT="${INTERNAL_HEIGHT:-${GAMESCOPE_INTERNAL_HEIGHT:-${SCREEN_HEIGHT}}}"

# Replica o ambiente definido pelo launcher oficial sem depender de SDDM ou de
# uma instância systemd --user, que não existem dentro do container do Wolf.
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=gamescope
export XDG_SESSION_DESKTOP=gamescope
export DESKTOP_SESSION=gamescope

exec dbus-run-session -- "${session_runner}" opengamepadui
