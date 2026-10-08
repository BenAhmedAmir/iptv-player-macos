#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"

echo "🔨 Building IPTV Player ($CONFIG) for Apple Silicon..."
swift build -c "$CONFIG"

BIN_PATH="$DIR/.build/arm64-apple-macosx/$CONFIG/IPTVPlayer"
APP_DIR="$DIR/build/IPTV Player.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Packaging into $APP_DIR..."

# Update the bundle IN PLACE — never `rm -rf` it.
#
# A login-keychain ACL records its trusted application by the bundle's filesystem
# identity, not merely by path and code signature. Deleting and recreating the
# bundle therefore makes the rebuilt app a stranger to the Keychain items it
# created, and macOS prompts for the login password on every launch — even though
# the designated requirement is unchanged. Overwriting the contents keeps the
# bundle's identity, so "Always Allow" survives rebuilds.
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# `cp` truncates the destination rather than replacing it, preserving its inode.
cp "$BIN_PATH" "$MACOS_DIR/IPTV Player"
chmod +x "$MACOS_DIR/IPTV Player"

ICON_SRC="$DIR/IPTVPlayer/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    echo "🎨 Installing app icon..."
    cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
else
    echo "⚠️  No AppIcon.icns — run scripts/make_icon.sh to build it from export/."
fi

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>IPTV Player</string>
    <key>CFBundleIdentifier</key>
    <string>com.iptvplayer.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>IPTV Player</string>
    <key>CFBundleDisplayName</key>
    <string>IPTV Player</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.entertainment</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>M3U Playlist</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>m3u</string>
                <string>m3u8</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
        </dict>
    </array>
</dict>
</plist>
EOF

: "${FRAMEWORKS_DIR:="$CONTENTS_DIR/Frameworks"}"
VLCKIT="$DIR/vendor/VLCKit.xcframework/macos-arm64_x86_64/VLCKit.framework"

if [ ! -d "$VLCKIT" ]; then
    echo "❌ VLCKit is missing. Run scripts/fetch_vlckit.sh first." >&2
    exit 1
fi

# The executable links VLCKit as @loader_path/../Frameworks/..., which resolves to
# Contents/Frameworks once the binary sits in Contents/MacOS. VOD playback uses it
# for the Matroska/AVI containers AVFoundation cannot demux.
echo "🎞️  Embedding VLCKit..."
mkdir -p "$FRAMEWORKS_DIR"
# rsync --delete syncs in place (removing stale files) without destroying and
# recreating the directory, for the same Keychain-ACL reason as above.
rsync -a --delete "$VLCKIT/" "$FRAMEWORKS_DIR/VLCKit.framework/"

# Prefer a real signing identity. An ad-hoc signature ties the app's designated
# requirement to the binary's cdhash, which changes on every build and therefore
# invalidates the Keychain ACLs holding the user's Xtream credentials — macOS then
# prompts for the login keychain password. See scripts/create_signing_cert.sh.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    for CANDIDATE in "IPTV Player Dev" "Developer ID Application" "Apple Development"; do
        if security find-identity -v -p codesigning | grep -qF "$CANDIDATE"; then
            IDENTITY="$CANDIDATE"
            break
        fi
    done
fi

if [ -n "$IDENTITY" ]; then
    echo "🔏 Code signing as \"$IDENTITY\"..."
    # Nested code must be signed before the enclosing bundle, otherwise sealing
    # the app would cover an unsigned framework and fail validation.
    codesign --force --sign "$IDENTITY" "$FRAMEWORKS_DIR/VLCKit.framework"
    codesign --force --sign "$IDENTITY" \
        --entitlements "$DIR/IPTVPlayer/IPTVPlayer.entitlements" \
        "$APP_DIR"
else
    echo "🔏 Code signing (ad-hoc)..."
    codesign --force --sign - "$FRAMEWORKS_DIR/VLCKit.framework"
    codesign --force --sign - \
        --entitlements "$DIR/IPTVPlayer/IPTVPlayer.entitlements" \
        "$APP_DIR"
    echo "⚠️  No code-signing identity found, so this build is signed ad-hoc."
    echo "   macOS will re-prompt for your login keychain password after every"
    echo "   rebuild. Run scripts/create_signing_cert.sh once to stop that."
fi

echo "✨ Successfully built: $APP_DIR"
