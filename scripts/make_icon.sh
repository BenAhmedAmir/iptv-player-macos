#!/bin/bash
#
# Builds IPTVPlayer/Resources/AppIcon.icns from export/AppIcon.appiconset.
#
# The appiconset is the source of truth, but macOS app bundles want a single
# .icns. `iconutil` needs an .iconset directory whose files are named with the
# @2x convention, whereas the exported set uses -2x — hence the rename step
# rather than pointing iconutil straight at the appiconset.
#
# Re-run after replacing the artwork.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$DIR/export/AppIcon.appiconset"
DEST_DIR="$DIR/IPTVPlayer/Resources"
DEST="$DEST_DIR/AppIcon.icns"

if [ ! -d "$SRC" ]; then
    echo "❌ Missing $SRC" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

# The ten sizes macOS expects. Each entry is "<source name>:<iconutil name>".
PAIRS=(
    "icon_16x16.png:icon_16x16.png"
    "icon_16x16-2x.png:icon_16x16@2x.png"
    "icon_32x32.png:icon_32x32.png"
    "icon_32x32-2x.png:icon_32x32@2x.png"
    "icon_128x128.png:icon_128x128.png"
    "icon_128x128-2x.png:icon_128x128@2x.png"
    "icon_256x256.png:icon_256x256.png"
    "icon_256x256-2x.png:icon_256x256@2x.png"
    "icon_512x512.png:icon_512x512.png"
    "icon_512x512-2x.png:icon_512x512@2x.png"
)

for pair in "${PAIRS[@]}"; do
    from="${pair%%:*}"
    to="${pair##*:}"
    if [ ! -f "$SRC/$from" ]; then
        echo "❌ Missing $SRC/$from" >&2
        exit 1
    fi
    cp "$SRC/$from" "$ICONSET/$to"
done

echo "🎨 Building AppIcon.icns from $(ls "$ICONSET" | wc -l | tr -d ' ') images..."
mkdir -p "$DEST_DIR"
iconutil --convert icns "$ICONSET" --output "$DEST"

echo "✅ Wrote $DEST ($(du -h "$DEST" | cut -f1))"
