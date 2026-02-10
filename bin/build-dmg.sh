#!/usr/bin/env bash
set -euo pipefail

# BrainPhart Voice — Full Build & DMG Packaging
# Cleans artifacts, rebuilds everything from scratch, creates signed .app in a DMG.
# Usage: bash bin/build-dmg.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
DEPS_DIR="${PROJECT_ROOT}/Dependencies"
BINARY_NAME="VoiceRecorder"
APP_NAME="BrainPhartVoice"
DISPLAY_NAME="BrainPhart Voice"
BUNDLE_ID="com.brainphart.voice"
VERSION="0.3.0"
DMG_STAGING="${BUILD_DIR}/dmg"
DMG_OUTPUT="${PROJECT_ROOT}/${APP_NAME}.dmg"

echo "=== ${DISPLAY_NAME} — Build & Package ==="
echo "Version: ${VERSION}"
echo ""

# ── Preflight checks ──────────────────────────────────────────────────────────

if [ ! -d "${DEPS_DIR}/whisper.cpp/build" ]; then
    echo "ERROR: whisper.cpp not built. Run 'bash Scripts/setup.sh' first."
    exit 1
fi
if [ ! -d "${DEPS_DIR}/ffmpeg-build/lib" ]; then
    echo "ERROR: FFmpeg not built. Run 'bash Scripts/setup.sh' first."
    exit 1
fi
if [ ! -f "${PROJECT_ROOT}/Resources/models/ggml-base.en.bin" ]; then
    echo "ERROR: Whisper model not found. Run 'bash Scripts/setup.sh' first."
    exit 1
fi

# ── Step 1: Clean old artifacts ────────────────────────────────────────────────

echo "--- Cleaning old build artifacts ---"
rm -rf "${PROJECT_ROOT}/.build"
rm -rf "${DMG_STAGING}"
rm -f "${DMG_OUTPUT}"
rm -f "${DMG_OUTPUT%.dmg}-rw.dmg"

# Clean CMake build objects but keep cache
if [ -f "${BUILD_DIR}/Makefile" ]; then
    cmake --build "${BUILD_DIR}" --target clean 2>/dev/null || true
fi

echo "Clean complete."
echo ""

# ── Step 2: Rebuild C++ static library ─────────────────────────────────────────

echo "--- Building C++ static library ---"
cmake -B "${BUILD_DIR}" -S "${PROJECT_ROOT}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_METAL=ON

cmake --build "${BUILD_DIR}" -j "$(sysctl -n hw.ncpu)"

if [ ! -f "${BUILD_DIR}/libVoiceRecorderCore.a" ]; then
    echo "ERROR: C++ static lib not produced."
    exit 1
fi
echo "C++ lib: ${BUILD_DIR}/libVoiceRecorderCore.a"
echo ""

# ── Step 3: Build Swift release binary ─────────────────────────────────────────

echo "--- Building Swift release binary ---"
swift build -c release --package-path "${PROJECT_ROOT}" 2>&1

RELEASE_BIN="${PROJECT_ROOT}/.build/release/${BINARY_NAME}"
if [ ! -f "${RELEASE_BIN}" ]; then
    echo "ERROR: Release binary not found at ${RELEASE_BIN}"
    exit 1
fi
echo "Binary: ${RELEASE_BIN} ($(du -h "${RELEASE_BIN}" | cut -f1))"
echo ""

# ── Step 4: Create .app bundle ─────────────────────────────────────────────────

echo "--- Creating .app bundle ---"
APP_BUNDLE="${DMG_STAGING}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources/models"

# Copy binary
cp "${RELEASE_BIN}" "${CONTENTS}/MacOS/${BINARY_NAME}"

# Copy whisper model
cp "${PROJECT_ROOT}/Resources/models/ggml-base.en.bin" "${CONTENTS}/Resources/models/"

# Generate .icns from 1024x1024 source icon
ICON_SRC="${PROJECT_ROOT}/assets/img/brainph-icon.png"
if [ -f "${ICON_SRC}" ]; then
    ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
    rm -rf "${ICONSET_DIR}"
    mkdir -p "${ICONSET_DIR}"

    sips -z 16 16     "${ICON_SRC}" --out "${ICONSET_DIR}/icon_16x16.png"      >/dev/null
    sips -z 32 32     "${ICON_SRC}" --out "${ICONSET_DIR}/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "${ICON_SRC}" --out "${ICONSET_DIR}/icon_32x32.png"      >/dev/null
    sips -z 64 64     "${ICON_SRC}" --out "${ICONSET_DIR}/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_128x128.png"    >/dev/null
    sips -z 256 256   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_256x256.png"    >/dev/null
    sips -z 512 512   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "${ICON_SRC}" --out "${ICONSET_DIR}/icon_512x512.png"    >/dev/null
    sips -z 1024 1024 "${ICON_SRC}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "${ICONSET_DIR}" -o "${CONTENTS}/Resources/AppIcon.icns"
    rm -rf "${ICONSET_DIR}"
    echo "Generated AppIcon.icns from ${ICON_SRC}"
fi

# Write Info.plist
cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${BINARY_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>BrainPhart Voice needs microphone access to record audio for local transcription.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>BrainPhart Voice needs accessibility access to paste transcribed text at your cursor location.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "App bundle created at ${APP_BUNDLE}"
echo ""

# ── Step 5: Ad-hoc code sign ──────────────────────────────────────────────────

echo "--- Code signing (ad-hoc) ---"
codesign --force --deep -s - "${APP_BUNDLE}"
echo "Signed: $(codesign -dv "${APP_BUNDLE}" 2>&1 | grep 'Signature=')"
echo ""

# ── Step 6: Create DMG ────────────────────────────────────────────────────────

echo "--- Creating DMG ---"

# Add Applications symlink for drag-and-drop install
ln -sf /Applications "${DMG_STAGING}/Applications"

# Create compressed read-only DMG directly (no rw intermediate)
hdiutil create -volname "${DISPLAY_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    -fs HFS+ \
    -imagekey zlib-level=9 \
    "${DMG_OUTPUT}"

# ── Done ───────────────────────────────────────────────────────────────────────

DMG_SIZE=$(stat -f%z "${DMG_OUTPUT}" 2>/dev/null || echo "0")
DMG_SIZE_MB=$((DMG_SIZE / 1048576))

echo ""
echo "========================================="
echo "  ${DISPLAY_NAME} v${VERSION}"
echo "  DMG: ${DMG_OUTPUT}"
echo "  Size: ${DMG_SIZE_MB}MB"
echo "========================================="
echo ""
echo "Install: Open DMG, drag '${APP_NAME}.app' to Applications."
