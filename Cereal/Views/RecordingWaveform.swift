import SwiftUI

/// A compact history of measured audio energy, with the newest sound at the right edge.
struct RecordingWaveform: View {
    let levels: [Float]
    var isPaused = false
    var tint: Color = .red

    private let barCount = 24
    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 1.5
    private let waveformHeight: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            for index in 0..<barCount {
                let levelIndex = index - (barCount - levels.count)
                let level = levelIndex >= 0 ? CGFloat(levels[levelIndex]) : 0
                let barHeight = max(2, min(size.height, 2 + level * (size.height - 2)))
                let rect = CGRect(x: CGFloat(index) * (barWidth + barSpacing),
                                  y: (size.height - barHeight) / 2,
                                  width: barWidth,
                                  height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                let opacity = isPaused ? 0.4 : (levelIndex < 0 ? 0.22 : 0.55 + 0.45 * Double(index) / Double(barCount - 1))
                context.fill(path, with: .color(tint.opacity(opacity)))
            }
        }
        .frame(width: CGFloat(barCount) * (barWidth + barSpacing) - barSpacing,
               height: waveformHeight)
        .accessibilityHidden(true)
    }
}
