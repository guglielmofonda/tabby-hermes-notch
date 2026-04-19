import SwiftUI

struct RecordingView: View {
    @ObservedObject var audio: AudioRecorder

    var body: some View {
        HStack(spacing: 14) {
            StopButton()
            Waveform(levels: audio.levelHistory)
                .frame(height: 28)
                .frame(maxWidth: .infinity)
            Text(formattedDuration(audio.durationSeconds))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 340)
    }

    private func formattedDuration(_ s: Double) -> String {
        let minutes = Int(s) / 60
        let seconds = Int(s) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct StopButton: View {
    @State private var isHovering = false

    var body: some View {
        Button {
            AppState.shared.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(isHovering ? 1.0 : 0.92))
                    .frame(width: 24, height: 24)
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white)
                    .frame(width: 9, height: 9)
            }
            .scaleEffect(isHovering ? 1.08 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Stop & transcribe")
    }
}

private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geo in
            let count = max(1, levels.count)
            let spacing: CGFloat = 3
            let barWidth = max(2.5, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, v in
                    let minHeight: CGFloat = 3
                    let maxHeight = geo.size.height
                    let h = minHeight + (maxHeight - minHeight) * CGFloat(v)
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(.white.opacity(0.5 + 0.4 * Double(v)))
                        .frame(width: barWidth, height: max(minHeight, h))
                        .animation(.easeOut(duration: 0.08), value: v)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
