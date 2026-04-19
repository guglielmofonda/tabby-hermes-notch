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

    let telegram = TelegramClient.shared
    let audio = AudioRecorder()
    let localTranscriber = LocalTranscriber()

    private var cancellables: Set<AnyCancellable> = []
    private let logger = Logger(subsystem: "com.guglielmofonda.Tabby", category: "AppState")

    enum NotchMode: Equatable {
        case idle
        case setupPending
        case recording
        case transcribing
        case sending
        case waitingForHermes
        case showingResponse(String)
        case error(String)
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
        switch notchMode {
        case .idle:
            Task { await startRecording() }
        case .recording:
            Task { await stopRecordingAndTranscribe() }
        default:
            // don't interrupt transcribing / sending / waiting / response states via click
            break
        }
    }

    func dismissNotch() {
        switch notchMode {
        case .showingResponse, .error:
            notchMode = .idle
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

        do {
            let text = try await localTranscriber.transcribe(
                samples: samples,
                sampleRate: AudioRecorder.targetSampleRate
            )
            lastTranscript = text
            logger.info("Transcript (\(samples.count) samples): \(text, privacy: .public)")

            if text.isEmpty {
                notchMode = .error("Heard nothing usable. Try again, and speak up.")
            } else {
                // Phase 3 will hand this to TelegramClient. For now, show it in the notch.
                notchMode = .showingResponse(text)
                await Task.sleep(seconds: 5)
                if case .showingResponse = notchMode { notchMode = .idle }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? (error as NSError).localizedDescription
            logger.error("Transcription failed: \(message, privacy: .public)")
            notchMode = .error(message)
        }
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
