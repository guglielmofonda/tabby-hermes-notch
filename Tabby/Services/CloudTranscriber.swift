import Foundation
import OSLog

/// Cloud transcription via an OpenAI-compatible `/audio/transcriptions` endpoint.
/// Encodes the captured 16 kHz mono Float32 PCM as a 16-bit WAV and uploads it via multipart form.
/// Supports OpenAI's own API and Aqua Voice (Avalon) — both share the multipart shape.
final class CloudTranscriber: Transcriber, @unchecked Sendable {
    enum Provider: String, CaseIterable {
        case openAI
        case aquaVoice

        var endpoint: URL {
            switch self {
            case .openAI: return URL(string: "https://api.openai.com/v1/audio/transcriptions")!
            case .aquaVoice: return URL(string: "https://api.aquavoice.com/api/v1/audio/transcriptions")!
            }
        }

        @MainActor
        var model: String {
            switch self {
            case .openAI: return "gpt-4o-transcribe"
            case .aquaVoice: return SettingsStore.aquaVoiceModel
            }
        }

        var label: String {
            switch self {
            case .openAI: return "OpenAI Whisper"
            case .aquaVoice: return "Aqua Voice"
            }
        }

        @MainActor
        var apiKey: String? {
            switch self {
            case .openAI: return SettingsStore.openAIKey
            case .aquaVoice: return SettingsStore.aquaVoiceKey
            }
        }
    }

    let provider: Provider
    var displayName: String { "Cloud (\(provider.label))" }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "tabby.app", category: "CloudTranscribe")

    init(provider: Provider) {
        self.provider = provider
    }

    enum CloudError: LocalizedError {
        case noAPIKey(providerLabel: String)
        case unauthorized(providerLabel: String)
        case networkError(String)
        case httpError(Int, String)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .noAPIKey(let label):
                return "No \(label) API key. Open Tabby Settings → Cloud and paste your key."
            case .unauthorized(let label):
                return "\(label) rejected the API key (HTTP 401). Update it in Settings."
            case .networkError(let m):
                return "Network error talking to cloud provider: \(m)"
            case .httpError(let code, let body):
                let preview = body.prefix(400)
                return "Provider returned HTTP \(code): \(preview)"
            case .decodingFailed:
                return "Couldn't decode the provider's response."
            }
        }
    }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        if samples.isEmpty { throw TranscriberError.empty }

        let (apiKey, model) = await MainActor.run { (provider.apiKey, provider.model) }
        guard let apiKey, !apiKey.isEmpty else {
            throw CloudError.noAPIKey(providerLabel: provider.label)
        }

        let wav = WAVEncoder.encode(samples: samples, sampleRate: sampleRate)
        let seconds = Double(samples.count) / sampleRate
        logger.info("Uploading \(wav.count) bytes (~\(seconds, format: .fixed(precision: 2))s) to \(self.provider.label, privacy: .public)")

        let boundary = "TabbyBoundary-\(UUID().uuidString)"
        var req = URLRequest(url: provider.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.buildMultipartBody(
            boundary: boundary,
            wav: wav,
            model: model
        )
        logger.info("\(self.provider.label, privacy: .public): POST \(self.provider.endpoint.absoluteString, privacy: .public) model=\(model, privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw CloudError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CloudError.networkError("non-HTTP response")
        }
        if http.statusCode == 401 { throw CloudError.unauthorized(providerLabel: provider.label) }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            logger.error("\(self.provider.label, privacy: .public) returned HTTP \(http.statusCode): \(body, privacy: .public)")
            throw CloudError.httpError(http.statusCode, body)
        }

        struct TranscriptionResponse: Decodable { let text: String }
        guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
            throw CloudError.decodingFailed
        }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("\(self.provider.label, privacy: .public) transcript: \(text, privacy: .public)")
        return text
    }

    private static func buildMultipartBody(boundary: String, wav: Data, model: String) -> Data {
        var body = Data()
        let newline = "\r\n"
        func append(_ str: String) { body.append(str.data(using: .utf8)!) }

        append("--\(boundary)\(newline)")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\(newline)")
        append("Content-Type: audio/wav\(newline)\(newline)")
        body.append(wav)
        append(newline)

        append("--\(boundary)\(newline)")
        append("Content-Disposition: form-data; name=\"model\"\(newline)\(newline)")
        append("\(model)\(newline)")

        append("--\(boundary)\(newline)")
        append("Content-Disposition: form-data; name=\"response_format\"\(newline)\(newline)")
        append("json\(newline)")

        append("--\(boundary)--\(newline)")
        return body
    }
}

/// Minimal WAV (RIFF) encoder for mono 16-bit PCM at the given sample rate.
enum WAVEncoder {
    static func encode(samples: [Float], sampleRate: Double) -> Data {
        let sampleRate32 = UInt32(sampleRate)
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate32 * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = UInt32(samples.count) * UInt32(blockAlign)

        var data = Data()
        data.reserveCapacity(44 + Int(dataSize))

        data.append("RIFF".data(using: .ascii)!)
        appendLE32(&data, 36 + dataSize)
        data.append("WAVE".data(using: .ascii)!)

        data.append("fmt ".data(using: .ascii)!)
        appendLE32(&data, 16)
        appendLE16(&data, 1)
        appendLE16(&data, numChannels)
        appendLE32(&data, sampleRate32)
        appendLE32(&data, byteRate)
        appendLE16(&data, blockAlign)
        appendLE16(&data, bitsPerSample)

        data.append("data".data(using: .ascii)!)
        appendLE32(&data, dataSize)

        for s in samples {
            let clamped = max(-1, min(1, s))
            let value = Int16(clamped * 32767)
            appendLE16Signed(&data, value)
        }
        return data
    }

    private static func appendLE16(_ data: inout Data, _ v: UInt16) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func appendLE32(_ data: inout Data, _ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func appendLE16Signed(_ data: inout Data, _ v: Int16) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}
