#!/usr/bin/env bash
# Regenerates the committed icon PNGs.
#
#   Resources/AppIcon.iconset/*.png      every size iconutil needs, downscaled from
#                                        Resources/Icon/AppIcon-1024.png (the app icon's source of truth)
#   Resources/MenuBarIconTemplate*.png   the menu-bar template image (@1x and @2x), rendered
#                                        from Assets/logo/menubar-template.svg
#
# AppIcon.icns itself is built from the iconset by scripts/build-app.sh with iconutil (macOS).
# To change the app icon artwork, run scripts/prepare-app-icon.sh on the new image first.
#
# Usage: scripts/generate-icons.sh [--previews <dir>]
#   --previews <dir>  also write review images: the app icon at 512/128/32/16px, the same sizes
#                     on light and dark backgrounds, and menu-bar glyph previews for the shipped
#                     glyph and every SVG in Assets/logo/menubar-concepts/ (menubar-concepts.png
#                     compares them).
#
# Requires ImageMagick (`brew install imagemagick` / `apt install imagemagick`) and
# rsvg-convert (`brew install librsvg` / `apt install librsvg2-bin`).
set -euo pipefail

cd "$(dirname "$0")/.."

previews=""
if [[ "${1:-}" == "--previews" ]]; then
  previews="${2:?--previews needs a directory}"
fi

im() { if command -v magick >/dev/null; then magick "$@"; else convert "$@"; fi; }
command -v rsvg-convert >/dev/null || { echo "generate-icons.sh: rsvg-convert not found" >&2; exit 1; }
command -v magick >/dev/null || command -v convert >/dev/null || { echo "generate-icons.sh: ImageMagick not found" >&2; exit 1; }

master=Resources/Icon/AppIcon-1024.png
glyph=Assets/logo/menubar-template.svg
iconset=Resources/AppIcon.iconset

[[ "$(im "$master" -format "%wx%h" info:)" == "1024x1024" ]] || { echo "generate-icons.sh: $master must be 1024x1024" >&2; exit 1; }

# Downscale in linear light with Lanczos (gamma-correct, so thin gold highlights don't darken),
# then sharpen slightly at small sizes where the resample softens edges.
downscale() { # size out
  local sharpen=()
  (( $1 <= 64 )) && sharpen=(-unsharp 0x0.6+0.6+0.02)
  im "$master" -colorspace RGB -filter Lanczos -resize "${1}x${1}" -colorspace sRGB "${sharpen[@]}" \
    -strip "PNG32:$2"
}

rm -rf "$iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  downscale "$size" "$iconset/icon_${size}x${size}.png"
  if (( size == 512 )); then
    im "$master" -strip "PNG32:$iconset/icon_512x512@2x.png"
  else
    downscale "$(( size * 2 ))" "$iconset/icon_${size}x${size}@2x.png"
  fi
done

# Menu-bar glyph: an 18pt template image (18px @1x, 36px @2x), the usual menu-bar icon size.
rsvg-convert --width 18 --height 18 "$glyph" --output Resources/MenuBarIconTemplate.png
rsvg-convert --width 36 --height 36 "$glyph" --output Resources/MenuBarIconTemplate@2x.png

echo "Wrote $iconset and Resources/MenuBarIconTemplate{,@2x}.png"

[[ -z "$previews" ]] && exit 0

mkdir -p "$previews"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# App icon at the requested review sizes, exactly as they ship in the iconset.
cp "$iconset/icon_512x512.png" "$previews/app-icon-512.png"
cp "$iconset/icon_128x128.png" "$previews/app-icon-128.png"
cp "$iconset/icon_32x32.png" "$previews/app-icon-32.png"
cp "$iconset/icon_16x16.png" "$previews/app-icon-16.png"

# Each size at actual pixels on light and dark backgrounds (how it sits in the Dock / Finder).
for bg in '#f2f2f2' '#1e1e1e'; do
  name=$([[ "$bg" == '#f2f2f2' ]] && echo light || echo dark)
  im -size 760x560 "xc:$bg" \
    "$iconset/icon_512x512.png" -geometry +24+24 -composite \
    "$iconset/icon_128x128.png" -geometry +560+24 -composite \
    "$iconset/icon_32x32.png" -geometry +608+184 -composite \
    "$iconset/icon_16x16.png" -geometry +616+248 -composite \
    "$previews/app-icon-sizes-$name.png"
done
# Small sizes enlarged 8x/4x (nearest-neighbor) to inspect individual pixels.
im "$iconset/icon_16x16.png" -background '#f2f2f2' -flatten -filter point -resize 128x128 "$tmp/16.png"
im "$iconset/icon_32x32.png" -background '#f2f2f2' -flatten -filter point -resize 128x128 "$tmp/32.png"
im "$tmp/16.png" "$tmp/32.png" -background '#f2f2f2' -splice 8x0 +append "$previews/app-icon-16-32-enlarged.png"

# Menu-bar glyph previews for one SVG: 16px, 18px, 36px (18@2x), each enlarged with
# nearest-neighbor, and light/dark menu-bar mockups at @2x (a 22pt bar is 44px tall). Glyph
# SVGs draw with currentColor and set color="#000", so swapping that renders the dark version.
glyph_previews() { # svg name-prefix
  local svg="$1" prefix="$2"
  rsvg-convert --width 16 --height 16 "$svg" --output "$previews/$prefix-16.png"
  rsvg-convert --width 18 --height 18 "$svg" --output "$previews/$prefix-18.png"
  rsvg-convert --width 36 --height 36 "$svg" --output "$previews/$prefix-18@2x.png"
  sed 's/color="#000"/color="#fff"/' "$svg" > "$tmp/white.svg"
  rsvg-convert --width 36 --height 36 "$tmp/white.svg" --output "$tmp/white36.png"
  im -size 240x44 xc:'#ececec' "$previews/$prefix-18@2x.png" -gravity center -composite "$tmp/light.png"
  im -size 240x44 xc:'#2a2a2c' "$tmp/white36.png" -gravity center -composite "$tmp/dark.png"
  im "$tmp/light.png" "$tmp/dark.png" -append +repage "$previews/$prefix-mockup.png"
  im "$previews/$prefix-16.png" -background white -flatten -filter point -resize 128x128 "$tmp/e16.png"
  im "$previews/$prefix-18.png" -background white -flatten -filter point -resize 144x144 "$tmp/e18.png"
  im "$previews/$prefix-18@2x.png" -background white -flatten -filter point -resize 144x144 "$tmp/e36.png"
  im "$tmp/e16.png" "$tmp/e18.png" "$tmp/e36.png" -background '#f6f6f6' -gravity center \
    -bordercolor '#f6f6f6' -border 6 +append +repage "$previews/$prefix-enlarged.png"
}

glyph_previews "$glyph" menubar-glyph

# Every concept in Assets/logo/menubar-concepts, plus one comparison sheet.
rows=()
for svg in Assets/logo/menubar-concepts/*.svg; do
  [[ -e "$svg" ]] || continue
  name="menubar-concept-$(basename "$svg" .svg)"
  glyph_previews "$svg" "$name"
  im "$previews/$name-enlarged.png" "$previews/$name-mockup.png" -background '#f6f6f6' -gravity center \
    -bordercolor '#f6f6f6' -border 6 +append +repage "$tmp/row-$name.png"
  rows+=("$tmp/row-$name.png")
done
if (( ${#rows[@]} )); then
  im "${rows[@]}" -background '#f6f6f6' -append +repage "$previews/menubar-concepts.png"
fi

echo "Wrote previews to $previews"
