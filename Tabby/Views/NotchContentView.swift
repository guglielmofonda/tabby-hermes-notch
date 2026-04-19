import SwiftUI

/// The single expanded-state SwiftUI view the DynamicNotch presents.
/// Switches content based on `AppState.notchMode`.
struct NotchContentView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        content
            .foregroundStyle(.white)
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }
    }

    @ViewBuilder
    private var content: some View {
        switch state.notchMode {
        case .idle, .setupPending:
            IdleExpandedView()
        case .recording:
            RecordingView(audio: state.audio)
        case .transcribing:
            TranscribingView()
        case .sending:
            WaitingView(label: "Sending to \(state.botDisplayName)…")
        case .waitingForHermes:
            WaitingView(label: "Waiting for \(state.botDisplayName)…")
        case .showingConversation:
            ConversationView()
        case .error(let msg):
            NotchErrorView(text: msg)
        }
    }

    private func handleTap() {
        switch state.notchMode {
        case .recording:
            // Tap anywhere on the expanded notch stops recording.
            state.toggleRecording()
        case .error:
            // Tap to dismiss an error.
            state.dismissNotch()
        default:
            // ConversationView has its own explicit buttons; don't dismiss on incidental taps.
            break
        }
    }
}
