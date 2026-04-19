import Foundation
import WhisperKit
import OSLog
import Combine

/// On-device transcription via WhisperKit (ANE-accelerated on Apple Silicon).
@MainActor
final class LocalTranscriber: ObservableObject, Transcriber {
    nonisolated var displayName: String { "Local (WhisperKit)" }

    @Published private(set) var isModelReady: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadingMessage: String?
    @Published private(set) var lastLoadError: String?

    private var pipe: WhisperKit?
    private var currentModel: String?
    private let logger = Logger(subsystem: "com.guglielmofonda.Tabby", category: "WhisperKit")

    /// Prepare the currently-selected WhisperKit model. Safe to call repeatedly.
    /// Returns true if the model is ready to transcribe after the call.
    @discardableResult
    func preloadCurrentModel() async -> Bool {
        let target = SettingsStore.whisperKitModel
        if let pipe, currentModel == target {
            _ = pipe
            isModelReady = true
            return true
        }
        guard !isLoading else { return isModelReady }
        isLoading = true
        loadingMessage = (pipe == nil || currentModel == nil)
            ? "Downloading \(short(target)) (first run, ~60–250 MB)…"
            : "Switching to \(short(target))…"
        lastLoadError = nil

        defer {
            isLoading = false
            loadingMessage = nil
        }

        do {
            logger.info("Loading WhisperKit model: \(target, privacy: .public)")
            let config = WhisperKitConfig(model: target)
            let loaded = try await WhisperKit(config)
            pipe = loaded
            currentModel = target
            isModelReady = true
            logger.info("WhisperKit model ready: \(target, privacy: .public)")
            return true
        } catch {
            let msg = String(describing: error)
            lastLoadError = msg
            isModelReady = false
            logger.error("WhisperKit model load failed: \(msg, privacy: .public)")
            return false
        }
    }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        if samples.isEmpty {
            throw TranscriberError.empty
        }

        if pipe == nil || currentModel != SettingsStore.whisperKitModel {
            let ok = await preloadCurrentModel()
            if !ok {
                throw TranscriberError.modelLoad(lastLoadError ?? "model failed to load")
            }
        }

        guard let pipe else {
            throw TranscriberError.modelLoad("pipeline nil after init")
        }

        logger.info("Transcribing \(samples.count) samples (~\(Double(samples.count) / sampleRate, format: .fixed(precision: 2))s)")
        let results = await pipe.transcribe(audioArrays: [samples])
        guard let first = results.first, let batch = first else {
            throw TranscriberError.inference("no result batches")
        }
        let text = batch.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Transcript: \(text, privacy: .public)")
        return text
    }

    private func short(_ model: String) -> String {
        if let dash = model.lastIndex(of: "-") {
            return String(model[model.index(after: dash)...])
        }
        return model
    }
}
