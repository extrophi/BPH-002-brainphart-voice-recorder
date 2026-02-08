cmake_minimum_required(VERSION 3.20)
project(VoiceRecorderCore LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ---------------------------------------------------------------------------
# Paths — all resolved from project root, nothing hardcoded
# ---------------------------------------------------------------------------
set(WHISPER_DIR "${CMAKE_SOURCE_DIR}/Dependencies/whisper.cpp" CACHE PATH "Path to whisper.cpp source")
set(FFMPEG_DIR "${CMAKE_SOURCE_DIR}/Dependencies/ffmpeg-build" CACHE PATH "Path to FFmpeg install prefix")

# ---------------------------------------------------------------------------
# whisper.cpp — use pre-built static libs from setup.sh
# ---------------------------------------------------------------------------
set(WHISPER_BUILD_DIR "${WHISPER_DIR}/build")

# Find whisper static lib (may be in src/ or root of build dir)
find_library(WHISPER_LIB whisper PATHS "${WHISPER_BUILD_DIR}/src" "${WHISPER_BUILD_DIR}" NO_DEFAULT_PATH)
find_library(GGML_LIB ggml PATHS "${WHISPER_BUILD_DIR}/ggml/src" "${WHISPER_BUILD_DIR}" NO_DEFAULT_PATH)

if(NOT WHISPER_LIB)
    message(FATAL_ERROR "whisper.cpp not built. Run 'bash Scripts/setup.sh' first.\nSearched: ${WHISPER_BUILD_DIR}")
endif()

set(WHISPER_INCLUDE_DIR "${WHISPER_DIR}/include")

# ---------------------------------------------------------------------------
# FFmpeg — use pre-built static libs from setup.sh
# ---------------------------------------------------------------------------
set(FFMPEG_LIB_DIR "${FFMPEG_DIR}/lib")
set(FFMPEG_INCLUDE_DIR "${FFMPEG_DIR}/include")

find_library(AVFORMAT_LIB avformat PATHS "${FFMPEG_LIB_DIR}" NO_DEFAULT_PATH)
find_library(AVCODEC_LIB avcodec PATHS "${FFMPEG_LIB_DIR}" NO_DEFAULT_PATH)
find_library(AVUTIL_LIB avutil PATHS "${FFMPEG_LIB_DIR}" NO_DEFAULT_PATH)
find_library(AVDEVICE_LIB avdevice PATHS "${FFMPEG_LIB_DIR}" NO_DEFAULT_PATH)
find_library(SWRESAMPLE_LIB swresample PATHS "${FFMPEG_LIB_DIR}" NO_DEFAULT_PATH)

if(NOT AVFORMAT_LIB)
    message(FATAL_ERROR "FFmpeg not built. Run 'bash Scripts/setup.sh' first.\nSearched: ${FFMPEG_LIB_DIR}")
endif()

# ---------------------------------------------------------------------------
# System frameworks (macOS)
# ---------------------------------------------------------------------------
find_library(METAL_FRAMEWORK Metal)
find_library(METALKIT_FRAMEWORK MetalKit)
find_library(ACCELERATE_FRAMEWORK Accelerate)
find_library(FOUNDATION_FRAMEWORK Foundation)
find_library(AVFOUNDATION_FRAMEWORK AVFoundation)
find_library(COREMEDIA_FRAMEWORK CoreMedia)
find_library(COREAUDIO_FRAMEWORK CoreAudio)
find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox)
find_library(SQLITE3_LIB sqlite3)

# ---------------------------------------------------------------------------
# VoiceRecorderCore static library
# ---------------------------------------------------------------------------
set(CORE_SOURCES
    Sources/VoiceRecorderCore/WhisperEngine.cpp
    Sources/VoiceRecorderCore/AudioRecorder.cpp
    Sources/VoiceRecorderCore/AudioConverter.cpp
    Sources/VoiceRecorderCore/DatabaseManager.cpp
    Sources/VoiceRecorderCore/StorageManager.cpp
)

add_library(VoiceRecorderCore STATIC ${CORE_SOURCES})

target_include_directories(VoiceRecorderCore PUBLIC
    "${CMAKE_SOURCE_DIR}/Sources/VoiceRecorderCore"
    "${WHISPER_INCLUDE_DIR}"
    "${WHISPER_DIR}/ggml/include"
    "${FFMPEG_INCLUDE_DIR}"
)

target_link_libraries(VoiceRecorderCore PUBLIC
    ${WHISPER_LIB}
    ${GGML_LIB}
    ${AVFORMAT_LIB}
    ${AVCODEC_LIB}
    ${AVUTIL_LIB}
    ${AVDEVICE_LIB}
    ${SWRESAMPLE_LIB}
    ${SQLITE3_LIB}
    ${METAL_FRAMEWORK}
    ${METALKIT_FRAMEWORK}
    ${ACCELERATE_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
    ${AVFOUNDATION_FRAMEWORK}
    ${COREMEDIA_FRAMEWORK}
    ${COREAUDIO_FRAMEWORK}
    ${AUDIOTOOLBOX_FRAMEWORK}
)
