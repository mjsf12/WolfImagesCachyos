ARG BASE_IMAGE=gow/cachyos-base:latest

# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

# http-parser não está no repo oficial do Arch mas é dependência do Heroic.
# Instalado diretamente do CachyOS antes do Heroic.
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm http-parser proton-cachyos proton-cachyos-slr cachyos/umu-launcher cachyos-gaming-applications  cachyos-gaming-meta && \
    pacman -Scc --noconfirm

# Baixa o pacote .pacman do Heroic, instala e limpa o cache
RUN curl -LO https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/v2.20.1/Heroic-2.20.1-linux-x64.pacman && \
    pacman -U --noconfirm Heroic-2.20.1-linux-x64.pacman && \
    rm Heroic-2.20.1-linux-x64.pacman && \
    pacman -Scc --noconfirm

COPY --chmod=777 scripts/startup.sh /opt/gow/startup.sh

# ---------------------------------------------------------------------------
# BUILD:
#   docker build -t gow/cachyos-base NewImages/base
#   docker build -t gow/cachyos-heroic --build-arg BASE_IMAGE=gow/cachyos-base NewImages/heroic
#
# Wolf config.toml:
#   [[profiles.apps]]
#   icon_png_path = ''
#   start_virtual_compositor = true
#   title = 'Heroic (cachyos)'
#
#       [profiles.apps.runner]
#       base_create_json = '''{
#     "HostConfig": {
#       "IpcMode": "host",
#       "Privileged": false,
#       "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_NICE"],
#       "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
#     }
#   }
#   '''
#       devices = []
#       env = [ 'RUN_SWAY=1', 'GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*' ]
#       image = 'gow/cachyos-heroic'
#       mounts = []
#       name = 'CachyosHeroic'
#       ports = []
#       type = 'docker'
# ---------------------------------------------------------------------------
