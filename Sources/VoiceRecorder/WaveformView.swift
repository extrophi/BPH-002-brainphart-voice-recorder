//
//  WaveformView.swift
//  VoiceRecorder
//
//  Real-time waveform visualisation driven by an array of metering samples.
//
//  Renders thin vertical bars whose heights correspond to recent audio levels.
//  Uses SwiftUI Canvas for efficient rendering and smooth animation.
//

import SwiftUI

// MARK: - WaveformView

struct WaveformView: View {
    /// Array of metering samples (0.0 -- 1.0). Typically a circular buffer of
    /// the last ~100 values.
    let samples: [Float]

    /// Colour of the waveform bars.
    var barColor: Color = .green

    /// Number of visible bars. The view picks evenly-spaced samples from the
    /// input array to fill this count.
    var barCount: Int = 48

    /// Spacing between bars in points.
    var barSpacing: CGFloat = 1.0

    /// Minimum bar height as a fraction of the canvas height.
    /// Keep low so silence is near-flat and speech is dramatic.
    var minimumBarHeight: CGFloat = 0.02

    var body: some View {
        // Smooth samples with a 3-point moving average for cleaner bars.
        let smoothed: [Float] = samples.indices.map { i in
            let lo = max(0, i - 1)
            let hi = min(samples.count - 1, i + 1)
            return (samples[lo] + samples[i] + samples[hi]) / 3.0
        }

        Canvas { context, size in
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let barWidth = max(1, (size.width - totalSpacing) / CGFloat(barCount))

            for i in 0..<barCount {
                let sampleIndex = mapIndex(barIndex: i, barCount: barCount, sampleCount: smoothed.count)
                let amplitude = CGFloat(clamp(smoothed[sampleIndex]))
                let height = max(size.height * minimumBarHeight,
                                 size.height * amplitude)
                let x = CGFloat(i) * (barWidth + barSpacing)
                let y = (size.height - height) / 2.0

                let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                let path = RoundedRectangle(cornerRadius: barWidth / 2)
                    .path(in: rect)

                // Fade the opacity slightly for bars further from the trailing
                // edge so the waveform has a sense of direction.
                let opacity = 0.4 + 0.6 * (Double(i) / Double(max(1, barCount - 1)))
                context.fill(path, with: .color(barColor.opacity(opacity)))
            }
        }
        // Animate every change to the samples array smoothly.
        .animation(.easeOut(duration: 0.08), value: samples)
    }

    // MARK: - Helpers

    /// Map a bar index (0 ..< barCount) to a sample index (0 ..< sampleCount)
    /// so that the bars evenly cover the sample buffer.
    private func mapIndex(barIndex: Int, barCount: Int, sampleCount: Int) -> Int {
        guard sampleCount > 0, barCount > 0 else { return 0 }
        let ratio = Float(barIndex) / Float(max(1, barCount - 1))
        let idx = Int(ratio * Float(sampleCount - 1))
        return min(max(idx, 0), sampleCount - 1)
    }

    /// Clamp a value between 0 and 1.
    private func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}

// MARK: - WaveformStyle (convenience presets)

extension WaveformView {
    /// A small waveform suitable for the floating overlay pill.
    /// Thin 1pt bars, tightly packed for a professional audio look.
    static func compact(samples: [Float], color: Color) -> WaveformView {
        WaveformView(
            samples: samples,
            barColor: color,
            barCount: 40,
            barSpacing: 1.0,
            minimumBarHeight: 0.01
        )
    }

    /// A larger waveform for the history detail view.
    /// Dense thin bars for detailed waveform visualization.
    static func expanded(samples: [Float], color: Color) -> WaveformView {
        WaveformView(
            samples: samples,
            barColor: color,
            barCount: 80,
            barSpacing: 1.0,
            minimumBarHeight: 0.01
        )
    }
}

// MARK: - Preview

#Preview("Waveform - Simulated") {
    let fakeSamples: [Float] = (0..<100).map { i in
        let t = Float(i) / 100
        return 0.3 + 0.5 * abs(sin(t * .pi * 4))
    }

    VStack(spacing: 20) {
        WaveformView(samples: fakeSamples, barColor: .green, barCount: 48)
            .frame(width: 300, height: 60)
            .padding()
            .background(.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

        WaveformView.compact(samples: fakeSamples, color: .green)
            .frame(width: 120, height: 30)
            .padding()
            .background(.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    .padding()
}
