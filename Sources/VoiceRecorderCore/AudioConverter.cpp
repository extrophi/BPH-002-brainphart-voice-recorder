#include "AudioConverter.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <stdexcept>

// TODO: Include FFmpeg headers when linking against the real libraries:
//
// extern "C" {
// #include <libavformat/avformat.h>
// #include <libavcodec/avcodec.h>
// #include <libswresample/swresample.h>
// #include <libavutil/opt.h>
// #include <libavutil/channel_layout.h>
// }

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

    // TODO: Full FFmpeg decode pipeline.  Outline:
    //
    //   // 1. Open input file.
    //   AVFormatContext* fmt_ctx = nullptr;
    //   int ret = avformat_open_input(&fmt_ctx, input_path.c_str(),
    //                                 nullptr, nullptr);
    //   if (ret < 0) return {};
    //
    //   ret = avformat_find_stream_info(fmt_ctx, nullptr);
    //   if (ret < 0) { avformat_close_input(&fmt_ctx); return {}; }
    //
    //   // 2. Find the audio stream.
    //   int audio_idx = av_find_best_stream(fmt_ctx, AVMEDIA_TYPE_AUDIO,
    //                                       -1, -1, nullptr, 0);
    //   if (audio_idx < 0) { avformat_close_input(&fmt_ctx); return {}; }
    //
    //   AVStream* stream = fmt_ctx->streams[audio_idx];
    //
    //   // 3. Open decoder.
    //   const AVCodec* decoder = avcodec_find_decoder(stream->codecpar->codec_id);
    //   AVCodecContext* dec_ctx = avcodec_alloc_context3(decoder);
    //   avcodec_parameters_to_context(dec_ctx, stream->codecpar);
    //   avcodec_open2(dec_ctx, decoder, nullptr);
    //
    //   // 4. Set up resampler: input format -> float32 mono @ target_sample_rate.
    //   SwrContext* swr = swr_alloc_set_opts(
    //       nullptr,
    //       AV_CH_LAYOUT_MONO, AV_SAMPLE_FMT_FLT, target_sample_rate,
    //       dec_ctx->channel_layout, dec_ctx->sample_fmt, dec_ctx->sample_rate,
    //       0, nullptr);
    //   swr_init(swr);
    //
    //   // 5. Read packets, decode frames, resample, collect PCM.
    //   AVPacket pkt;
    //   AVFrame* frame = av_frame_alloc();
    //   while (av_read_frame(fmt_ctx, &pkt) >= 0) {
    //       if (pkt.stream_index != audio_idx) {
    //           av_packet_unref(&pkt);
    //           continue;
    //       }
    //       avcodec_send_packet(dec_ctx, &pkt);
    //       while (avcodec_receive_frame(dec_ctx, frame) == 0) {
    //           // Estimate output sample count.
    //           int out_samples = av_rescale_rnd(
    //               swr_get_delay(swr, dec_ctx->sample_rate) + frame->nb_samples,
    //               target_sample_rate, dec_ctx->sample_rate, AV_ROUND_UP);
    //
    //           std::vector<float> buf(out_samples);
    //           uint8_t* out_buf = reinterpret_cast<uint8_t*>(buf.data());
    //           int converted = swr_convert(swr, &out_buf, out_samples,
    //                                       (const uint8_t**)frame->extended_data,
    //                                       frame->nb_samples);
    //           if (converted > 0) {
    //               pcm_out.insert(pcm_out.end(),
    //                              buf.begin(), buf.begin() + converted);
    //           }
    //       }
    //       av_packet_unref(&pkt);
    //   }
    //
    //   // 6. Flush decoder.
    //   avcodec_send_packet(dec_ctx, nullptr);
    //   while (avcodec_receive_frame(dec_ctx, frame) == 0) {
    //       int out_samples = av_rescale_rnd(
    //           swr_get_delay(swr, dec_ctx->sample_rate) + frame->nb_samples,
    //           target_sample_rate, dec_ctx->sample_rate, AV_ROUND_UP);
    //       std::vector<float> buf(out_samples);
    //       uint8_t* out_buf = reinterpret_cast<uint8_t*>(buf.data());
    //       int converted = swr_convert(swr, &out_buf, out_samples,
    //                                   (const uint8_t**)frame->extended_data,
    //                                   frame->nb_samples);
    //       if (converted > 0) {
    //           pcm_out.insert(pcm_out.end(),
    //                          buf.begin(), buf.begin() + converted);
    //       }
    //   }
    //
    //   // 7. Flush resampler.
    //   {
    //       int out_samples = swr_get_delay(swr, target_sample_rate);
    //       if (out_samples > 0) {
    //           std::vector<float> buf(out_samples);
    //           uint8_t* out_buf = reinterpret_cast<uint8_t*>(buf.data());
    //           int converted = swr_convert(swr, &out_buf, out_samples,
    //                                       nullptr, 0);
    //           if (converted > 0) {
    //               pcm_out.insert(pcm_out.end(),
    //                              buf.begin(), buf.begin() + converted);
    //           }
    //       }
    //   }
    //
    //   // 8. Cleanup.
    //   av_frame_free(&frame);
    //   swr_free(&swr);
    //   avcodec_free_context(&dec_ctx);
    //   avformat_close_input(&fmt_ctx);

    // STUB: return empty — no FFmpeg linked yet.
    (void)input_path;
    (void)target_sample_rate;
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

    // TODO: Use FFmpeg's libswresample for high-quality conversion:
    //
    //   SwrContext* swr = swr_alloc_set_opts(
    //       nullptr,
    //       AV_CH_LAYOUT_MONO, AV_SAMPLE_FMT_FLT, output_rate,
    //       AV_CH_LAYOUT_MONO, AV_SAMPLE_FMT_FLT, input_rate,
    //       0, nullptr);
    //   swr_init(swr);
    //
    //   int max_out = av_rescale_rnd(
    //       input_data.size(), output_rate, input_rate, AV_ROUND_UP);
    //   std::vector<float> output(max_out);
    //
    //   const uint8_t* in_buf  = reinterpret_cast<const uint8_t*>(input_data.data());
    //   uint8_t*       out_buf = reinterpret_cast<uint8_t*>(output.data());
    //
    //   int converted = swr_convert(swr, &out_buf, max_out,
    //                               &in_buf, (int)input_data.size());
    //   // Flush.
    //   int flushed = swr_convert(swr, &out_buf + converted * sizeof(float),
    //                             max_out - converted, nullptr, 0);
    //   output.resize(converted + flushed);
    //   swr_free(&swr);
    //   return output;

    // FALLBACK: simple linear interpolation (used until FFmpeg is linked).
    const double ratio = static_cast<double>(output_rate) /
                         static_cast<double>(input_rate);
    const size_t out_len = static_cast<size_t>(
        std::ceil(static_cast<double>(input_data.size()) * ratio));

    std::vector<float> output(out_len);

    for (size_t i = 0; i < out_len; ++i) {
        double src_idx = static_cast<double>(i) / ratio;
        size_t idx0 = static_cast<size_t>(src_idx);
        size_t idx1 = std::min(idx0 + 1, input_data.size() - 1);
        double frac = src_idx - static_cast<double>(idx0);
        output[i] = static_cast<float>(
            input_data[idx0] * (1.0 - frac) + input_data[idx1] * frac);
    }

    return output;
}

} // namespace vr
