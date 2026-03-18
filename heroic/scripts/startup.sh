#!/bin/bash
set -e

source /opt/gow/bash-lib/utils.sh

if [ -n "$DISPLAY" ]; then
    gow_log "Waiting for X Server $DISPLAY to be available"
    /opt/gow/wait-x11
fi

gow_log "Starting Heroic Games Launcher..."

source /opt/gow/launch-comp.sh
launcher /usr/bin/heroic --no-sandbox
