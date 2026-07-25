# Wolf Images - CachyOS

Alternative Docker images for [Wolf](https://github.com/games-on-whales/wolf) built on [CachyOS](https://cachyos.org/), an Arch Linux-based distribution optimized for performance.

## About

This project provides custom Docker images as an alternative to the standard [games-on-whales/gow](https://github.com/games-on-whales/gow) images. While the original images are based on generic distributions, these images leverage CachyOS's optimizations for potentially better performance in gaming and multimedia workloads.

### Related Projects

- **[Wolf](https://github.com/games-on-whales/wolf)** - Moonlight-compatible game/server streaming host
- **[games-on-whales/gow](https://github.com/games-on-whales/gow)** - Original Docker images this project is based on

## Configuration Guide

This document explains how to configure `newImages` for running applications inside Docker containers with GPU passthrough and device access.

## Basic Structure

```toml
[[profiles.apps]]
    icon_png_path = ''
    start_virtual_compositor = true
    title = 'App Name'

    [profiles.apps.runner]
    # Docker container configuration
```

## Configuration Options

### App Level

| Field | Type | Description |
|-------|------|-------------|
| `icon_png_path` | string | Path to the app icon (empty = default) |
| `start_virtual_compositor` | bool | Start a virtual compositor (Wayland/X11) |
| `title` | string | Display name for the app |

### Runner Level

| Field | Type | Description |
|-------|------|-------------|
| `base_create_json` | string | Raw Docker API JSON for container creation |
| `devices` | array | Device mappings (e.g., `/dev/ntsync`) |
| `env` | array | Environment variables |
| `image` | string | Docker image name |
| `mounts` | array | Volume mounts (host:container:mode) |
| `name` | string | Container name identifier |
| `ports` | array | Port mappings (empty = none) |
| `type` | string | Runner type (`docker`) |

## Complete Example

```toml
[[profiles.apps]]
    icon_png_path = ''
    start_virtual_compositor = true
    title = 'Heroic (CachyOS)'

    [profiles.apps.runner]
    base_create_json = '''{
  "HostConfig": {
    "IpcMode": "host",
    "Privileged": false,
    "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_NICE"],
    "CpusetCpus": "0-7,16-23",
    "Devices": [
    {
        "PathOnHost": "/dev/ntsync",
        "PathInContainer": "/dev/ntsync",
        "CgroupPermissions": "rwm"
    }
    ],
    "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
  }
}
'''
    devices = [ '/dev/ntsync:/dev/ntsync:rwm' ]
    env = [
        'RUN_SWAY=1',
        'GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*',
        'LANG=pt_BR.UTF-8',
        'LANGUAGE=pt_BR:pt',
        'LC_ALL=pt_BR.UTF-8',
        'XKB_DEFAULT_LAYOUT=br',
        'XKB_DEFAULT_MODEL=pc105',
        'XKB_DEFAULT_VARIANT=abnt2'
    ]
    image = 'gow/cachyos-heroic'
    mounts = [
        '/home/mjsf12/.config/heroic:/home/gow/.config/heroic:rw',
        '/home/mjsf12/Games:/home/gow/Games:rw'
    ]
    name = 'CachyOSHeroic'
    ports = []
    type = 'docker'
```

## Key Notes

### CPU Affinity
- `CpusetCpus` pins containers to specific cores
- Example: `"0-7,16-23"` uses cores 0-7 and 16-23 (typical for hyperthreading)

### Device Passthrough
- Add devices to both `base_create_json.Devices` AND `devices` array
- Format: `/dev/ntsync:/dev/ntsync:rwm`

### Compositor
- Set `start_virtual_compositor = true` for GUI apps
- `RUN_SWAY=1` in env enables Sway compositor inside container

### XFCE Desktop Mode (Pegasus)
- Set `RUN_XFCE=1` in env to start a full XFCE desktop (Thunar, terminal, mousepad, panel, window manager)
- Runs directly on the virtual compositor's XWayland — no Sway involved
- Useful for system configuration, installing games, or tweaking emulators
- Session ends when you log out of XFCE

```toml
# In Wolf config.toml
env = [ 'RUN_XFCE=1' ]
```

### Locale/Keyboard
- Set `LANG`, `LANGUAGE`, `LC_ALL` for locale
- Set `XKB_*` vars for keyboard layout (example: Brazilian ABNT2)

## Building Images

The build follows a hierarchical structure:

```
base (NewImages/base)
   ├── app (NewImages/heroic, NewImages/firefox, etc.)
   └── pegasus
       └── opengamepadui
```

### Build Base Image First

```bash
# Build the base image
docker build -t gow/cachyos-base NewImages/base
```

### Build App Image

```bash
# Build app image using the base
docker build -t gow/cachyos-heroic \
  --build-arg BASE_IMAGE=gow/cachyos-base \
  NewImages/heroic
```

The `pegasus` image inherits from `base` directly (not `heroic`) and includes all gaming frontends:

```bash
docker build -t gow/cachyos-pegasus \
  --build-arg BASE_IMAGE=gow/cachyos-base \
  NewImages/pegasus
```

The `opengamepadui` image inherits every Pegasus package, installs
`opengamepadui-bin` and all of its optional dependencies through `paru`, and
starts the official Gamescope session:

```bash
docker build -t gow/cachyos-opengamepadui \
  --build-arg PEGASUS_IMAGE=gow/cachyos-pegasus \
  NewImages/opengamepadui
```

### Build All NewImages

```bash
# Base
docker build -t gow/cachyos-base NewImages/base

# Apps
docker build -t gow/cachyos-heroic --build-arg BASE_IMAGE=gow/cachyos-base NewImages/heroic
docker build -t gow/cachyos-firefox --build-arg BASE_IMAGE=gow/cachyos-base NewImages/firefox
docker build -t gow/cachyos-pegasus --build-arg BASE_IMAGE=gow/cachyos-base NewImages/pegasus
docker build -t gow/cachyos-opengamepadui --build-arg PEGASUS_IMAGE=gow/cachyos-pegasus NewImages/opengamepadui
```

## Complete Workflow

```bash
# 1. Build base
docker build -t gow/cachyos-base NewImages/base

# 2. Build pegasus (includes all gaming frontends + XFCE config mode)
docker build -t gow/cachyos-pegasus --build-arg BASE_IMAGE=gow/cachyos-base NewImages/pegasus

# 3. Use in Wolf config.toml
[[profiles.apps]]
    title = 'Pegasus (CachyOS)'
    [profiles.apps.runner]
    image = 'gow/cachyos-pegasus'
    type = 'docker'
    ...
```

### OpenGamepadUI with Gamescope

OpenGamepadUI uses Gamescope by default; do not set `RUN_SWAY` for this
profile. `/dev/uinput` is required by InputPlumber for virtual controllers:

```toml
[[profiles.apps]]
    icon_png_path = ''
    start_virtual_compositor = true
    title = 'OpenGamepadUI (CachyOS)'

    [profiles.apps.runner]
    base_create_json = '''{
  "HostConfig": {
    "IpcMode": "host",
    "Privileged": false,
    "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_NICE"],
    "Devices": [{
      "PathOnHost": "/dev/uinput",
      "PathInContainer": "/dev/uinput",
      "CgroupPermissions": "rwm"
    }],
    "DeviceCgroupRules": ["c 10:223 rmw", "c 13:* rmw", "c 244:* rmw"]
  }
}
'''
    devices = [ '/dev/uinput:/dev/uinput:rwm' ]
    env = [ 'GOW_REQUIRED_DEVICES=/dev/uinput /dev/input/* /dev/dri/* /dev/nvidia*' ]
    image = 'gow/cachyos-opengamepadui'
    mounts = []
    name = 'CachyosOpenGamepadUI'
    ports = []
    type = 'docker'
```

Useful variables are `GAMESCOPE_WIDTH`, `GAMESCOPE_HEIGHT`,
`GAMESCOPE_INTERNAL_WIDTH`, `GAMESCOPE_INTERNAL_HEIGHT`, and
`OPENGAMEPADUI_STARTUP_FLAGS`. The inherited `RUN_XFCE=1` maintenance mode
remains available.

Host directories mounted at `~/.config/gamescope` or
`~/.local/share/opengamepadui` must belong to UID/GID `1000:1000`.
PowerStation remains installed but is disabled by default because `/sys` is
normally read-only in the container; set `START_POWERSTATION=1` only when the
host provides compatible access.

---

[README em Português](README_pt.md)
