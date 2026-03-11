App Icons for Fence
===================

electron-builder looks in this directory for app icons.

Required files:

  icon.icns   - macOS    (512x512 or larger)
  icon.ico    - Windows  (256x256)
  icon.png    - Linux    (512x512 or larger)

To generate all formats from a single 1024x1024 source PNG:

  npx electron-icon-builder --input=icon-source.png --output=build/icons/

Until icons are added, electron-builder uses the default Electron icon.
