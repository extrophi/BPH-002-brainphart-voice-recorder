#!/usr/bin/env bash
set -euo pipefail

# BrainPhart Voice DMG Packaging Script
# Creates unsigned DMG for drag-and-drop install.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
DMG_DIR="${BUILD_DIR}/dmg"
BINARY_NAME="VoiceRecorder"
DISPLAY_NAME="BrainPhart Voice"
DMG_OUTPUT="${BUILD_DIR}/BrainPhartVoice.dmg"

echo "=== Creating DMG for ${DISPLAY_NAME} ==="

# Find built binary
BIN_PATH="$(swift build -c release --package-path "${PROJECT_ROOT}" --show-bin-path)/${BINARY_NAME}"
if [ ! -f "${BIN_PATH}" ]; then
    echo "ERROR: Binary not found at ${BIN_PATH}. Run 'swift build -c release' first."
    exit 1
fi

# Create .app bundle structure
APP_BUNDLE="${DMG_DIR}/${DISPLAY_NAME}.app"
rm -rf "${DMG_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources/models"

# Copy binary
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"

# Copy SPM resource bundle (contains brainphart logo)
BIN_DIR="$(dirname "${BIN_PATH}")"
RESOURCE_BUNDLE="${BIN_DIR}/VoiceRecorder_VoiceRecorder.bundle"
if [ -d "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
    echo "Copied resource bundle"
fi

# Copy model
MODEL_PATH="${PROJECT_ROOT}/Resources/models/ggml-base.en.bin"
if [ -f "${MODEL_PATH}" ]; then
    cp "${MODEL_PATH}" "${APP_BUNDLE}/Contents/Resources/models/"
fi

# Generate .icns from source PNG
ICON_PATH="${PROJECT_ROOT}/assets/img/brainph-icon.png"
if [ -f "${ICON_PATH}" ]; then
    ICONSET_DIR="/tmp/AppIcon.iconset"
    rm -rf "${ICONSET_DIR}"
    mkdir -p "${ICONSET_DIR}"
    sips -z 16 16     "${ICON_PATH}" --out "${ICONSET_DIR}/icon_16x16.png"      >/dev/null
    sips -z 32 32     "${ICON_PATH}" --out "${ICONSET_DIR}/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "${ICON_PATH}" --out "${ICONSET_DIR}/icon_32x32.png"      >/dev/null
    sips -z 64 64     "${ICON_PATH}" --out "${ICONSET_DIR}/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "${ICON_PATH}" --out "${ICONSET_DIR}/icon_128x128.png"    >/dev/null
    sips -z 256 256   "${ICON_PATH}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "${ICON_PATH}" --out "${ICONSET_DIR}/icon_256x256.png"    >/dev/null
    sips -z 512 512   "${ICON_PATH}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "${ICON_PATH}" --out "${ICONSET_DIR}/icon_512x512.png"    >/dev/null
    sips -z 1024 1024 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "${ICONSET_DIR}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    rm -rf "${ICONSET_DIR}"
    echo "Generated AppIcon.icns from ${ICON_PATH}"
else
    echo "WARNING: Icon source not found at ${ICON_PATH}"
fi

# Add Applications symlink for drag-and-drop install
ln -sf /Applications "${DMG_DIR}/Applications"

# Create Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>VoiceRecorder</string>
    <key>CFBundleIdentifier</key>
    <string>art.brainph.voice</string>
    <key>CFBundleName</key>
    <string>BrainPhart Voice</string>
    <key>CFBundleDisplayName</key>
    <string>BrainPhart Voice</string>
    <key>CFBundleVersion</key>
    <string>0.2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>BrainPhart Voice needs microphone access to record audio for local transcription.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>BrainPhart Voice needs accessibility access to paste transcribed text at your cursor location.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

# Create DMG (read-write first, then convert to compressed)
rm -f "${DMG_OUTPUT}" "${DMG_OUTPUT%.dmg}-rw.dmg"
echo "Packaging DMG..."

# Create read-write DMG so we can style it
hdiutil create -volname "${DISPLAY_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDRW \
    "${DMG_OUTPUT%.dmg}-rw.dmg"

# Mount it, style the window, then eject
MOUNT_DIR="/Volumes/${DISPLAY_NAME}"
hdiutil attach "${DMG_OUTPUT%.dmg}-rw.dmg" -mountpoint "${MOUNT_DIR}" -nobrowse
if [ -d "${MOUNT_DIR}" ]; then
    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${DISPLAY_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 200, 660, 460}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set position of item "${DISPLAY_NAME}.app" of container window to {120, 120}
        set position of item "Applications" of container window to {340, 120}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
    sync
    sleep 2
    # Retry detach — Finder may hold a reference from the AppleScript.
    hdiutil detach "${MOUNT_DIR}" 2>/dev/null || {
        sleep 3
        hdiutil detach "${MOUNT_DIR}" -force 2>/dev/null || true
    }
fi

# Convert to compressed read-only DMG
hdiutil convert "${DMG_OUTPUT%.dmg}-rw.dmg" \
    -format UDZO -o "${DMG_OUTPUT}"
rm -f "${DMG_OUTPUT%.dmg}-rw.dmg"

DMG_SIZE=$(stat -f%z "${DMG_OUTPUT}" 2>/dev/null || stat -c%s "${DMG_OUTPUT}" 2>/dev/null)
DMG_SIZE_MB=$((DMG_SIZE / 1048576))

echo ""
echo "=== DMG Created ==="
echo "Output: ${DMG_OUTPUT}"
echo "Size: ${DMG_SIZE_MB}MB"
echo ""
echo "Install: Open DMG, drag '${DISPLAY_NAME}.app' to Applications."
