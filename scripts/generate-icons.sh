#!/usr/bin/env bash
# Regenerates the committed icon PNGs from the SVG sources in Assets/logo/.
#
#   Resources/AppIcon.iconset/*.png      every size iconutil needs for AppIcon.icns
#   Resources/MenuBarIconTemplate*.png   the menu-bar template image (@1x and @2x)
#
# AppIcon.icns itself is built from the iconset by scripts/build-app.sh with iconutil (macOS).
#
# Usage: scripts/generate-icons.sh [--previews <dir>]
#   --previews <dir>  also write review images: the icon at 512px, the glyph at 16/32px,
#                     enlarged pixel views, and light/dark menu-bar mockups.
#
# Requires rsvg-convert (macOS: `brew install librsvg`; Debian/Ubuntu: `apt install librsvg2-bin`).
# --previews also needs ImageMagick's `convert`.
set -euo pipefail

cd "$(dirname "$0")/.."

previews=""
if [[ "${1:-}" == "--previews" ]]; then
  previews="${2:?--previews needs a directory}"
fi

command -v rsvg-convert >/dev/null || { echo "generate-icons.sh: rsvg-convert not found" >&2; exit 1; }

full=Assets/logo/app-icon.svg
small=Assets/logo/app-icon-small.svg
glyph=Assets/logo/menubar-template.svg
iconset=Resources/AppIcon.iconset

render() { # svg size out
  rsvg-convert --width "$2" --height "$2" --keep-aspect-ratio "$1" --output "$3"
}

rm -rf "$iconset"
mkdir -p "$iconset"
# Tiny sizes use the simplified artwork so the visor stays legible.
render "$small" 16   "$iconset/icon_16x16.png"
render "$small" 32   "$iconset/icon_16x16@2x.png"
render "$small" 32   "$iconset/icon_32x32.png"
render "$full"  64   "$iconset/icon_32x32@2x.png"
render "$full"  128  "$iconset/icon_128x128.png"
render "$full"  256  "$iconset/icon_128x128@2x.png"
render "$full"  256  "$iconset/icon_256x256.png"
render "$full"  512  "$iconset/icon_256x256@2x.png"
render "$full"  512  "$iconset/icon_512x512.png"
render "$full"  1024 "$iconset/icon_512x512@2x.png"

render "$glyph" 16 Resources/MenuBarIconTemplate.png
render "$glyph" 32 Resources/MenuBarIconTemplate@2x.png

echo "Wrote $iconset and Resources/MenuBarIconTemplate{,@2x}.png"

[[ -z "$previews" ]] && exit 0

command -v convert >/dev/null || { echo "generate-icons.sh: ImageMagick convert not found" >&2; exit 1; }
mkdir -p "$previews"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp "$iconset/icon_512x512.png" "$previews/app-icon-512.png"
cp "$iconset/icon_16x16.png" "$previews/app-icon-16.png"
cp "$iconset/icon_32x32.png" "$previews/app-icon-32.png"
cp Resources/MenuBarIconTemplate.png "$previews/menubar-glyph-16.png"
cp Resources/MenuBarIconTemplate@2x.png "$previews/menubar-glyph-32.png"

# Pixel-level views of the small sizes (nearest-neighbor, 8x and 4x).
convert Resources/MenuBarIconTemplate.png -background white -flatten -filter point -resize 128x128 "$previews/menubar-glyph-16-enlarged.png"
convert Resources/MenuBarIconTemplate@2x.png -background white -flatten -filter point -resize 128x128 "$previews/menubar-glyph-32-enlarged.png"
convert "$iconset/icon_16x16.png" -filter point -resize 128x128 "$previews/app-icon-16-enlarged.png"

# Menu-bar mockups at @2x (a 22pt bar is 44px): template rendered black on light, white on dark.
sed 's/fill="#000"/fill="#fff"/' "$glyph" > "$tmp/white.svg"
render "$tmp/white.svg" 32 "$tmp/white32.png"
convert -size 240x44 xc:'#ececec' Resources/MenuBarIconTemplate@2x.png -gravity center -composite "$tmp/light.png"
convert -size 240x44 xc:'#2a2a2c' "$tmp/white32.png" -gravity center -composite "$tmp/dark.png"
convert "$tmp/light.png" "$tmp/dark.png" -append +repage "$previews/menubar-mockup.png"

# One-page overview.
pad() { convert "$1" +repage -background '#f6f6f6' -flatten -bordercolor '#f6f6f6' -border 8 "$2"; }
convert "$previews/app-icon-512.png" -resize 300x300 "$tmp/icon-300.png"
pad "$tmp/icon-300.png" "$tmp/icon.png"
pad "$previews/app-icon-16-enlarged.png" "$tmp/a.png"
pad "$previews/menubar-glyph-16-enlarged.png" "$tmp/b.png"
pad "$previews/menubar-glyph-32-enlarged.png" "$tmp/c.png"
pad "$previews/menubar-mockup.png" "$tmp/d.png"
convert "$tmp/a.png" "$tmp/b.png" "$tmp/c.png" -background '#f6f6f6' +append "$tmp/small.png"
convert "$tmp/small.png" "$tmp/d.png" -background '#f6f6f6' -gravity center -append "$tmp/right.png"
convert "$tmp/icon.png" "$tmp/right.png" -background '#f6f6f6' -gravity center +append \
  -bordercolor '#f6f6f6' -border 8 "$previews/overview.png"

echo "Wrote previews to $previews"
