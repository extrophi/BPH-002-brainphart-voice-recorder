#!/usr/bin/env bash
set -euo pipefail

# VoiceRecorder Build Script
# Builds the full app from source.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== VoiceRecorder Build ==="

# Verify setup has been run
DEPS_DIR="${PROJECT_ROOT}/Dependencies"
if [ ! -d "${DEPS_DIR}/whisper.cpp/build" ]; then
    echo "ERROR: Dependencies not built. Run 'bash Scripts/setup.sh' first."
    exit 1
fi
if [ ! -d "${DEPS_DIR}/ffmpeg-build/lib" ]; then
    echo "ERROR: FFmpeg not built. Run 'bash Scripts/setup.sh' first."
    exit 1
fi
if [ ! -f "${PROJECT_ROOT}/Resources/models/ggml-base.en.bin" ]; then
    echo "ERROR: Whisper model not downloaded. Run 'bash Scripts/setup.sh' first."
    exit 1
fi

# Build C++ core
echo ""
echo "--- Building C++ Core ---"
BUILD_DIR="${PROJECT_ROOT}/build"
cmake -B "${BUILD_DIR}" -S "${PROJECT_ROOT}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_DIR="${DEPS_DIR}/whisper.cpp" \
    -DFFMPEG_DIR="${DEPS_DIR}/ffmpeg-build"

cmake --build "${BUILD_DIR}" -j "$(sysctl -n hw.ncpu)"

# Build Swift app
echo ""
echo "--- Building Swift App ---"
swift build -c release \
    --package-path "${PROJECT_ROOT}" \
    -Xlinker -L"${BUILD_DIR}" \
    -Xlinker -L"${DEPS_DIR}/ffmpeg-build/lib" \
    -Xlinker -L"${DEPS_DIR}/whisper.cpp/build/src" \
    -Xlinker -L"${DEPS_DIR}/whisper.cpp/build/ggml/src"

echo ""
echo "=== Build Complete ==="
echo "Binary: $(swift build -c release --package-path "${PROJECT_ROOT}" --show-bin-path)/VoiceRecorder"
