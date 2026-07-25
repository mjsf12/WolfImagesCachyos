ARG PEGASUS_IMAGE=gow/cachyos-pegasus:latest

# Herda todos os pacotes, caches gráficos e o modo XFCE da imagem Pegasus.
# hadolint ignore=DL3006
FROM ${PEGASUS_IMAGE}

ENV \
    START_SYSTEM_DBUS=1 \
    START_INPUTPLUMBER=1 \
    START_POWERSTATION=0

# paru é fornecido pelos repositórios já configurados na imagem CachyOS/Chaotic.
# Os pacotes AUR são compilados por um usuário sem privilégios; sudo é usado
# pelo helper somente para a transação final do pacman.
RUN pacman -S --noconfirm --needed paru sudo && \
    useradd --create-home --shell /bin/bash aurbuilder && \
    printf 'aurbuilder ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/aurbuilder && \
    chmod 0440 /etc/sudoers.d/aurbuilder

# PKGBUILDs baseados nos releases binários oficiais. Eles evitam depender da
# disponibilidade do Git do AUR, mas continuam sendo resolvidos, verificados e
# instalados pelo paru/makepkg.
COPY --chown=aurbuilder:aurbuilder pkgbuilds /tmp/pkgbuilds

RUN runuser -u aurbuilder -- paru -Syu --repo --noconfirm --needed \
        gamescope-session-git \
        firejail \
        bubblewrap \
        wireplumber \
        networkmanager \
        bluez \
        dbus && \
    runuser -u aurbuilder -- paru -Bi --noconfirm --needed --skipreview \
        /tmp/pkgbuilds/opengamepadui-bin \
        /tmp/pkgbuilds/powerstation-bin && \
    rm -rf /tmp/pkgbuilds && \
    rm -f /etc/sudoers.d/aurbuilder && \
    userdel --remove aurbuilder && \
    pacman -Scc --noconfirm

# O Makefile upstream grava o caminho temporário de $pkgdir no desktop entry.
# O launcher principal já funciona, mas o atalho do modo XFCE também deve usar
# o caminho definitivo instalado na imagem.
RUN sed -i \
    's|^Exec=.*opengamepadui.*|Exec=/usr/bin/opengamepadui %u|' \
    /usr/share/applications/opengamepadui.desktop

# Evita recursão de diálogos Zenity quando a camada Vulkan Gamescope WSI
# decide continuar com um swapchain X11 normal.
ENV GAMESCOPE_ZENITY_DISABLE=1

# Preserva o modo de manutenção XFCE herdado do Pegasus.
RUN mv /opt/gow/startup.sh /opt/gow/startup-pegasus.sh

# Configuração da sessão oficial ShadowBlip/OpenGamepadUI-session.
# /etc tem precedência sobre /usr no gamescope-session-plus.
COPY session/opengamepadui \
    /etc/gamescope-session-plus/sessions.d/opengamepadui
COPY session/gamescope-session-opengamepadui.desktop \
    /usr/share/wayland-sessions/gamescope-session-opengamepadui.desktop

COPY --chmod=755 scripts/init-services.sh /etc/cont-init.d/50-opengamepadui-services
COPY --chmod=755 scripts/startup.sh /opt/gow/startup.sh

# ---------------------------------------------------------------------------
# BUILD:
#   podman build -t gow/cachyos-base base
#   podman build -t gow/cachyos-pegasus \
#     --build-arg BASE_IMAGE=gow/cachyos-base pegasus
#   podman build -t gow/cachyos-opengamepadui \
#     --build-arg PEGASUS_IMAGE=gow/cachyos-pegasus opengamepadui
#
# Wolf config.toml:
#   [[profiles.apps]]
#   icon_png_path = ''
#   start_virtual_compositor = true
#   title = 'OpenGamepadUI (CachyOS)'
#
#       [profiles.apps.runner]
#       base_create_json = '''{
#     "HostConfig": {
#       "IpcMode": "host",
#       "Privileged": false,
#       "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_NICE"],
#       "Devices": [{
#         "PathOnHost": "/dev/uinput",
#         "PathInContainer": "/dev/uinput",
#         "CgroupPermissions": "rwm"
#       }],
#       "DeviceCgroupRules": ["c 10:223 rmw", "c 13:* rmw", "c 244:* rmw"]
#     }
#   }
#   '''
#       devices = [ '/dev/uinput:/dev/uinput:rwm' ]
#       env = [
#         'GOW_REQUIRED_DEVICES=/dev/uinput /dev/input/* /dev/dri/* /dev/nvidia*'
#       ]
#       image = 'gow/cachyos-opengamepadui'
#       mounts = []
#       name = 'CachyosOpenGamepadUI'
#       ports = []
#       type = 'docker'
# ---------------------------------------------------------------------------
