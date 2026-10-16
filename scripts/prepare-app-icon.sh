#!/usr/bin/env bash
# Normalizes a raster app icon into Resources/Icon/AppIcon-1024.png, the source of truth that
# scripts/generate-icons.sh downscales into the .iconset. Run it only when the artwork changes.
#
# Usage: scripts/prepare-app-icon.sh [input.png]   (default: Resources/Icon/AppIcon-original.png)
#
# What it does:
#   - finds the rounded tile (pixels at least half opaque) and scales the image so the tile is
#     824px wide on a 1024px canvas, centered: Apple's macOS icon grid. The aspect ratio is
#     kept, and anything outside the tile (e.g. a drop shadow) stays transparent around it.
#   - makes the tile fully opaque (generators often leave it at ~99% alpha) and clears the
#     near-invisible alpha haze (alpha < 4/255) outside it, so the Dock shows clean corners.
#
# Requires ImageMagick 6 or 7 (`convert`/`magick`).
set -euo pipefail

cd "$(dirname "$0")/.."

input="${1:-Resources/Icon/AppIcon-original.png}"
output=Resources/Icon/AppIcon-1024.png
canvas=1024
body=824

im() { if command -v magick >/dev/null; then magick "$@"; else convert "$@"; fi; }

read -r width height <<<"$(im "$input" -format "%w %h" info:)"
[[ "$width" == "$height" ]] || echo "prepare-app-icon.sh: note: $input is ${width}x${height}, not square; the output will be" >&2

# Tile bounding box, e.g. "1126x1101+64+68".
bbox="$(im "$input" -alpha extract -threshold 50% -format "%@" info:)"
[[ "$bbox" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]] || { echo "prepare-app-icon.sh: can't find the tile ($bbox)" >&2; exit 1; }
tile_w="${BASH_REMATCH[1]}" tile_h="${BASH_REMATCH[2]}" tile_x="${BASH_REMATCH[3]}" tile_y="${BASH_REMATCH[4]}"

longest=$(( tile_w > tile_h ? tile_w : tile_h ))
scale="$(awk "BEGIN { printf \"%.6f\", $body / $longest }")"
center_x="$(awk "BEGIN { printf \"%.2f\", $tile_x + $tile_w / 2 }")"
center_y="$(awk "BEGIN { printf \"%.2f\", $tile_y + $tile_h / 2 }")"
echo "tile ${tile_w}x${tile_h} at +${tile_x}+${tile_y}; scaling by $scale and centering on a ${canvas}px canvas"

# Clean alpha at full resolution, then scale/translate in one high-quality resample (EWA Lanczos).
im "$input" \
  -channel A -fx "u >= 250/255 ? 1 : (u < 4/255 ? 0 : u)" +channel \
  -background none -virtual-pixel transparent -filter Lanczos \
  -define distort:viewport=${canvas}x${canvas}+0+0 \
  -distort SRT "$center_x,$center_y $scale 0 $(( canvas / 2 )),$(( canvas / 2 ))" \
  +repage -strip "PNG32:$output"

echo "Wrote $output ($(im "$output" -format "%wx%h" info:), tile now $(im "$output" -alpha extract -threshold 50% -format "%@" info:))"
