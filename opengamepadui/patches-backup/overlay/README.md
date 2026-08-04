# Retired overlay patches

These are byte-for-byte backups of the three patches whose behavior is now
owned by the `wolf-gamescope-session` plugin. The original files also remain in
`opengamepadui/patches`; the Docker build verifies both copies with `cmp` and
does not apply them.

The remaining OpenGamepadUI patches are still applied because they change core
window discovery, launcher cleanup, or Godot 4.7 compatibility and cannot be
implemented through the public plugin API.
