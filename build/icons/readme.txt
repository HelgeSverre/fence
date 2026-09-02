App icons for Fence
===================

Source of truth: src/icon.svg (1024x1024, macOS squircle with the standard
transparent margin). Regenerate every platform icon with:

  bash scripts/build-icons.sh

Outputs (used by electron-builder, see package.json "build"):

  icon.icns   macOS   (from the padded source)
  icon.png    Linux   (margin cropped so it fills its slot)
  icon.ico    Windows (from icon.png, 16-256px)
