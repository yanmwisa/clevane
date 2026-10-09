#!/bin/bash
# Turns the 1024 px icon exported by the snapshot run (AppIconArtwork) into Clevane/Resources/AppIcon.icns.
# Usage: scripts/make-icon.sh path/to/AppIcon-1024.png
set -euo pipefail
source_png="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset" "$root/Clevane/Resources"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source_png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$source_png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$root/Clevane/Resources/AppIcon.icns"
echo "$root/Clevane/Resources/AppIcon.icns"
