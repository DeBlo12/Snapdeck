#!/bin/bash
# Rebuilds Support/AppIcon.icns and docs/icon.png from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET" docs
for size in 16 32 128 256 512; do
    swift scripts/make-icon.swift "$SET/icon_${size}x${size}.png" "$size"
    swift scripts/make-icon.swift "$SET/icon_${size}x${size}@2x.png" "$((size * 2))"
done
iconutil -c icns "$SET" -o Support/AppIcon.icns
cp "$SET/icon_128x128@2x.png" docs/icon.png
echo "Built Support/AppIcon.icns"
