#!/usr/bin/env bash
set -u

source /opt/gow/bash-lib/utils.sh

# The official InputPlumber polkit policy requires this group for profile,
# intercept, target and mouse D-Bus mutations. Run after the base entrypoint's
# device-group setup so its usermod -G cannot remove this membership again.
/opt/gow/authorize-inputplumber-user "${UNAME:-gow}"

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

start_inputplumber_x11_bridge() {
    local bridge=/opt/gow/inputplumber_x11_bridge.py
    local session_user="${UNAME:-gow}"

    if [ ! -x "${bridge}" ]; then
        gow_log "WARN: InputPlumber X11 bridge is not installed"
        return
    fi
    if pgrep -f "${bridge}" >/dev/null 2>&1; then
        gow_log "InputPlumber X11 bridge is already running"
        return
    fi

    # Xwayland authorizes local clients by UID. Run as the session user and let
    # the bridge wait for Gamescope to create display :1.
    gow_log "Starting InputPlumber X11 desktop bridge..."
    runuser -u "${session_user}" -- env DISPLAY=:1 "${bridge}" :1 &
    gow_log "InputPlumber X11 desktop bridge started (pid $!)"
}

materialize_inputplumber_desktop_targets() {
    local attempt
    local device_name
    local device_number
    local event_name
    local event_path
    local major_number
    local minor_number
    local node_path
    local targets_found

    # Wolf gives application containers a private /dev/input. InputPlumber can
    # create uinput devices in the kernel, but there is no udev daemon here to
    # create their event nodes in that private directory. Materialize the two
    # desktop targets before Gamescope starts and enumerates input devices.
    for attempt in $(seq 1 50); do
        targets_found=0
        for event_path in /sys/class/input/event*; do
            [ -e "${event_path}" ] || continue
            device_name="$(cat "${event_path}/device/name" 2>/dev/null || true)"
            case "${device_name}" in
                "InputPlumber Mouse"|"InputPlumber Keyboard") ;;
                *) continue ;;
            esac

            event_name="${event_path##*/}"
            device_number="$(cat "${event_path}/dev" 2>/dev/null || true)"
            case "${device_number}" in
                *:*) ;;
                *) continue ;;
            esac
            major_number="${device_number%%:*}"
            minor_number="${device_number##*:}"
            node_path="/dev/input/${event_name}"

            if [ ! -e "${node_path}" ]; then
                if mknod "${node_path}" c "${major_number}" "${minor_number}"; then
                    chmod 0666 "${node_path}"
                    gow_log "Created ${node_path} for ${device_name}"
                else
                    gow_log "WARN: failed to create ${node_path} for ${device_name}"
                    continue
                fi
            fi
            targets_found=$((targets_found + 1))
        done

        if [ "${targets_found}" -ge 2 ]; then
            gow_log "InputPlumber desktop input targets are ready"
            return 0
        fi
        sleep 0.1
    done

    gow_log "WARN: InputPlumber desktop input targets were not ready before Gamescope startup"
    return 1
}

maintain_inputplumber_menu_intercept() {
    local current_mode
    local device_name
    local device_path
    declare -A generic_chord_configured=()

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

            if [ "${current_mode}" = "u 0" ]; then
                if timeout 2 busctl --system set-property \
                    org.shadowblip.InputPlumber \
                    "${device_path}" \
                    org.shadowblip.Input.CompositeDevice \
                    InterceptMode u 2 >/dev/null 2>&1; then
                    gow_log "Enabled InputPlumber D-Bus menu input for ${device_path}"
                fi
            fi

            # Card UI writes its own Guide activation directly to the D-Bus
            # composite during startup. That bypasses the global state exposed
            # to plugins, so a plugin cannot reliably detect the overwrite.
            # Keep the generic Moonlight chord authoritative only for Wolf's
            # virtual gamepad; leave physical/local controllers untouched.
            if [ "${ENABLE_GENERIC_GUIDE_CHORD:-1}" != "1" ]; then
                continue
            fi
            device_name="$(
                timeout 2 busctl --system get-property \
                    org.shadowblip.InputPlumber \
                    "${device_path}" \
                    org.shadowblip.Input.CompositeDevice \
                    Name 2>/dev/null
            )" || continue
            if [ "${device_name}" != 's "Wolf Virtual Gamepad"' ]; then
                continue
            fi

            # Rewriting activation while Start/Select are physically held can
            # restart InputPlumber's chord state and leave interception stuck.
            # Configure each composite once; the plugin performs its own late
            # startup write after Card UI has initialized.
            if [ -n "${generic_chord_configured[${device_path}]:-}" ]; then
                continue
            fi

            if timeout 2 busctl --system call \
                org.shadowblip.InputPlumber \
                "${device_path}" \
                org.shadowblip.Input.CompositeDevice \
                SetInterceptActivation ass 2 \
                Gamepad:Button:Start \
                Gamepad:Button:Select \
                Gamepad:Button:Guide >/dev/null 2>&1; then
                generic_chord_configured["${device_path}"]=1
                gow_log "Enabled generic Guide chord for ${device_path}"
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
    materialize_inputplumber_desktop_targets || true
    start_inputplumber_x11_bridge
    maintain_inputplumber_menu_intercept &
fi

if [ "${START_POWERSTATION:-0}" = "1" ]; then
    start_daemon powerstation powerstation
fi
