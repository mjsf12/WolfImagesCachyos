ARG BASE_IMAGE=gow/cachyos-base:latest

# hadolint ignore=DL3006
FROM ${BASE_IMAGE}
# Configure Chaotic-AUR (prioridade baixa, adicionado ao final do pacman.conf)
RUN mkdir -p /tmp/nohooks && \
    pacman-key --init && \
    curl -fsSL --retry 3 --connect-timeout 15 \
        'https://raw.githubusercontent.com/chaotic-aur/keyring/master/chaotic.gpg' \
        -o /tmp/chaotic.gpg && \
    pacman-key --add /tmp/chaotic.gpg && \
    pacman-key --lsign-key EF925EA60F33D0CB85C44AD13056513887B78AEB && \
    pacman -U --noconfirm --hookdir /tmp/nohooks 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' && \
    pacman -U --noconfirm --hookdir /tmp/nohooks 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' && \
    pacman-key --populate chaotic && \
    rm -f /tmp/chaotic.gpg && \
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf && \
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
        foot http-parser proton-cachyos proton-cachyos-slr cachyos/umu-launcher cachyos-gaming-applications cachyos-gaming-meta \
        xfce4 xfce4-whiskermenu-plugin \
        mousepad ristretto \
        python python-pip yq librsvg papirus-icon-theme shared-mime-info \
        ttf-dejavu && \
    pacman -Scc --noconfirm

# Hooks falharam no build (sandbox de rede), compilar manualmente
RUN mkdir -p /usr/lib/gdk-pixbuf-2.0/2.10.0; \
    gdk-pixbuf-query-loaders --update-cache 2>/dev/null || \
    gdk-pixbuf-query-loaders > /usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache; \
    glib-compile-schemas /usr/share/glib-2.0/schemas/ || true; \
    gtk-update-icon-cache -f /usr/share/icons/hicolor/ 2>/dev/null || true; \
    gtk-update-icon-cache -f /usr/share/icons/Papirus/ 2>/dev/null || true; \
    gtk-update-icon-cache -f /usr/share/icons/Papirus-Dark/ 2>/dev/null || true; \
    gtk-update-icon-cache -f /usr/share/icons/ePapirus/ 2>/dev/null || true; \
    gtk-update-icon-cache -f /usr/share/icons/ePapirus-Dark/ 2>/dev/null || true; \
    update-desktop-database 2>/dev/null || true; \
    update-mime-database /usr/share/mime 2>/dev/null || true; \
    sed -i \
        -e 's/value="Sans 10"/value="DejaVu Sans 10"/' \
        -e 's/value="Monospace 10"/value="DejaVu Sans Mono 10"/' \
        /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml; \
    sed -i \
        's/^title_font=Sans Bold 9$/title_font=DejaVu Sans Bold 9/' \
        /usr/share/xfwm4/defaults; \
    fc-cache -f

COPY configs/xfce4-terminal.xml /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-terminal.xml
COPY --chmod=777 scripts/startup.sh /opt/gow/startup.sh

# ---------------------------------------------------------------------------
# BUILD:
#   docker build -t gow/cachyos-base NewImages/base
#   docker build -t gow/cachyos-heroic --build-arg BASE_IMAGE=gow/cachyos-base NewImages/heroic
#   docker build -t gow/cachyos-pegasus --build-arg BASE_IMAGE=gow/cachyos-base NewImages/pegasus
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
