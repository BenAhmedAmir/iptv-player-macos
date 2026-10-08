#!/bin/bash
#
# Downloads VLCKit and installs a slimmed-down copy at vendor/VLCKit.xcframework.
#
# VLCKit plays the Matroska, AVI and FLV containers that AVFoundation cannot
# demux — roughly half of a typical Xtream VOD catalogue. Live TV still uses
# AVPlayer, so this only backs the movie and episode paths.
#
# The upstream archive is ~84 MB and expands to ~411 MB, almost all of which is
# a debug-symbol bundle. What actually ships is the 79 MB universal binary,
# thinned here to arm64 (~40 MB) to match the project's Apple Silicon target.
#
# Idempotent: skips the download when the framework is already in place.

set -euo pipefail

VERSION="3.7.3"
ARCHIVE="VLCKit-3.7.3-319ed2c0-79128878.tar.xz"
URL="https://download.videolan.org/pub/cocoapods/prod/$ARCHIVE"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$DIR/vendor"
DEST="$VENDOR/VLCKit.xcframework"

if [ -d "$DEST" ] && [ "${1:-}" != "--force" ]; then
    echo "✅ VLCKit already present at vendor/VLCKit.xcframework"
    echo "   Re-download with: scripts/fetch_vlckit.sh --force"
    exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "⬇️  Downloading VLCKit $VERSION (~84 MB)..."
curl -fL --progress-bar -o "$WORK_DIR/vlckit.tar.xz" "$URL"

echo "📂 Extracting..."
tar -xJf "$WORK_DIR/vlckit.tar.xz" -C "$WORK_DIR"

SRC="$(find "$WORK_DIR" -maxdepth 3 -name "VLCKit.xcframework" -type d | head -1)"
if [ -z "$SRC" ]; then
    echo "❌ VLCKit.xcframework not found in the archive." >&2
    exit 1
fi

mkdir -p "$VENDOR"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

# The debug symbols are ~323 MB and are never loaded at runtime.
find "$DEST" -name "dSYMs" -type d -prune -exec rm -rf {} + 2>/dev/null || true

SLICE="$(find "$DEST" -maxdepth 1 -type d -name "macos-*" | head -1)"
BINARY="$SLICE/VLCKit.framework/Versions/A/VLCKit"

if [ ! -f "$BINARY" ]; then
    echo "❌ Expected framework binary missing at $BINARY" >&2
    exit 1
fi

if lipo -info "$BINARY" | grep -q "x86_64"; then
    echo "✂️  Thinning to arm64..."
    lipo -thin arm64 "$BINARY" -output "$WORK_DIR/VLCKit.arm64"
    mv "$WORK_DIR/VLCKit.arm64" "$BINARY"
    # Thinning invalidates the vendor's signature; build_app.sh re-signs it.
    rm -rf "$SLICE/VLCKit.framework/Versions/A/_CodeSignature"
fi

echo
echo "✅ Installed vendor/VLCKit.xcframework"
echo "   arch:  $(lipo -info "$BINARY" | sed 's/.*: //')"
echo "   size:  $(du -sh "$DEST" | cut -f1)"
