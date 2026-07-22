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
    export GDK_BACKEND=x11
    export XDG_CURRENT_DESKTOP=XFCE
    export XDG_SESSION_DESKTOP=xfce

    unset WAYLAND_DISPLAY

    dbus-run-session -- xfce4-session
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
