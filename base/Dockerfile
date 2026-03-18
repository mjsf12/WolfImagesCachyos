# Usa a imagem oficial do Arch Linux
FROM cachyos/cachyos-v4:latest

LABEL maintainer="seu_nome@email.com"

# Habilita multilib para pacotes lib32-* ANTES do primeiro pacman
RUN echo -e "[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf

ENV \
    PUID=1000 \
    PGID=1000 \
    UMASK=000 \
    UNAME="gow" \
    HOME="/home/gow" \
    TZ="America/Fortaleza"

# Atualiza o sistema e instala todos os pacotes em um único RUN para reduzir camadas
# --noconfirm (sem hífen em "no") é o correto no pacman
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        base-devel git wget curl vim \
        ca-certificates fuse2 nss jq \
        util-linux dbus \
        wayland libegl libgl \
        mesa vulkan-mesa-layers \
        xorg-xdpyinfo \
        gamescope xorg-xwayland sway \
        waybar ttf-font-awesome noto-fonts-cjk \
        pulseaudio sdl2 ncurses \
        kitty nano psmisc \
        mangohud lib32-mangohud \
        xdg-desktop-portal xdg-desktop-portal-gtk \
        nvidia-utils lib32-nvidia-utils \
        glibc-locales && \
    pacman -Scc --noconfirm

# Configura localização
# glibc-locales provê os arquivos de definição de locale necessários para locale-gen
RUN sed -i 's/#pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' /etc/locale.gen && \
    sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen

# Cria a estrutura de diretórios do GOW
RUN mkdir -p /opt/gow/bash-lib /etc/cont-init.d /run/user && \
    mkdir -p /etc/ld.so.conf.d && \
    echo -e "/usr/nvidia/lib\n/usr/nvidia/lib32" > /etc/ld.so.conf.d/nvidia.conf

# Biblioteca utilitária (sourced por todos os scripts GOW)
RUN cat > /opt/gow/bash-lib/utils.sh << 'EOF'
#!/usr/bin/env bash
gow_log() {
    echo "$(date +"[%Y-%m-%d %H:%M:%S]") $*"
}
join_by() { local IFS="$1"; shift; echo "$*"; }
github_download() {
    curl -H "X-GitHub-Api-Version: ${GITHUB_REST_VERSION:-2022-11-28}" \
        https://api.github.com/repos/$1/releases/latest | \
        jq $2 | xargs wget -O $3
}
EOF

# Script que garante acesso do usuário aos grupos dos dispositivos
RUN cat > /opt/gow/ensure-groups << 'EOF'
#!/usr/bin/env bash
set -e
source /opt/gow/bash-lib/utils.sh
declare -A group_map
for dev in "$@"; do
    if [ -e "$dev" ]; then
        dev_group=$(stat -c "%G" "$dev")
        dev_gid=$(stat -c "%g" "$dev")
        if [ "$dev_group" = "UNKNOWN" ]; then
            new_name="gow-gid-$dev_gid"
            groupadd -g "$dev_gid" "$new_name"
            group_map[$new_name]=1
        else
            group_map[$dev_group]=1
        fi
        if [ "$(stat -c "%a" "$dev" | cut -c2)" -lt 6 ]; then
            chmod g+rw "$dev"
        fi
    else
        gow_log "Path '$dev' is not present."
    fi
done
groups=$(join_by "," "${!group_map[@]}")
if [ "$groups" != "" ]; then
    gow_log "Adding user '${UNAME}' to groups: $groups"
    usermod -G "$groups" "${UNAME}"
else
    gow_log "Not modifying user groups"
fi
EOF

# Script de lançamento com Gamescope ou Sway
# Nota: no Arch, gamescope fica em /usr/bin/gamescope (não /usr/games/)
RUN cat > /opt/gow/launch-comp.sh << 'EOF'
#!/bin/bash
set -e
source /opt/gow/bash-lib/utils.sh
function launcher() {
    export GAMESCOPE_WIDTH=${GAMESCOPE_WIDTH:-1920}
    export GAMESCOPE_HEIGHT=${GAMESCOPE_HEIGHT:-1080}
    export GAMESCOPE_REFRESH=${GAMESCOPE_REFRESH:-60}

    if [ -n "$RUN_GAMESCOPE" ]; then
        gow_log "[Gamescope] - Starting: \`$*\`"
        GAMESCOPE_MODE=${GAMESCOPE_MODE:-"-b"}
        gamescope "${GAMESCOPE_MODE}" -W "${GAMESCOPE_WIDTH}" -H "${GAMESCOPE_HEIGHT}" -r "${GAMESCOPE_REFRESH}" -- "$@"

    elif [ -n "$RUN_SWAY" ]; then
        gow_log "[Sway] - Starting: \`$*\`"
        export SWAYSOCK=${XDG_RUNTIME_DIR}/sway.socket
        export SWAY_STOP_ON_APP_EXIT=${SWAY_STOP_ON_APP_EXIT:-"yes"}
        export XDG_CURRENT_DESKTOP=sway
        export XDG_SESSION_DESKTOP=sway
        export XDG_SESSION_TYPE=wayland

        mkdir -p "$HOME/.config/waybar"
        cp -u /cfg/waybar/* "$HOME/.config/waybar/"

        mkdir -p "$HOME/.config/sway/"
        cp /cfg/sway/config "$HOME/.config/sway/config"
        echo "output * resolution ${GAMESCOPE_WIDTH}x${GAMESCOPE_HEIGHT} position 0,0" >> "$HOME/.config/sway/config"
        echo -n "workspace main; exec $*" >> "$HOME/.config/sway/config"
        if [ "$SWAY_STOP_ON_APP_EXIT" == "yes" ]; then
            echo -n " && killall sway" >> "$HOME/.config/sway/config"
        fi
        dbus-run-session -- sway --unsupported-gpu

    else
        gow_log "[exec] Starting: $*"
        exec "$@"
    fi
}
EOF

# Script de espera pelo servidor X11 (usado por containers com Xwayland)
RUN cat > /opt/gow/wait-x11 << 'EOF'
#!/bin/bash
set -e
source /opt/gow/bash-lib/utils.sh
if [ -z "$DISPLAY" ]; then
    gow_log "FATAL: No DISPLAY environment variable set."
    exit 13
fi
MAX=120
CT=0
while ! xdpyinfo >/dev/null 2>&1; do
    sleep 1s
    CT=$(( CT + 1 ))
    if [ "$CT" -ge "$MAX" ]; then
        gow_log "FATAL: $0: Gave up waiting for X server $DISPLAY"
        exit 11
    fi
done
EOF

# Placeholder de startup — imagens derivadas devem sobrescrever este script
RUN cat > /opt/gow/startup.sh << 'EOF'
#!/usr/bin/env bash
set -e
echo "ERROR: This script '$0' must be replaced by the service init commands."
exit 1
EOF

RUN chmod +x \
    /opt/gow/bash-lib/utils.sh \
    /opt/gow/ensure-groups \
    /opt/gow/launch-comp.sh \
    /opt/gow/wait-x11 \
    /opt/gow/startup.sh

# XDG_RUNTIME_DIR correto para sessão Wayland (não é /tmp/.X11-unix)
ENV XDG_RUNTIME_DIR=/run/user/1000
ENV XDG_SESSION_TYPE=wayland
ENV WAYLAND_DISPLAY=wayland-1

COPY configs /cfg
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR ${HOME}

ENTRYPOINT ["/entrypoint.sh"]
# Sem CMD — o Wolf inicia sem args, fazendo o entrypoint rodar o startup.sh corretamente.
# Para debug manual use: docker run -it --rm --entrypoint /bin/bash gow/arch-firefox
