import SwiftUI
import OSLog

struct IdleTrailingView: View {
    @ObservedObject var state = AppState.shared
    private static let logger = Logger(subsystem: "com.guglielmofonda.Tabby", category: "TrailingTap")

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tintColor)
            .frame(width: 22, height: 22)
            .scaleEffect(state.isPillHovering ? 1.35 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: state.isPillHovering)
            .contentShape(Rectangle())
            .onTapGesture {
                Self.logger.info("trailing tap; mode=\(String(describing: state.notchMode), privacy: .public)")
                state.toggleRecording()
            }
    }

    private var iconName: String {
        switch state.notchMode {
        case .recording: return "stop.circle.fill"
        case .transcribing, .sending, .waitingForHermes: return "waveform"
        case .error: return "exclamationmark.triangle.fill"
        case .showingConversation: return "text.bubble.fill"
        default: return "waveform"
        }
    }

    private var tintColor: Color {
        switch state.notchMode {
        case .recording: return .red
        case .error: return .orange
        default: return .white.opacity(0.9)
        }
    }
}

#Preview {
    IdleTrailingView()
        .background(.black)
}
