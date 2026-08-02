ARG PEGASUS_IMAGE=gow/cachyos-pegasus:latest
ARG OPENGAMEPADUI_BUILDER_IMAGE=ghcr.io/shadowblip/opengamepadui-builder:4.7.1

# Herda todos os pacotes, caches gráficos e o modo XFCE da imagem Pegasus.
# hadolint ignore=DL3006
FROM ${PEGASUS_IMAGE} AS opengamepadui-runtime

ENV \
    START_SYSTEM_DBUS=1 \
    START_INPUTPLUMBER=1 \
    START_POWERSTATION=0

# Algumas revisões antigas da imagem base registravam [multilib] duas vezes.
# O pacman apenas avisa, mas o paru --repo encerra com erro. Preserve a primeira
# definição de cada repositório e descarte somente blocos repetidos.
RUN awk '/^\[[^]]+\]$/ { if (seen[$0]++) { skip = 1; next } skip = 0 } !skip { print }' \
        /etc/pacman.conf > /tmp/pacman.conf && \
    install -m 0644 /tmp/pacman.conf /etc/pacman.conf && \
    rm -f /tmp/pacman.conf

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
        python-evdev \
        python-xlib \
        dbus && \
    runuser -u aurbuilder -- paru -Bi --noconfirm --needed --skipreview \
        /tmp/pkgbuilds/inputplumber-wolf && \
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

# O OGUI 0.46.0 associa janelas principalmente pelo OGUI_ID dos processos.
# Launchers intermediários como Bottles, Heroic e Lutris podem remover essa
# variável antes de criar a janela do jogo. Gere apenas um PCK corrigido usando
# a mesma versão do Godot do binário oficial; o restante continua vindo do
# pacote opengamepadui-bin instalado acima.
FROM ${OPENGAMEPADUI_BUILDER_IMAGE} AS opengamepadui-pck-builder

ARG OPENGAMEPADUI_COMMIT=b149644f46b71e175a2ad223e84c18361596691e
ARG OPENGAMEPADUI_SOURCE_SHA256=19e2eefd26f9777555885474fced7bdba66b63e26313bed27f4103e195923b18

WORKDIR /src

RUN curl --fail --location --retry 3 \
        --output /tmp/opengamepadui-source.tar.gz \
        "https://github.com/ShadowBlip/OpenGamepadUI/archive/${OPENGAMEPADUI_COMMIT}.tar.gz" && \
    echo "${OPENGAMEPADUI_SOURCE_SHA256}  /tmp/opengamepadui-source.tar.gz" | sha256sum --check && \
    tar --extract --gzip --file /tmp/opengamepadui-source.tar.gz \
        --strip-components=1 --directory /src && \
    rm -f /tmp/opengamepadui-source.tar.gz

COPY patches/opengamepadui-gamescope-appid-window-detection.patch /tmp/opengamepadui.patch
COPY patches/opengamepadui-overlay-return.patch /tmp/opengamepadui-overlay-return.patch
COPY patches/opengamepadui-overlay-menu.patch /tmp/opengamepadui-overlay-menu.patch
COPY patches/opengamepadui-godot-4.7-maximum-size.patch /tmp/opengamepadui-godot-4.7-maximum-size.patch
COPY plugins/wolf-desktop-input /src/plugins/wolf-desktop-input
COPY plugin-build/wolf-desktop-input-export.cfg /tmp/wolf-desktop-input-export.cfg
RUN patch --strip=1 < /tmp/opengamepadui-godot-4.7-maximum-size.patch && \
    patch --strip=1 < /tmp/opengamepadui.patch && \
    patch --strip=1 < /tmp/opengamepadui-overlay-return.patch && \
    patch --strip=1 < /tmp/opengamepadui-overlay-menu.patch && \
    sed -i 's|rootfs,sandbox,plugins,|rootfs,sandbox,plugins/*,|' \
        /src/export_presets.cfg && \
    cat /tmp/wolf-desktop-input-export.cfg >> /src/export_presets.cfg

# O editor carrega a variante debug durante import/test. As duas variantes usam
# a extensão oficial 0.46.0 já instalada na etapa de runtime.
COPY --from=opengamepadui-runtime \
    /usr/share/opengamepadui/libopengamepadui-core.linux.template_release.x86_64.so \
    /src/addons/core/bin/libopengamepadui-core.linux.template_release.x86_64.so
RUN cp \
        addons/core/bin/libopengamepadui-core.linux.template_release.x86_64.so \
        addons/core/bin/libopengamepadui-core.linux.template_debug.x86_64.so && \
    make GODOT=/usr/bin/godot import && \
    /usr/bin/godot --headless --path /src \
        --script res://addons/gut/gut_cmdln.gd \
        -gselect=gamescope_focusable_windows && \
    /usr/bin/godot --headless --path /src \
        --script res://addons/gut/gut_cmdln.gd \
        -gselect=gamescope_session_state && \
    /usr/bin/godot --headless --path /src \
        --script res://addons/gut/gut_cmdln.gd \
        -gdir=res://plugins/wolf-desktop-input/core && \
    mkdir -p /src/build && \
    /usr/bin/godot --headless --path /src \
        --export-pack "Linux/X11 x86_64" \
        /src/build/opengamepad-ui.pck && \
    /usr/bin/godot --headless --path /src \
        --export-pack "Wolf Desktop Input" \
        /src/build/wolf-desktop-input.zip

# Volte à imagem completa e troque somente os scripts/recursos Godot. O binário
# e a GDExtension continuam byte a byte iguais aos do release oficial 0.46.0.
FROM opengamepadui-runtime

COPY --from=opengamepadui-pck-builder \
    /src/build/opengamepad-ui.pck \
    /usr/share/opengamepadui/opengamepad-ui.pck
COPY --from=opengamepadui-pck-builder \
    /src/build/wolf-desktop-input.zip \
    /usr/share/opengamepadui/plugins/wolf-desktop-input.zip

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
COPY --chmod=755 scripts/inputplumber_x11_bridge.py /opt/gow/inputplumber_x11_bridge.py
RUN bash -n /etc/cont-init.d/50-opengamepadui-services
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
#       "Tmpfs": {"/dev/input": "rw,dev,mode=0755"},
#       "Privileged": false,
#       "SecurityOpt": ["seccomp=unconfined"],
#       "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_NICE", "SYS_ADMIN"],
#       "Devices": [
#         {
#           "PathOnHost": "/dev/ntsync",
#           "PathInContainer": "/dev/ntsync",
#           "CgroupPermissions": "rwm"
#         },
#         {
#           "PathOnHost": "/dev/uinput",
#           "PathInContainer": "/dev/uinput",
#           "CgroupPermissions": "rwm"
#         },
#         {
#           "PathOnHost": "/dev/uhid",
#           "PathInContainer": "/dev/uhid",
#           "CgroupPermissions": "rwm"
#         }
#       ],
#       "DeviceCgroupRules": ["c 10:223 rmw", "c 13:* rmw", "c 244:* rmw"]
#     }
#   }
#   '''
#       devices = [
#         '/dev/ntsync:/dev/ntsync:rwm',
#         '/dev/uinput:/dev/uinput:rwm',
#         '/dev/uhid:/dev/uhid:rwm'
#       ]
#       env = [
#         'GOW_REQUIRED_DEVICES=/dev/uinput /dev/uhid /dev/input/* /dev/dri/* /dev/nvidia*'
#       ]
#       image = 'gow/cachyos-opengamepadui'
#       mounts = []
#       name = 'CachyosOpenGamepadUI'
#       ports = []
#       type = 'docker'
# ---------------------------------------------------------------------------
