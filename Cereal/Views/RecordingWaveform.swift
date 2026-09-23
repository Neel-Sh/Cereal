import SwiftUI

/// A single flowing line that responds to the microphone level.
struct RecordingWaveform: View {
    let level: Float
    var tint: Color = .red

    var body: some View {
        WaveformLine(amplitude: CGFloat(max(0.12, min(level, 1))))
            .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .frame(width: 54, height: 23)
            .animation(.easeOut(duration: 0.12), value: level)
            .accessibilityHidden(true)
    }
}

private struct WaveformLine: Shape {
    var amplitude: CGFloat

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = rect.midY
        let height = 2.5 + amplitude * (rect.height * 0.42)

        for step in 0...80 {
            let progress = CGFloat(step) / 80
            let envelope = pow(max(0, sin(.pi * progress)), 1.3)
            let wave = sin(progress * .pi * 4.5)
            let point = CGPoint(x: rect.minX + rect.width * progress,
                                y: center - wave * envelope * height)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
