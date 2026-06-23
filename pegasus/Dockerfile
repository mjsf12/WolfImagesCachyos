ARG BASE_IMAGE=gow/cachyos-heroic:latest

# hadolint ignore=DL3006
FROM ${BASE_IMAGE}
# Configure Chaotic-AUR (prioridade baixa, adicionado ao final do pacman.conf)
RUN mkdir -p /tmp/nohooks && \
    pacman-key --init && \
    pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && \
    pacman-key --lsign-key 3056513887B78AEB && \
    pacman -U --noconfirm --hookdir /tmp/nohooks 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' && \
    pacman -U --noconfirm --hookdir /tmp/nohooks 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' && \
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf && \
    pacman-key --recv-key 349BC7808577C592 --keyserver keyserver.ubuntu.com && \
    pacman-key --lsign-key 349BC7808577C592 && \
    pacman -Syyuu --noconfirm --hookdir /tmp/nohooks

RUN pacman -S --noconfirm \
        pegasus-frontend-git \
        heroic-games-launcher-bin \
        lutris \
        steam \
        itch-setup-bin \
        bottles \
        eden-git \
        ryujinx-canary \
        rpcs3-git \
        shadps4-qtlauncher-git \
        retroarch \
        cemu-git \
        pcsx2-git \
        gsettings-desktop-schemas \
        foot && \
    pacman -Scc --noconfirm

# Hooks falharam no build (sandbox de rede), compilar manualmente
RUN glib-compile-schemas /usr/share/glib-2.0/schemas/ || true; \
    gtk-update-icon-cache -f /usr/share/icons/hicolor/ 2>/dev/null || true; \
    update-desktop-database 2>/dev/null || true

COPY --chmod=777 scripts/startup.sh /opt/gow/startup.sh

# ---------------------------------------------------------------------------
# BUILD:
#   docker build -t gow/cachyos-base NewImages/base
#   docker build -t gow/cachyos-heroic --build-arg BASE_IMAGE=gow/cachyos-base NewImages/heroic
#   docker build -t gow/cachyos-pegasus --build-arg BASE_IMAGE=gow/cachyos-heroic NewImages/pegasus
#
# Wolf config.toml:
#   [[profiles.apps]]
#   icon_png_path = ''
#   start_virtual_compositor = true
#   title = 'Pegasus (cachyos)'
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
#       image = 'gow/cachyos-pegasus'
#       mounts = []
#       name = 'CachyosPegasus'
#       ports = []
#       type = 'docker'
# ---------------------------------------------------------------------------
