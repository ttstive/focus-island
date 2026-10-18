#!/bin/zsh
set -eu
cd "${0:A:h}/.."
ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/focus-island-icon.XXXXXX")/AppIcon.iconset"
mkdir -p "$ICONSET" assets
trap 'rm -rf "${ICONSET:h}"' EXIT
SOURCE="Sources/FocusIsland/Resources/AppIcon.png"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  /usr/bin/sips -z "$retina" "$retina" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o assets/AppIcon.icns
