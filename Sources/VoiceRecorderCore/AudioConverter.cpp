#include "AudioConverter.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <stdexcept>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>
#include <libavutil/channel_layout.h>
}

namespace vr {

// ---------------------------------------------------------------------------
// Construction / destruction
// ---------------------------------------------------------------------------

AudioConverter::AudioConverter() = default;
AudioConverter::~AudioConverter() = default;

// ---------------------------------------------------------------------------
// m4a_to_pcm
// ---------------------------------------------------------------------------

std::vector<float> AudioConverter::m4a_to_pcm(const std::string& input_path,
                                              int target_sample_rate) const {
    std::vector<float> pcm_out;

    // 1. Open input file
    AVFormatContext* fmt_ctx = nullptr;
    int ret = avformat_open_input(&fmt_ctx, input_path.c_str(), nullptr, nullptr);
    if (ret < 0) {
        char errbuf[256];
        av_strerror(ret, errbuf, sizeof(errbuf));
        throw std::runtime_error(std::string("Failed to open audio file '") + input_path + "': " + errbuf);
    }

    ret = avformat_find_stream_info(fmt_ctx, nullptr);
    if (ret < 0) { avformat_close_input(&fmt_ctx); throw std::runtime_error("Failed to find stream info in audio file"); }

    // 2. Find the audio stream
    int audio_idx = av_find_best_stream(fmt_ctx, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
    if (audio_idx < 0) { avformat_close_input(&fmt_ctx); throw std::runtime_error("No audio stream found in file"); }

    AVStream* stream = fmt_ctx->streams[audio_idx];

    // 3. Open decoder
    const AVCodec* decoder = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!decoder) { avformat_close_input(&fmt_ctx); throw std::runtime_error("No decoder found for audio codec"); }
    AVCodecContext* dec_ctx = avcodec_alloc_context3(decoder);
    avcodec_parameters_to_context(dec_ctx, stream->codecpar);
    ret = avcodec_open2(dec_ctx, decoder, nullptr);
    if (ret < 0) {
        avcodec_free_context(&dec_ctx);
        avformat_close_input(&fmt_ctx);
        throw std::runtime_error("Failed to open audio decoder");
    }

    // 4. Set up resampler
    AVChannelLayout out_layout = AV_CHANNEL_LAYOUT_MONO;
    SwrContext* swr = nullptr;
    ret = swr_alloc_set_opts2(&swr,
        &out_layout, AV_SAMPLE_FMT_FLT, target_sample_rate,
        &dec_ctx->ch_layout, dec_ctx->sample_fmt, dec_ctx->sample_rate,
        0, nullptr);
    if (ret < 0 || swr_init(swr) < 0) {
        avcodec_free_context(&dec_ctx);
        avformat_close_input(&fmt_ctx);
        if (swr) swr_free(&swr);
        throw std::runtime_error("Failed to initialize audio resampler");
    }

    // 5. Read packets, decode frames, resample
    AVPacket* pkt = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();
    while (av_read_frame(fmt_ctx, pkt) >= 0) {
        if (pkt->stream_index != audio_idx) {
            av_packet_unref(pkt);
            continue;
        }
        avcodec_send_packet(dec_ctx, pkt);
        while (avcodec_receive_frame(dec_ctx, frame) == 0) {
            int out_samples = av_rescale_rnd(
                swr_get_delay(swr, dec_ctx->sample_rate) + frame->nb_samples,
                target_sample_rate, dec_ctx->sample_rate, AV_ROUND_UP);

            std::vector<float> buf(out_samples);
            uint8_t* out_buf = reinterpret_cast<uint8_t*>(buf.data());
            int converted = swr_convert(swr, &out_buf, out_samples,
                                        (const uint8_t**)frame->extended_data,
                                        frame->nb_samples);
            if (converted > 0) {
                pcm_out.insert(pcm_out.end(), buf.begin(), buf.begin() + converted);
            }
        }
        av_packet_unref(pkt);
    }

    // 6. Flush decoder
    avcodec_send_packet(dec_ctx, nullptr);
    while (avcodec_receive_frame(dec_ctx, frame) == 0) {
        int out_samples = av_rescale_rnd(
            swr_get_delay(swr, dec_ctx->sample_rate) + frame->nb_samples,
            target_sample_rate, dec_ctx->sample_rate, AV_ROUND_UP);
        std::vector<float> buf(out_samples);
        uint8_t* out_buf = reinterpret_cast<uint8_t*>(buf.data());
        int converted = swr_convert(swr, &out_buf, out_samples,
                                    (const uint8_t**)frame->extended_data,
                                    frame->nb_samples);
        if (converted > 0) {
            pcm_out.insert(pcm_out.end(), buf.begin(), buf.begin() + converted);
        }
    }

    // 7. Flush resampler
    {
        int out_samples = swr_get_delay(swr, target_sample_rate);
        if (out_samples > 0) {
            std::vector<float> buf(out_samples);
            uint8_t* out_buf = reinterpret_cast<uint8_t*>(buf.data());
            int converted = swr_convert(swr, &out_buf, out_samples, nullptr, 0);
            if (converted > 0) {
                pcm_out.insert(pcm_out.end(), buf.begin(), buf.begin() + converted);
            }
        }
    }

    // 8. Cleanup
    av_frame_free(&frame);
    av_packet_free(&pkt);
    swr_free(&swr);
    avcodec_free_context(&dec_ctx);
    avformat_close_input(&fmt_ctx);

    return pcm_out;
}

// ---------------------------------------------------------------------------
// resample  (static)
// ---------------------------------------------------------------------------

std::vector<float> AudioConverter::resample(const std::vector<float>& input_data,
                                            int input_rate,
                                            int output_rate) {
    if (input_data.empty() || input_rate <= 0 || output_rate <= 0) {
        return {};
    }

    if (input_rate == output_rate) {
        return input_data;   // no-op
    }

    AVChannelLayout mono_layout = AV_CHANNEL_LAYOUT_MONO;
    SwrContext* swr = nullptr;
    int ret = swr_alloc_set_opts2(&swr,
        &mono_layout, AV_SAMPLE_FMT_FLT, output_rate,
        &mono_layout, AV_SAMPLE_FMT_FLT, input_rate,
        0, nullptr);
    if (ret < 0 || swr_init(swr) < 0) {
        if (swr) swr_free(&swr);
        return {};
    }

    int max_out = av_rescale_rnd(input_data.size(), output_rate, input_rate, AV_ROUND_UP);
    std::vector<float> output(max_out);

    const uint8_t* in_buf = reinterpret_cast<const uint8_t*>(input_data.data());
    uint8_t* out_buf = reinterpret_cast<uint8_t*>(output.data());

    int converted = swr_convert(swr, &out_buf, max_out, &in_buf, static_cast<int>(input_data.size()));
    // Flush
    if (converted >= 0) {
        int flushed = swr_convert(swr, &out_buf, max_out - converted, nullptr, 0);
        if (flushed > 0) converted += flushed;
    }
    swr_free(&swr);
    if (converted > 0) {
        output.resize(converted);
        return output;
    }
    return {};
}

} // namespace vr
