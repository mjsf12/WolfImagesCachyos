#!/bin/bash
set -e

source /opt/gow/bash-lib/utils.sh

# Se DISPLAY estiver definido (modo Xwayland), espera o servidor X ficar disponível
if [ -n "$DISPLAY" ]; then
    gow_log "Waiting for X Server $DISPLAY to be available"
    /opt/gow/wait-x11
fi

gow_log "Starting Firefox..."

# Usa o launch-comp.sh para iniciar via Gamescope, Sway ou direto
# Controlado pelas env vars: RUN_GAMESCOPE=1 ou RUN_SWAY=1
# Se nenhuma estiver definida, executa o firefox direto
source /opt/gow/launch-comp.sh
launcher firefox --no-remote
