#!/usr/bin/env bash
# Regenerate build/icons/{icon.icns,icon.ico,icon.png} from build/icons/src/icon.svg.
# Needs rsvg-convert, iconutil (macOS) and ImageMagick (`magick`).
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=build/icons/src/icon.svg
OUT=build/icons
TMP=$(mktemp -d)

# macOS: padded squircle source -> .icns via iconset
rsvg-convert -w 1024 -h 1024 "$SRC" > "$TMP/icon_1024.png"
mkdir -p "$TMP/icon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$TMP/icon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$TMP/icon_1024.png" --out "$TMP/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/icon.iconset" -o "$OUT/icon.icns"

# Windows/Linux: crop the margin so the icon fills its slot like native apps do
magick "$TMP/icon_1024.png" -crop 824x824+100+100 +repage -resize 1024x1024 "$OUT/icon.png"
magick "$OUT/icon.png" -define icon:auto-resize=256,128,64,48,32,24,16 "$OUT/icon.ico"

rm -rf "$TMP"
echo "icons written to $OUT"
