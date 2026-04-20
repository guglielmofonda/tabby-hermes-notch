import Foundation
import Combine
import SwiftUI
import OSLog

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var notchMode: NotchMode = .idle
    @Published var isSetupWindowOpen: Bool = false
    @Published var lastTranscript: String = ""
    @Published var conversation: [ConversationTurn] = []
    @Published var botDisplayName: String = SettingsStore.botDisplayName {
        didSet { SettingsStore.botDisplayName = botDisplayName }
    }
    /// True while the mouse is over the DynamicNotch panel (pill, chrome, or expanded area).
    /// Pumped from `DynamicNotch.$isHovering` by the AppDelegate so the idle view can react
    /// to hover over chrome the `compactTrailing` view itself doesn't cover.
    @Published var isPillHovering: Bool = false

    let telegram = TelegramClient.shared
    let audio = AudioRecorder()
    let localTranscriber = LocalTranscriber()
    let openAITranscriber = CloudTranscriber(provider: .openAI)
    let aquaVoiceTranscriber = CloudTranscriber(provider: .aquaVoice)

    private var cancellables: Set<AnyCancellable> = []
    private let logger = Logger(subsystem: "com.guglielmofonda.Tabby", category: "AppState")

    enum NotchMode: Equatable {
        case idle
        case setupPending
        case recording
        case transcribing
        case sending
        case waitingForHermes
        case showingConversation
        case error(String)
    }

    struct ConversationTurn: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let text: String
        let attributedText: AttributedString
        let timestamp: Date

        init(role: Role, text: String, attributedText: AttributedString? = nil, timestamp: Date) {
            self.role = role
            self.text = text
            self.attributedText = attributedText ?? AttributedString(text)
            self.timestamp = timestamp
        }

        enum Role: Equatable {
            case user
            case hermes
        }
    }

    private init() {
        telegram.$authStep
            .receive(on: DispatchQueue.main)
            .sink { [weak self] step in
                self?.applyAuthStep(step)
            }
            .store(in: &cancellables)
    }

    func bootstrap() {
        telegram.start()
    }

    // MARK: - Recording flow

    func toggleRecording() {
        logger.info("toggleRecording; mode=\(String(describing: self.notchMode), privacy: .public)")
        switch notchMode {
        case .idle:
            // Fresh conversation
            conversation.removeAll()
            Task { await startRecording() }
        case .recording:
            Task { await stopRecordingAndTranscribe() }
        case .showingConversation:
            // Follow-up: preserve conversation
            Task { await startRecording() }
        default:
            // don't interrupt transcribing / sending / waiting states via click
            break
        }
    }

    /// Record a follow-up after a Hermes response without clearing the conversation.
    func recordFollowUp() {
        guard notchMode == .showingConversation else { return }
        Task { await startRecording() }
    }

    /// Explicitly close the conversation and return the notch to idle.
    func dismissConversation() {
        conversation.removeAll()
        lastTranscript = ""
        notchMode = .idle
    }

    func dismissNotch() {
        switch notchMode {
        case .showingConversation, .error:
            dismissConversation()
        default:
            break
        }
    }

    private func startRecording() async {
        do {
            try await audio.start()
            notchMode = .recording
        } catch AudioRecorder.AudioError.microphonePermissionDenied {
            notchMode = .error("Microphone permission denied. Enable it in System Settings → Privacy & Security → Microphone.")
        } catch {
            notchMode = .error(String(describing: error))
        }
    }

    private func stopRecordingAndTranscribe() async {
        let samples = audio.stop()
        logger.info("AppState received \(samples.count) samples for transcription")
        notchMode = .transcribing

        let transcript: String
        do {
            let engine = SettingsStore.transcriptionEngine
            logger.info("Transcribing via \(engine.rawValue, privacy: .public) engine")
            switch engine {
            case .local:
                transcript = try await localTranscriber.transcribe(
                    samples: samples,
                    sampleRate: AudioRecorder.targetSampleRate
                )
            case .openAI:
                transcript = try await openAITranscriber.transcribe(
                    samples: samples,
                    sampleRate: AudioRecorder.targetSampleRate
                )
            case .aquaVoice:
                transcript = try await aquaVoiceTranscriber.transcribe(
                    samples: samples,
                    sampleRate: AudioRecorder.targetSampleRate
                )
            }
            lastTranscript = transcript
            logger.info("Transcript (\(samples.count) samples): \(transcript, privacy: .public)")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? (error as NSError).localizedDescription
            logger.error("Transcription failed: \(message, privacy: .public)")
            notchMode = .error(message)
            return
        }

        if transcript.isEmpty {
            notchMode = .error("Heard nothing usable. Try again, and speak up.")
            return
        }

        conversation.append(ConversationTurn(role: .user, text: transcript, timestamp: Date()))

        // Send to Hermes via Telegram + await keyed reply.
        let key = CorrelationKey.new()
        let composed = CorrelationKey.decorate(
            prompt: transcript,
            with: key,
            maxLines: SettingsStore.maxResponseLines,
            extra: SettingsStore.additionalAppendedText
        )
        notchMode = .sending
        do {
            _ = try await telegram.sendPrompt(composed)
            logger.info("Sent prompt with key=\(key, privacy: .public)")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? (error as NSError).localizedDescription
            notchMode = .error(message)
            return
        }

        notchMode = .waitingForHermes
        let reply = await telegram.awaitHermesReply(containingKey: key, timeout: 120)
        guard let reply else {
            notchMode = .error("No reply from \(botDisplayName) within 2 minutes. Check Telegram directly.")
            return
        }

        let cleanedPlain = stripKey(from: reply.plain, key: key)
        let cleanedAttr = stripKey(fromAttributed: reply.attributed, key: key)
        conversation.append(ConversationTurn(
            role: .hermes,
            text: cleanedPlain,
            attributedText: cleanedAttr,
            timestamp: Date()
        ))
        notchMode = .showingConversation
    }

    /// Regex patterns used to strip the correlation `key: xxxxxx` marker from Hermes's reply.
    private func keyStripPatterns(for key: String) -> [String] {
        [
            "\\s*\\(?\\s*key:\\s*\(key)\\s*\\)?\\s*",
            "\\s*\\[\\s*key:\\s*\(key)\\s*\\]\\s*",
            "\\s*key:\\s*\(key)\\s*",
            "^\\s*\(key)\\s*[-–—:]\\s*",
            "\\s*\(key)\\s*",
        ]
    }

    /// Remove the `key: xxxxxx` boilerplate from Hermes's reply before displaying in the notch.
    private func stripKey(from text: String, key: String) -> String {
        var cleaned = text
        for pattern in keyStripPatterns(for: key) {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Same as `stripKey(from:key:)` but operates on `AttributedString` so the
    /// bold/italic/link formatting around the key tokens is preserved.
    private func stripKey(fromAttributed attr: AttributedString, key: String) -> AttributedString {
        var out = attr
        for pattern in keyStripPatterns(for: key) {
            while let range = out.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                out.replaceSubrange(range, with: AttributedString(" "))
            }
        }
        let chars = out.characters
        var start = chars.startIndex
        while start < chars.endIndex, chars[start].isWhitespace || chars[start].isNewline {
            start = chars.index(after: start)
        }
        var end = chars.endIndex
        while end > start {
            let prev = chars.index(before: end)
            if !(chars[prev].isWhitespace || chars[prev].isNewline) { break }
            end = prev
        }
        return AttributedString(out[start..<end])
    }

    private func applyAuthStep(_ step: AuthStep) {
        switch step {
        case .authenticated:
            if case .setupPending = notchMode { notchMode = .idle }
            isSetupWindowOpen = false
        case .launching:
            if notchMode != .idle { notchMode = .setupPending }
        case .error(let message):
            notchMode = .error(message)
            isSetupWindowOpen = true
        default:
            notchMode = .setupPending
            isSetupWindowOpen = true
        }
    }
}

private extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
