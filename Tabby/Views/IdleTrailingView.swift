import SwiftUI

struct IdleTrailingView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tintColor)
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
            .onTapGesture { state.toggleRecording() }
    }

    private var iconName: String {
        switch state.notchMode {
        case .recording: return "stop.circle.fill"
        case .transcribing, .sending, .waitingForHermes: return "waveform"
        case .error: return "exclamationmark.triangle.fill"
        case .showingResponse: return "text.bubble.fill"
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
