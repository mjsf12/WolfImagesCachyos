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
profile. The image installs a patched InputPlumber 0.78.0 build that:

- recognizes the `Wolf X-Box One`, `Wolf PS5`, `Wolf DualSense`, and
  `Wolf Nintendo` virtual controllers plus the motion sensor;
- creates the `/dev/input` watcher before Wolf connects a controller;
- exposes the controller to OpenGamepadUI over D-Bus without `EVIOCGRAB`, so
  the same controller remains available after a game starts;
- enables D-Bus interception when a new composite controller starts in mode
  `0`, without overriding OpenGamepadUI's in-game mode `1`.

The build also patches OpenGamepadUI 0.46.0 window discovery. Gamescope
publishes focusable X11 windows as `[window_id, app_id, pid]` triplets; the
patched launcher uses that AppId as a fallback when Bottles, Heroic, Lutris, or
another intermediary launcher removes `OGUI_ID` from the game process. When the
last game exits, the patch also disables `STEAM_OVERLAY` and restores Gamescope's
idle baselayer list, preventing the menu from remaining transparent over a
black screen. Wine and launcher helpers that outlive a closed game are finalized
after a bounded grace period so they cannot retain a stale game baselayer.
Twelve headless Godot tests validate discovery, lifecycle, and state transitions
during the image build.

OpenGamepadUI 0.46.0 is built with Godot 4.7.1. The image carries a small
compatibility patch for the new native `Control.custom_maximum_size` property
and keeps the official binary, PCK, and GDExtension on the same release. The
session skips persisted update packs because an upstream PCK would replace the
Wolf Gamescope patches independently of the container image.

The image also installs the `Wolf Desktop Input` plugin. For generic Moonlight
controllers it translates `Start + Select` into a virtual Guide button. Releasing
the shortcut opens the main menu, `Start + Select + A` opens the quick bar, and
`Start + Select + X` toggles between the normal profile and desktop mode. In
desktop mode, the right stick moves the pointer, `A`/RT left-click, `B`/LT
right-click, and the bumpers scroll. The previous game profile is restored when
mouse mode is disabled. Its quick-bar page controls the current mode, generic
shortcut, automatic launcher activation, and pointer speed. Every route change
is written to the live InputPlumber composite even if OpenGamepadUI's local cache
already reports that mode. Sixteen additional tests validate the chord, route,
and desktop profile. The plugin registers its procedural
Quick Bar page with an explicit title, avoiding OpenGamepadUI
0.46.0's unsafe legacy `SectionLabel` lookup.

Build the image with:

```bash
docker buildx build \
  --load \
  --progress=plain \
  --build-arg PEGASUS_IMAGE=gow/cachyos-pegasus:latest \
  -t gow/cachyos-opengamepadui:latest \
  ./opengamepadui
```

#### Host setup

Create `/etc/udev/rules.d/85-wolf-virtual-inputs.rules`. Both Sony controller
names are included because different Wolf versions use either `PS5` or
`DualSense`:

```udev
# Allow Wolf to create virtual controllers.
KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput", TAG+="uaccess"

# Required for DualSense emulation.
KERNEL=="uhid", GROUP="input", MODE="0660", TAG+="uaccess"

# Virtual controllers created by Wolf.
KERNEL=="hidraw*", ATTRS{name}=="Wolf PS5 (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
KERNEL=="hidraw*", ATTRS{name}=="Wolf DualSense (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
SUBSYSTEMS=="input", ATTRS{name}=="Wolf X-Box One (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
SUBSYSTEMS=="input", ATTRS{name}=="Wolf PS5 (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
SUBSYSTEMS=="input", ATTRS{name}=="Wolf DualSense (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
SUBSYSTEMS=="input", ATTRS{name}=="Wolf gamepad (virtual) motion sensors", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
SUBSYSTEMS=="input", ATTRS{name}=="Wolf Nintendo (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
```

Reload the rules and restart Wolf:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
docker restart wolf
ls -l /dev/uinput /dev/uhid
```

The Wolf container itself needs these arguments for complete controller
support, including DualSense. They match the official example:

```bash
--device /dev/uinput \
--device /dev/uhid \
-v /dev/:/dev/:rw \
-v /run/udev:/run/udev:rw \
--device-cgroup-rule 'c 13:* rmw'
```

The Docker Compose equivalent is:

```yaml
services:
  wolf:
    volumes:
      - /dev/:/dev/:rw
      - /run/udev:/run/udev:rw
    devices:
      - /dev/uinput
      - /dev/uhid
    device_cgroup_rules:
      - 'c 13:* rmw'
```

#### Wolf application profile

Use the fields below in the OpenGamepadUI application profile. Preserve any
game and launcher mounts already present in your profile:

```toml
[[profiles.apps]]
    icon_png_path = ''
    start_virtual_compositor = true
    title = 'OpenGamepadUI (CachyOS)'

    [profiles.apps.runner]
    base_create_json = '''{
  "HostConfig": {
    "IpcMode": "host",
    "Tmpfs": {"/dev/input": "rw,dev,mode=0755"},
    "Privileged": false,
    "SecurityOpt": ["seccomp=unconfined"],
    "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_NICE", "SYS_ADMIN"],
    "Devices": [
      {
        "PathOnHost": "/dev/ntsync",
        "PathInContainer": "/dev/ntsync",
        "CgroupPermissions": "rwm"
      },
      {
        "PathOnHost": "/dev/uinput",
        "PathInContainer": "/dev/uinput",
        "CgroupPermissions": "rwm"
      },
      {
        "PathOnHost": "/dev/uhid",
        "PathInContainer": "/dev/uhid",
        "CgroupPermissions": "rwm"
      }
    ],
    "DeviceCgroupRules": ["c 10:223 rmw", "c 13:* rmw", "c 244:* rmw"]
  }
}
'''
    devices = [
        '/dev/ntsync:/dev/ntsync:rwm',
        '/dev/uinput:/dev/uinput:rwm',
        '/dev/uhid:/dev/uhid:rwm'
    ]
    env = [
        'GOW_REQUIRED_DEVICES=/dev/uinput /dev/uhid /dev/input/* /dev/dri/* /dev/nvidia*'
    ]
    image = 'gow/cachyos-opengamepadui:latest'
    mounts = []
    name = 'CachyOSOpenGamepadUI'
    ports = []
    type = 'docker'
```

A private `tmpfs` at `/dev/input` is required. Wolf's `fake-udev` creates the
late `event*` and `js*` nodes there, while the cgroup rule grants access to
input major 13. The `dev` option is also required: without it Docker mounts the
`tmpfs` with `nodev`, and InputPlumber gets `EACCES` when opening the controller.
Do not bind-mount the host's `/dev/input` for this profile because it conflicts
with `fake-udev` creating the same nodes.

Useful variables are `GAMESCOPE_WIDTH`, `GAMESCOPE_HEIGHT`,
`GAMESCOPE_INTERNAL_WIDTH`, `GAMESCOPE_INTERNAL_HEIGHT`, and
`OPENGAMEPADUI_STARTUP_FLAGS`. The inherited `RUN_XFCE=1` maintenance mode
remains available.

Host directories mounted at `~/.config/gamescope` or
`~/.local/share/opengamepadui` must belong to UID/GID `1000:1000`.
PowerStation remains installed but is disabled by default because `/sys` is
normally read-only in the container; set `START_POWERSTATION=1` only when the
host provides compatible access.

Validate the result after connecting through Moonlight:

```bash
ogui_container="$(
  docker ps --filter ancestor=gow/cachyos-opengamepadui:latest \
    --format '{{.ID}}' | head -n1
)"

docker exec "$ogui_container" \
  test -f /usr/share/inputplumber/devices/59-wolf_virtual_gamepad.yaml
docker exec "$ogui_container" inputplumber devices list
docker exec "$ogui_container" sh -c \
  'for event in /dev/input/event*; do
     name="$(cat "/sys/class/input/${event##*/}/device/name" 2>/dev/null)"
     case "$name" in Wolf\ *) echo "$event: $name";; esac
   done'
docker logs "$ogui_container" 2>&1 |
  grep -E 'inputplumber|Wolf Virtual Gamepad|Started evdev'
```

The expected result is a `Wolf Virtual Gamepad` composite device in
InputPlumber and at least one Wolf `event*`. Passthrough mode is intentional:
OpenGamepadUI reads the controller while the game continues to receive the
original device.

---

[README em Português](README_pt.md)
