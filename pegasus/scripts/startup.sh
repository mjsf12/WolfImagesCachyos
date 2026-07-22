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

    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=XFCE
    export XDG_SESSION_DESKTOP=xfce
    export GDK_BACKEND=x11
    export DISPLAY=:0
    export DESKTOP_SESSION=xfce
    export QT_QPA_PLATFORM=xcb
    export QT_AUTO_SCREEN_SCALE_FACTOR=1
    export _JAVA_AWT_WM_NONREPARENTING=1
    export MOZ_ENABLE_WAYLAND=0
    export GTK_ICON_THEME_NAME=ePapirus-Dark

    # Imagens antigas podem ter persistido os aliases genericos do XFCE.
    # Migra somente esses valores; uma fonte escolhida pelo usuario e preservada.
    XFCE_XSETTINGS_FILE="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
    if [ -f "$XFCE_XSETTINGS_FILE" ]; then
        sed -i \
            -e 's/value="Sans 10"/value="Noto Sans 10"/' \
            -e 's/value="Monospace 10"/value="Noto Sans Mono 10"/' \
            "$XFCE_XSETTINGS_FILE"
    fi

    XFCE_XFWM4_FILE="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    if [ -f "$XFCE_XFWM4_FILE" ]; then
        sed -i \
            's/value="Sans Bold 9"/value="Noto Sans Bold 9"/' \
            "$XFCE_XFWM4_FILE"
    fi

    REAL_WAYLAND_DISPLAY=$WAYLAND_DISPLAY
    unset WAYLAND_DISPLAY

    dbus-run-session -- bash -c \
        "WAYLAND_DISPLAY=$REAL_WAYLAND_DISPLAY Xwayland :0 & sleep 2 && startxfce4"

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
