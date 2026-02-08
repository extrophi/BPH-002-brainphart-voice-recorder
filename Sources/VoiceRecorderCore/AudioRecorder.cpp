#include "AudioRecorder.hpp"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <stdexcept>

// TODO: Include FFmpeg headers when linking against the real libraries:
//
// extern "C" {
// #include <libavdevice/avdevice.h>
// #include <libavformat/avformat.h>
// #include <libavcodec/avcodec.h>
// #include <libswresample/swresample.h>
// #include <libavutil/opt.h>
// #include <libavutil/audio_fifo.h>
// }

namespace vr {

// ---------------------------------------------------------------------------
// Construction / destruction
// ---------------------------------------------------------------------------

AudioRecorder::AudioRecorder() {
    // TODO: avdevice_register_all();
    //       — needed once per process so FFmpeg can find AVFoundation.
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

    // TODO: Open AVFoundation capture device via FFmpeg.
    //
    //   const AVInputFormat* avfoundation = av_find_input_format("avfoundation");
    //   if (!avfoundation) return false;
    //
    //   AVDictionary* options = nullptr;
    //   // "none:default" = no video, default audio device
    //   av_dict_set(&options, "sample_rate", "44100", 0);
    //   av_dict_set(&options, "channels",    "1",     0);
    //
    //   AVFormatContext* ifmt_ctx = nullptr;
    //   int ret = avformat_open_input(&ifmt_ctx, ":default", avfoundation, &options);
    //   if (ret < 0) return false;
    //
    //   ret = avformat_find_stream_info(ifmt_ctx, nullptr);
    //   if (ret < 0) { avformat_close_input(&ifmt_ctx); return false; }
    //
    //   fmt_ctx_in_ = ifmt_ctx;

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

    // TODO: Close the capture device.
    //
    //   if (fmt_ctx_in_) {
    //       avformat_close_input(reinterpret_cast<AVFormatContext**>(&fmt_ctx_in_));
    //       fmt_ctx_in_ = nullptr;
    //   }

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
        // TODO: Read one frame from the capture device.
        //
        //   AVPacket pkt;
        //   av_init_packet(&pkt);
        //   int ret = av_read_frame(
        //       reinterpret_cast<AVFormatContext*>(fmt_ctx_in_), &pkt);
        //   if (ret < 0) break;
        //
        //   // Decode the raw PCM from the capture device.
        //   AVFrame* frame = av_frame_alloc();
        //   int got_frame = 0;
        //   avcodec_send_packet(
        //       reinterpret_cast<AVCodecContext*>(codec_ctx_), &pkt);
        //   avcodec_receive_frame(
        //       reinterpret_cast<AVCodecContext*>(codec_ctx_), frame);
        //
        //   // Compute metering from the decoded PCM samples.
        //   float level = compute_rms(
        //       reinterpret_cast<const float*>(frame->data[0]),
        //       frame->nb_samples);
        //   current_level_.store(level);
        //   if (meter_cb_) meter_cb_(level);
        //
        //   // Encode to AAC and write to the current M4A chunk.
        //   // ... (encode frame, write packet to fmt_ctx_out_) ...
        //
        //   av_frame_free(&frame);
        //   av_packet_unref(&pkt);

        // STUB: sleep to avoid busy-loop.
        std::this_thread::sleep_for(std::chrono::milliseconds(10));

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

    // TODO: Open an M4A/AAC output file with FFmpeg.
    //
    //   AVFormatContext* ofmt_ctx = nullptr;
    //   int ret = avformat_alloc_output_context2(
    //       &ofmt_ctx, nullptr, "ipod", current_chunk_path_.c_str());
    //   if (ret < 0 || !ofmt_ctx) return false;
    //
    //   // Find AAC encoder.
    //   const AVCodec* aac_codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
    //   if (!aac_codec) { avformat_free_context(ofmt_ctx); return false; }
    //
    //   AVStream* out_stream = avformat_new_stream(ofmt_ctx, aac_codec);
    //   AVCodecContext* enc_ctx = avcodec_alloc_context3(aac_codec);
    //   enc_ctx->sample_rate    = kSampleRate;
    //   enc_ctx->channels       = kChannels;
    //   enc_ctx->channel_layout = AV_CH_LAYOUT_MONO;
    //   enc_ctx->sample_fmt     = AV_SAMPLE_FMT_FLTP;
    //   enc_ctx->bit_rate       = 128000;
    //
    //   if (ofmt_ctx->oformat->flags & AVFMT_GLOBALHEADER)
    //       enc_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    //
    //   avcodec_open2(enc_ctx, aac_codec, nullptr);
    //   avcodec_parameters_from_context(out_stream->codecpar, enc_ctx);
    //
    //   avio_open(&ofmt_ctx->pb, current_chunk_path_.c_str(), AVIO_FLAG_WRITE);
    //   avformat_write_header(ofmt_ctx, nullptr);
    //
    //   fmt_ctx_out_ = ofmt_ctx;
    //   codec_ctx_   = enc_ctx;

    return true;
}

// ---------------------------------------------------------------------------
// finalize_chunk
// ---------------------------------------------------------------------------

void AudioRecorder::finalize_chunk() {
    if (current_chunk_path_.empty()) {
        return;
    }

    // TODO: Write trailer and close the output file.
    //
    //   if (fmt_ctx_out_) {
    //       AVFormatContext* ofmt = reinterpret_cast<AVFormatContext*>(fmt_ctx_out_);
    //       av_write_trailer(ofmt);
    //       avio_closep(&ofmt->pb);
    //       avformat_free_context(ofmt);
    //       fmt_ctx_out_ = nullptr;
    //   }
    //   if (codec_ctx_) {
    //       avcodec_free_context(
    //           reinterpret_cast<AVCodecContext**>(&codec_ctx_));
    //       codec_ctx_ = nullptr;
    //   }

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
