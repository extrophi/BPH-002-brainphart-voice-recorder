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

# Copy model
MODEL_PATH="${PROJECT_ROOT}/Resources/models/ggml-base.en.bin"
if [ -f "${MODEL_PATH}" ]; then
    cp "${MODEL_PATH}" "${APP_BUNDLE}/Contents/Resources/models/"
fi

# Copy app icon if available
ICON_PATH="${PROJECT_ROOT}/assets/img/brainph-icon.png"
if [ -f "${ICON_PATH}" ]; then
    cp "${ICON_PATH}" "${APP_BUNDLE}/Contents/Resources/AppIcon.png"
fi

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
</dict>
</plist>
PLIST

# Create DMG
rm -f "${DMG_OUTPUT}"
echo "Packaging DMG..."
hdiutil create -volname "${DISPLAY_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    "${DMG_OUTPUT}"

DMG_SIZE=$(stat -f%z "${DMG_OUTPUT}" 2>/dev/null || stat -c%s "${DMG_OUTPUT}" 2>/dev/null)
DMG_SIZE_MB=$((DMG_SIZE / 1048576))

echo ""
echo "=== DMG Created ==="
echo "Output: ${DMG_OUTPUT}"
echo "Size: ${DMG_SIZE_MB}MB"
echo ""
echo "Install: Open DMG, drag '${DISPLAY_NAME}.app' to Applications."
