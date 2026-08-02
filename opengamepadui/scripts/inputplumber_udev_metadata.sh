#!/usr/bin/env bash
set -euo pipefail

readonly INPUTPLUMBER_GAMEPAD_NAME="Microsoft Xbox Series S|X Controller"

register_gamepad() {
    local device_name="$1"
    local major_number="$2"
    local minor_number="$3"
    local data_dir="${WOLF_UDEV_DATA_DIR:-/run/udev/data}"
    local destination
    local temporary

    if [ "${device_name}" != "${INPUTPLUMBER_GAMEPAD_NAME}" ]; then
        echo "refusing to register unexpected input device: ${device_name}" >&2
        return 1
    fi
    if [[ ! "${major_number}" =~ ^[0-9]+$ ]] || \
        [[ ! "${minor_number}" =~ ^[0-9]+$ ]]; then
        echo "invalid input device number: ${major_number}:${minor_number}" >&2
        return 1
    fi

    mkdir -p "${data_dir}"
    destination="${data_dir}/c${major_number}:${minor_number}"
    temporary="$(mktemp "${data_dir}/.inputplumber-gamepad.XXXXXX")"
    trap 'rm -f -- "${temporary}"' RETURN

    # Wolf mounts a private udev database into application containers. Without
    # this record, libudev sees the uinput event node but Wine/SDL do not
    # classify or enumerate it as a joystick.
    printf '%s\n' \
        'E:ID_INPUT=1' \
        'E:ID_INPUT_JOYSTICK=1' \
        'E:ID_BUS=usb' \
        'G:seat' \
        'G:uaccess' \
        'Q:seat' \
        'Q:uaccess' \
        'V:1' > "${temporary}"
    chmod 0644 "${temporary}"
    mv -f -- "${temporary}" "${destination}"
    trap - RETURN

    printf '%s\n' "${destination}"
}

self_test() {
    local test_dir
    local event_result
    local expected
    local js_result

    test_dir="$(mktemp -d)"
    trap "rm -rf -- $(printf '%q' "${test_dir}")" EXIT
    event_result="$(
        WOLF_UDEV_DATA_DIR="${test_dir}" \
            register_gamepad "${INPUTPLUMBER_GAMEPAD_NAME}" 13 76
    )"
    js_result="$(
        WOLF_UDEV_DATA_DIR="${test_dir}" \
            register_gamepad "${INPUTPLUMBER_GAMEPAD_NAME}" 13 2
    )"
    expected="$(printf '%s\n' \
        'E:ID_INPUT=1' \
        'E:ID_INPUT_JOYSTICK=1' \
        'E:ID_BUS=usb' \
        'G:seat' \
        'G:uaccess' \
        'Q:seat' \
        'Q:uaccess' \
        'V:1')"

    [ "${event_result}" = "${test_dir}/c13:76" ]
    [ "${js_result}" = "${test_dir}/c13:2" ]
    [ "$(cat "${event_result}")" = "${expected}" ]
    [ "$(cat "${js_result}")" = "${expected}" ]
    [ "$(stat -Lc '%a' "${event_result}")" = "644" ]
    [ "$(stat -Lc '%a' "${js_result}")" = "644" ]
    if WOLF_UDEV_DATA_DIR="${test_dir}" \
        register_gamepad 'Unexpected Controller' 13 77 >/dev/null 2>&1; then
        echo 'unexpected device was accepted' >&2
        return 1
    fi

    rm -rf -- "${test_dir}"
    trap - EXIT
    echo 'inputplumber udev metadata self-test passed'
}

case "${1:-}" in
    --self-test)
        self_test
        ;;
    '')
        echo "usage: $0 <device-name> <major> <minor>" >&2
        exit 2
        ;;
    *)
        if [ "$#" -ne 3 ]; then
            echo "usage: $0 <device-name> <major> <minor>" >&2
            exit 2
        fi
        register_gamepad "$1" "$2" "$3"
        ;;
esac
