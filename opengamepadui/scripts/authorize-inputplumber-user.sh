#!/usr/bin/env bash
set -euo pipefail

source /opt/gow/bash-lib/utils.sh

session_user="${1:-${UNAME:-}}"
if [ -z "${session_user}" ]; then
    session_user="$(id -un "${PUID:-1000}")"
fi

if ! id "${session_user}" >/dev/null 2>&1; then
    gow_log "FATAL: OpenGamepadUI session user '${session_user}' does not exist"
    exit 1
fi

# InputPlumber's upstream polkit rule authorizes mutating D-Bus calls only for
# members of inputplumber or wheel. The base image rebuilds the dynamic user's
# supplementary groups before running init hooks, so append this group here,
# after device groups have been configured and before setpriv --init-groups.
if ! getent group inputplumber >/dev/null 2>&1; then
    groupadd --system inputplumber
fi

if ! id -nG "${session_user}" | tr ' ' '\n' | grep -qx inputplumber; then
    usermod --append --groups inputplumber "${session_user}"
fi

if ! id -nG "${session_user}" | tr ' ' '\n' | grep -qx inputplumber; then
    gow_log "FATAL: failed to authorize '${session_user}' for InputPlumber D-Bus actions"
    exit 1
fi

gow_log "Authorized user '${session_user}' for InputPlumber D-Bus actions"
