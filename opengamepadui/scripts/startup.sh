#!/usr/bin/env bash
set -e

source /opt/gow/bash-lib/utils.sh

ensure_writable_dir() {
    local directory="$1"
    local probe

    if ! mkdir -p "${directory}"; then
        gow_log "FATAL: Could not create ${directory}"
        gow_log "Fix the bind mount on the host with: chown -R 1000:1000 <host-directory>"
        exit 1
    fi

    probe="${directory}/.gow-write-test.$$"
    if ! touch "${probe}" 2>/dev/null; then
        gow_log "FATAL: User $(id -u):$(id -g) cannot write to ${directory}"
        gow_log "Fix the bind mount on the host with: chown -R 1000:1000 <host-directory>"
        exit 1
    fi
    rm -f "${probe}"
}

# Mantém o desktop de manutenção exatamente como na imagem Pegasus.
if [ "${RUN_XFCE:-0}" = "1" ]; then
    exec /opt/gow/startup-pegasus.sh
fi

ensure_writable_dir "${HOME}/.config/gamescope"
ensure_writable_dir "${HOME}/.local/share/opengamepadui"

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

# Se o hook Vulkan da camada Gamescope WSI falhar, ele tenta abrir um diálogo
# com Zenity. Como o Zenity herda a mesma camada Vulkan, isso entra em recursão
# e bloqueia o Godot antes de criar a janela principal. Gamescope 3.16 fornece
# esta opção para seguir com o swapchain normal sem abrir o diálogo.
export GAMESCOPE_ZENITY_DISABLE="${GAMESCOPE_ZENITY_DISABLE:-1}"

# O launcher oficial configura isto no systemd --user. No container executamos
# a sessão diretamente, então a variável deve ser herdada pelo D-Bus de usuário.
export XDG_DESKTOP_PORTAL_DIR=""

# O script do ChimeraOS lê este arquivo antes de verificar sessões curtas.
touch /tmp/chimeraos-short-session-tracker

exec dbus-run-session -- "${session_runner}" opengamepadui
