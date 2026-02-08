#!/usr/bin/env bash
set -euo pipefail

# VoiceRecorder DMG Packaging Script
# Creates unsigned DMG for drag-and-drop install.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
DMG_DIR="${BUILD_DIR}/dmg"
APP_NAME="VoiceRecorder"
DMG_OUTPUT="${BUILD_DIR}/${APP_NAME}.dmg"

echo "=== Creating DMG ==="

# Find built binary
BIN_PATH="$(swift build -c release --package-path "${PROJECT_ROOT}" --show-bin-path)/${APP_NAME}"
if [ ! -f "${BIN_PATH}" ]; then
    echo "ERROR: Binary not found at ${BIN_PATH}. Run 'bash Scripts/build.sh' first."
    exit 1
fi

# Create .app bundle structure
APP_BUNDLE="${DMG_DIR}/${APP_NAME}.app"
rm -rf "${DMG_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources/models"

# Copy binary
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy model
MODEL_PATH="${PROJECT_ROOT}/Resources/models/ggml-base.en.bin"
if [ -f "${MODEL_PATH}" ]; then
    cp "${MODEL_PATH}" "${APP_BUNDLE}/Contents/Resources/models/"
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
    <string>com.voicerecorder.app</string>
    <key>CFBundleName</key>
    <string>VoiceRecorder</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceRecorder needs microphone access to record audio for local transcription.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>VoiceRecorder needs accessibility access to paste transcribed text at your cursor location.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Create DMG
rm -f "${DMG_OUTPUT}"
echo "Packaging DMG..."
hdiutil create -volname "${APP_NAME}" \
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
echo "Install: Open DMG, drag VoiceRecorder.app to Applications."
