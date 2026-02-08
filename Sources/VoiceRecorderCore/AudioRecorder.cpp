#include "AudioRecorder.hpp"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <stdexcept>

extern "C" {
#include <libavdevice/avdevice.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/channel_layout.h>
}

namespace vr {

// ---------------------------------------------------------------------------
// Construction / destruction
// ---------------------------------------------------------------------------

AudioRecorder::AudioRecorder() {
    avdevice_register_all();
}

AudioRecorder::~AudioRecorder() {
    if (recording_.load()) {
        stop_recording();
    }
}

// ---------------------------------------------------------------------------
// start_recording
// ---------------------------------------------------------------------------

bool AudioRecorder::start_recording(const std::string& output_dir,
                                    const std::string& session_id,
                                    BurstCallback burst_cb,
                                    MeteringCallback meter_cb) {
    std::lock_guard<std::mutex> lock(mu_);

    if (recording_.load()) {
        return false;   // already recording
    }

    output_dir_  = output_dir;
    session_id_  = session_id;
    chunk_index_ = 0;
    burst_cb_    = std::move(burst_cb);
    meter_cb_    = std::move(meter_cb);

    // Ensure output directory exists.
    std::filesystem::create_directories(output_dir_);

    const AVInputFormat* avfoundation = av_find_input_format("avfoundation");
    if (!avfoundation) return false;

    AVDictionary* options = nullptr;
    av_dict_set(&options, "sample_rate", std::to_string(kSampleRate).c_str(), 0);
    av_dict_set(&options, "channels", std::to_string(kChannels).c_str(), 0);

    AVFormatContext* ifmt_ctx = nullptr;
    int ret = avformat_open_input(&ifmt_ctx, ":default", avfoundation, &options);
    av_dict_free(&options);
    if (ret < 0) return false;

    ret = avformat_find_stream_info(ifmt_ctx, nullptr);
    if (ret < 0) { avformat_close_input(&ifmt_ctx); return false; }

    fmt_ctx_in_ = ifmt_ctx;

    // Open the first output chunk.
    if (!open_new_chunk()) {
        return false;
    }

    recording_.store(true);
    record_thread_ = std::thread(&AudioRecorder::recording_loop, this);

    return true;
}

// ---------------------------------------------------------------------------
// stop_recording
// ---------------------------------------------------------------------------

std::string AudioRecorder::stop_recording() {
    if (!recording_.load()) {
        return "";
    }

    recording_.store(false);

    if (record_thread_.joinable()) {
        record_thread_.join();
    }

    std::lock_guard<std::mutex> lock(mu_);

    // Finalize the last chunk.
    finalize_chunk();

    std::string last_path = current_chunk_path_;

    if (fmt_ctx_in_) {
        avformat_close_input(reinterpret_cast<AVFormatContext**>(&fmt_ctx_in_));
        fmt_ctx_in_ = nullptr;
    }
    if (swr_ctx_) {
        swr_free(reinterpret_cast<SwrContext**>(&swr_ctx_));
        swr_ctx_ = nullptr;
    }

    current_level_.store(0.0f);
    return last_path;
}

// ---------------------------------------------------------------------------
// get_metering / is_recording / chunk_count
// ---------------------------------------------------------------------------

float AudioRecorder::get_metering() const {
    return current_level_.load();
}

bool AudioRecorder::is_recording() const {
    return recording_.load();
}

int AudioRecorder::chunk_count() const {
    std::lock_guard<std::mutex> lock(mu_);
    return chunk_index_;
}

// ---------------------------------------------------------------------------
// recording_loop  (runs on background thread)
// ---------------------------------------------------------------------------

void AudioRecorder::recording_loop() {
    using Clock = std::chrono::steady_clock;
    auto chunk_start = Clock::now();

    while (recording_.load()) {
        AVFormatContext* ifmt = reinterpret_cast<AVFormatContext*>(fmt_ctx_in_);
        AVPacket* pkt = av_packet_alloc();
        if (!pkt) break;

        int ret = av_read_frame(ifmt, pkt);
        if (ret < 0) {
            av_packet_free(&pkt);
            if (ret == AVERROR_EOF) break;
            continue;
        }

        // Get the raw audio data from the packet (AVFoundation gives us PCM directly)
        if (pkt->data && pkt->size > 0) {
            // Compute metering from raw PCM samples
            int sample_count = pkt->size / sizeof(float);
            if (sample_count > 0) {
                float level = compute_rms(reinterpret_cast<const float*>(pkt->data), sample_count);
                current_level_.store(level);
                if (meter_cb_) meter_cb_(level);
            }

            // Write the raw packet to the output M4A file
            AVFormatContext* ofmt = reinterpret_cast<AVFormatContext*>(fmt_ctx_out_);
            if (ofmt) {
                AVPacket* out_pkt = av_packet_alloc();
                if (out_pkt) {
                    // Re-encode from PCM to AAC
                    AVCodecContext* enc = reinterpret_cast<AVCodecContext*>(codec_ctx_);
                    if (enc) {
                        AVFrame* frame = av_frame_alloc();
                        frame->nb_samples = pkt->size / (sizeof(float) * kChannels);
                        frame->format = AV_SAMPLE_FMT_FLT;
                        frame->ch_layout = (AVChannelLayout)AV_CHANNEL_LAYOUT_MONO;
                        frame->sample_rate = kSampleRate;
                        av_frame_get_buffer(frame, 0);
                        memcpy(frame->data[0], pkt->data, pkt->size);

                        // Convert sample format if needed (PCM float -> AAC expects FLTP)
                        SwrContext* swr = reinterpret_cast<SwrContext*>(swr_ctx_);
                        if (swr) {
                            AVFrame* converted = av_frame_alloc();
                            converted->nb_samples = frame->nb_samples;
                            converted->format = AV_SAMPLE_FMT_FLTP;
                            converted->ch_layout = (AVChannelLayout)AV_CHANNEL_LAYOUT_MONO;
                            converted->sample_rate = kSampleRate;
                            av_frame_get_buffer(converted, 0);
                            swr_convert(swr,
                                        converted->extended_data, converted->nb_samples,
                                        (const uint8_t**)frame->extended_data, frame->nb_samples);
                            av_frame_free(&frame);
                            frame = converted;
                        }

                        avcodec_send_frame(enc, frame);
                        while (avcodec_receive_packet(enc, out_pkt) == 0) {
                            out_pkt->stream_index = 0;
                            av_interleaved_write_frame(ofmt, out_pkt);
                        }
                        av_frame_free(&frame);
                    }
                    av_packet_free(&out_pkt);
                }
            }
        }
        av_packet_free(&pkt);

        // Check if we've hit the 35-second burst boundary.
        auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
            Clock::now() - chunk_start);

        if (elapsed.count() >= kBurstDurationSec) {
            std::lock_guard<std::mutex> lock(mu_);
            finalize_chunk();
            open_new_chunk();
            chunk_start = Clock::now();
        }
    }
}

// ---------------------------------------------------------------------------
// open_new_chunk
// ---------------------------------------------------------------------------

bool AudioRecorder::open_new_chunk() {
    // Build path: <output_dir>/<session_id>_chunk_<N>.m4a
    current_chunk_path_ = output_dir_ + "/" + session_id_
                          + "_chunk_" + std::to_string(chunk_index_) + ".m4a";

    AVFormatContext* ofmt_ctx = nullptr;
    int ret = avformat_alloc_output_context2(&ofmt_ctx, nullptr, "ipod", current_chunk_path_.c_str());
    if (ret < 0 || !ofmt_ctx) return false;

    const AVCodec* aac_codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!aac_codec) { avformat_free_context(ofmt_ctx); return false; }

    AVStream* out_stream = avformat_new_stream(ofmt_ctx, aac_codec);
    AVCodecContext* enc_ctx = avcodec_alloc_context3(aac_codec);
    enc_ctx->sample_rate = kSampleRate;
    enc_ctx->ch_layout = (AVChannelLayout)AV_CHANNEL_LAYOUT_MONO;
    enc_ctx->sample_fmt = AV_SAMPLE_FMT_FLTP;
    enc_ctx->bit_rate = 128000;

    if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER)
        enc_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

    ret = avcodec_open2(enc_ctx, aac_codec, nullptr);
    if (ret < 0) {
        avcodec_free_context(&enc_ctx);
        avformat_free_context(ofmt_ctx);
        return false;
    }
    avcodec_parameters_from_context(out_stream->codecpar, enc_ctx);
    out_stream->time_base = (AVRational){1, kSampleRate};

    ret = avio_open(&ofmt_ctx->pb, current_chunk_path_.c_str(), AVIO_FLAG_WRITE);
    if (ret < 0) {
        avcodec_free_context(&enc_ctx);
        avformat_free_context(ofmt_ctx);
        return false;
    }
    avformat_write_header(ofmt_ctx, nullptr);

    // Set up sample format converter (PCM float interleaved -> float planar for AAC)
    SwrContext* swr = nullptr;
    ret = swr_alloc_set_opts2(&swr,
        &enc_ctx->ch_layout, AV_SAMPLE_FMT_FLTP, kSampleRate,
        &enc_ctx->ch_layout, AV_SAMPLE_FMT_FLT, kSampleRate,
        0, nullptr);
    if (ret >= 0) swr_init(swr);

    fmt_ctx_out_ = ofmt_ctx;
    codec_ctx_ = enc_ctx;
    swr_ctx_ = swr;

    return true;
}

// ---------------------------------------------------------------------------
// finalize_chunk
// ---------------------------------------------------------------------------

void AudioRecorder::finalize_chunk() {
    if (current_chunk_path_.empty()) {
        return;
    }

    if (fmt_ctx_out_) {
        // Flush encoder
        AVCodecContext* enc = reinterpret_cast<AVCodecContext*>(codec_ctx_);
        if (enc) {
            avcodec_send_frame(enc, nullptr);
            AVPacket* pkt = av_packet_alloc();
            while (avcodec_receive_packet(enc, pkt) == 0) {
                pkt->stream_index = 0;
                av_interleaved_write_frame(reinterpret_cast<AVFormatContext*>(fmt_ctx_out_), pkt);
            }
            av_packet_free(&pkt);
        }

        AVFormatContext* ofmt = reinterpret_cast<AVFormatContext*>(fmt_ctx_out_);
        av_write_trailer(ofmt);
        avio_closep(&ofmt->pb);
        avformat_free_context(ofmt);
        fmt_ctx_out_ = nullptr;
    }
    if (codec_ctx_) {
        AVCodecContext* enc = reinterpret_cast<AVCodecContext*>(codec_ctx_);
        avcodec_free_context(&enc);
        codec_ctx_ = nullptr;
    }
    if (swr_ctx_) {
        SwrContext* swr = reinterpret_cast<SwrContext*>(swr_ctx_);
        swr_free(&swr);
        swr_ctx_ = nullptr;
    }

    // Read the finalized chunk file from disk and fire the burst callback.
    if (burst_cb_ && std::filesystem::exists(current_chunk_path_)) {
        std::ifstream file(current_chunk_path_, std::ios::binary | std::ios::ate);
        if (file.is_open()) {
            auto size = file.tellg();
            file.seekg(0, std::ios::beg);

            AudioChunk chunk;
            chunk.session_id  = session_id_;
            chunk.chunk_index = chunk_index_;
            chunk.audio_data.resize(static_cast<size_t>(size));
            file.read(reinterpret_cast<char*>(chunk.audio_data.data()),
                      static_cast<std::streamsize>(size));
            chunk.duration_ms = kBurstDurationSec * 1000;

            burst_cb_(chunk);
        }
    }

    ++chunk_index_;
}

// ---------------------------------------------------------------------------
// compute_rms
// ---------------------------------------------------------------------------

float AudioRecorder::compute_rms(const float* samples, size_t count) {
    if (!samples || count == 0) return 0.0f;

    double sum = 0.0;
    for (size_t i = 0; i < count; ++i) {
        sum += static_cast<double>(samples[i]) * static_cast<double>(samples[i]);
    }
    float rms = static_cast<float>(std::sqrt(sum / static_cast<double>(count)));

    // Clamp to [0, 1].
    return std::min(1.0f, std::max(0.0f, rms));
}

} // namespace vr
