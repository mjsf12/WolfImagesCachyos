# Bundled OpenGamepadUI plugins

These sources are built with the exact Godot toolchain used for the bundled
OpenGamepadUI PCK. They were imported from the sibling development trees on
2026-08-04:

- `lutris`: `OpenGamepadUI-lutris`, commit
  `601bd6b2f3c035cfdce7f0bb0c4d14bf55992e87`; bundled version `2.0.1`.
- `heroic`: local `OpenGamepadUI-heroic` working tree; bundled version `0.1.1`.
- `bottles`: local `OpenGamepadUI-bottles` working tree; bundled version `0.1.2`.

The patch component was increased for each imported plugin so OpenGamepadUI
will re-extract the image-provided archive over an older persistent copy. The
Heroic PNG is stored losslessly as `assets/heroic.png.base64`; the Docker build
decodes it before Godot imports and exports the plugin. Its expected SHA-256 is
`a57601ee8357f0b51d987a03eddeef7bab4a777955b9fe86b9f8d6a7891aa654`.
