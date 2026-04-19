import SwiftUI

struct TranscribingView: View {
    @ObservedObject var transcriber: LocalTranscriber = AppState.shared.localTranscriber

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 300, maxWidth: 440)
    }

    private var engine: SettingsStore.TranscriptionEngine {
        SettingsStore.transcriptionEngine
    }

    private var headline: String {
        switch engine {
        case .cloud:
            return "Uploading to OpenAI…"
        case .local:
            if transcriber.loadingMessage != nil {
                return "Preparing local transcription"
            }
            return "Transcribing locally…"
        }
    }

    private var subtitle: String? {
        switch engine {
        case .cloud:
            return "gpt-4o-transcribe"
        case .local:
            return transcriber.loadingMessage
        }
    }
}
