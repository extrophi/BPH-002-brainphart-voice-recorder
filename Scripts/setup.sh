#!/usr/bin/env bash
set -euo pipefail

# VoiceRecorder Setup Script
# Initializes all dependencies from source. No Homebrew. No pip.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPS_DIR="${PROJECT_ROOT}/Dependencies"
RESOURCES_DIR="${PROJECT_ROOT}/Resources"

echo "=== VoiceRecorder Setup ==="
echo "Project root: ${PROJECT_ROOT}"

# ---------------------------------------------------------------------------
# 1. whisper.cpp (git submodule)
# ---------------------------------------------------------------------------
echo ""
echo "--- [1/3] whisper.cpp ---"
WHISPER_DIR="${DEPS_DIR}/whisper.cpp"

if [ ! -f "${WHISPER_DIR}/CMakeLists.txt" ]; then
    echo "Initializing whisper.cpp submodule..."
    git -C "${PROJECT_ROOT}" submodule update --init --recursive
else
    echo "whisper.cpp submodule already initialized."
fi

WHISPER_BUILD_DIR="${WHISPER_DIR}/build"
if [ ! -f "${WHISPER_BUILD_DIR}/src/libwhisper.a" ] && [ ! -f "${WHISPER_BUILD_DIR}/libwhisper.a" ]; then
    echo "Building whisper.cpp with Metal support..."
    cmake -B "${WHISPER_BUILD_DIR}" -S "${WHISPER_DIR}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DWHISPER_METAL=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DWHISPER_BUILD_EXAMPLES=OFF \
        -DWHISPER_BUILD_TESTS=OFF
    cmake --build "${WHISPER_BUILD_DIR}" -j "$(sysctl -n hw.ncpu)"
    echo "whisper.cpp built successfully."
else
    echo "whisper.cpp already built."
fi

# ---------------------------------------------------------------------------
# 2. FFmpeg (build from source — static libs)
# ---------------------------------------------------------------------------
echo ""
echo "--- [2/3] FFmpeg ---"
FFMPEG_SRC="${DEPS_DIR}/ffmpeg-src"
FFMPEG_BUILD="${DEPS_DIR}/ffmpeg-build"

if [ ! -f "${FFMPEG_BUILD}/lib/libavformat.a" ]; then
    if [ ! -d "${FFMPEG_SRC}" ]; then
        echo "Cloning FFmpeg n7.1..."
        git clone --depth 1 --branch n7.1 https://github.com/FFmpeg/FFmpeg.git "${FFMPEG_SRC}"
    fi

    echo "Configuring FFmpeg (static, minimal)..."
    mkdir -p "${FFMPEG_BUILD}"
    cd "${FFMPEG_SRC}"
    ./configure \
        --prefix="${FFMPEG_BUILD}" \
        --enable-static \
        --disable-shared \
        --disable-programs \
        --disable-doc \
        --disable-network \
        --disable-autodetect \
        --enable-avformat \
        --enable-avcodec \
        --enable-avutil \
        --enable-avdevice \
        --enable-swresample \
        --enable-demuxer=mov,wav \
        --enable-muxer=ipod,wav \
        --enable-decoder=aac,pcm_s16le,pcm_f32le \
        --enable-encoder=aac,pcm_s16le \
        --enable-protocol=file \
        --enable-filter=aresample \
        --enable-indev=avfoundation \
        --extra-cflags="-mmacosx-version-min=13.0" \
        --extra-ldflags="-mmacosx-version-min=13.0"

    echo "Building FFmpeg..."
    make -j "$(sysctl -n hw.ncpu)"
    make install
    cd "${PROJECT_ROOT}"
    echo "FFmpeg built successfully."
else
    echo "FFmpeg already built."
fi

# ---------------------------------------------------------------------------
# 3. Whisper model (ggml-base.en.bin)
# ---------------------------------------------------------------------------
echo ""
echo "--- [3/3] Whisper Model ---"
MODEL_DIR="${RESOURCES_DIR}/models"
MODEL_PATH="${MODEL_DIR}/ggml-base.en.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

mkdir -p "${MODEL_DIR}"

if [ ! -f "${MODEL_PATH}" ]; then
    echo "Downloading ggml-base.en.bin (148MB)..."
    curl -L --progress-bar -o "${MODEL_PATH}" "${MODEL_URL}"

    # Verify file size (should be ~148MB)
    FILE_SIZE=$(stat -f%z "${MODEL_PATH}" 2>/dev/null || stat -c%s "${MODEL_PATH}" 2>/dev/null)
    if [ "${FILE_SIZE}" -lt 100000000 ]; then
        echo "ERROR: Downloaded model is too small (${FILE_SIZE} bytes). Removing."
        rm -f "${MODEL_PATH}"
        exit 1
    fi
    echo "Model downloaded successfully (${FILE_SIZE} bytes)."
else
    echo "Model already downloaded."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Dependencies:"
echo "  whisper.cpp: ${WHISPER_DIR}"
echo "  FFmpeg:      ${FFMPEG_BUILD}"
echo "  Model:       ${MODEL_PATH}"
echo ""
echo "Next: bash Scripts/build.sh"
