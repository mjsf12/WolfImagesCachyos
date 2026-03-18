# ARG aponta para a imagem base Arch que criamos em NewImages/base
ARG BASE_IMAGE=gow/arch-base:latest

# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

# Instala o Firefox via pacman
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed firefox mesa-utils vulkan-tools && \
    pacman -Scc --noconfirm

# Políticas do Firefox: desativa auto-update, primeira execução e telemetria
# Força WebRender e WebGL para melhor performance de streaming
RUN mkdir -p /etc/firefox/policies && \
    cat > /etc/firefox/policies/policies.json << 'EOF'
{
  "policies": {
    "AppAutoUpdate": false,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "DisableTelemetry": true,
    "FirefoxHome": {
      "Search": true,
      "TopSites": true,
      "SponsoredTopSites": false,
      "Highlights": true,
      "Pocket": false,
      "SponsoredPocket": false,
      "Snippets": false,
      "Locked": false
    },
    "Preferences": {
      "gfx.webrender.all": {
        "Value": true,
        "Status": "default"
      },
      "webgl.force-enabled": {
        "Value": true,
        "Status": "default"
      },
      "media.hardware-video-decoding.force-enabled": {
        "Value": true,
        "Status": "default"
      }
    }
  }
}
EOF

# Substitui o placeholder /opt/gow/startup.sh pelo launcher do Firefox
COPY --chmod=777 scripts/startup.sh /opt/gow/startup.sh

# ---------------------------------------------------------------------------
# BUILD (a partir da raiz do repo):
#
#   docker build -t gow/arch-base NewImages/base
#   docker build -t gow/arch-firefox --build-arg BASE_IMAGE=gow/arch-base NewImages/firefox
#
# TESTE sem Wolf (host Wayland):
#
#   docker run --rm -it \
#     --device=/dev/dri/renderD128 --device=/dev/dri/card0 \
#     --ipc=host --cap-add=SYS_NICE --cap-add=NET_RAW --cap-add=MKNOD \
#     -e WAYLAND_DISPLAY=$WAYLAND_DISPLAY \
#     -e XDG_RUNTIME_DIR=/run/user/1000 \
#     -v $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY:/run/user/1000/$WAYLAND_DISPLAY:rw \
#     -e RUN_SWAY=1 \
#     -e GOW_REQUIRED_DEVICES='/dev/input/* /dev/dri/*' \
#     gow/arch-firefox
#
# ENTRADA no config.toml do Wolf:
#
#   [[profiles.apps]]
#   icon_png_path = ''
#   start_virtual_compositor = true
#   title = 'Firefox (Arch)'
#
#       [profiles.apps.runner]
#       base_create_json = '''
#   {
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
#       image = 'gow/arch-firefox'
#       mounts = []
#       name = 'ArchFirefox'
#       ports = []
#       type = 'docker'
# ---------------------------------------------------------------------------
