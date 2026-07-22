#!/bin/bash
set -e

source /opt/gow/bash-lib/utils.sh

if [ -n "$DISPLAY" ]; then
    gow_log "Waiting for X Server $DISPLAY to be available"
    /opt/gow/wait-x11
fi

# ── Modo XFCE ──────────────────────────────────────────
if [ "${RUN_XFCE}" = "1" ]; then
    gow_log "[XFCE] Starting XFCE desktop session..."

    export GAMESCOPE_WIDTH=${GAMESCOPE_WIDTH:-1920}
    export GAMESCOPE_HEIGHT=${GAMESCOPE_HEIGHT:-1080}
    export GAMESCOPE_REFRESH=${GAMESCOPE_REFRESH:-60}

    export SWAYSOCK=${XDG_RUNTIME_DIR}/sway.socket
    export XDG_CURRENT_DESKTOP=XFCE
    export XDG_SESSION_DESKTOP=xfce

    mkdir -p "$HOME/.config/sway"
    cp /cfg/sway/config "$HOME/.config/sway/config"

    echo "output * resolution ${GAMESCOPE_WIDTH}x${GAMESCOPE_HEIGHT} position 0,0" >> "$HOME/.config/sway/config"

    # XFCE apps precisam de XDG_SESSION_TYPE=x11 para usar XWayland
    export XDG_SESSION_TYPE=x11

    cat >> "$HOME/.config/sway/config" << 'SWAYCONF'

# XFCE desktop
exec_always xfsettingsd
exec_always xfce4-panel
exec_always xfdesktop
exec_always thunar --daemon

bindsym $mod+Return exec xfce4-terminal
# Nota: waybar continua visivel. Remova ou comente a linha 'bar swaybar_command waybar'
# em /cfg/sway/config se quiser ocultar.

# Sessao XFCE — quando o usuario deslogar, sway encerra junto
exec xfce4-session --skip-window-manager && swaymsg exit

SWAYCONF

    dbus-run-session -- sway --unsupported-gpu
    exit $?
fi

# ── Modo normal (Pegasus) ──────────────────────────────
gow_log "Starting Pegasus Frontend..."

source /opt/gow/launch-comp.sh

cat > /tmp/pegasus-wrapper.sh << 'WRAPPER'
#!/bin/bash

# Pegasus nao funciona com Wayland, forcar X11 via XWayland
export XDG_SESSION_TYPE=x11
unset WAYLAND_DISPLAY

exec /usr/sbin/pegasus-fe "$@"
WRAPPER
chmod +x /tmp/pegasus-wrapper.sh

pegasus_args=(/tmp/pegasus-wrapper.sh)
if [ -n "${PEGASUS_STARTUP_FLAGS:-}" ]; then
    read -r -a startup_flags <<< "${PEGASUS_STARTUP_FLAGS}"
    pegasus_args+=("${startup_flags[@]}")
fi

launcher "${pegasus_args[@]}"
