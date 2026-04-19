import Foundation
import OSLog

/// Cloud transcription via OpenAI's `/v1/audio/transcriptions` endpoint.
/// Encodes the captured 16 kHz mono Float32 PCM as a 16-bit WAV and uploads it via multipart form.
final class CloudTranscriber: Transcriber, @unchecked Sendable {
    var displayName: String { "Cloud (OpenAI Whisper)" }

    private let logger = Logger(subsystem: "com.guglielmofonda.Tabby", category: "CloudWhisper")
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    enum CloudError: LocalizedError {
        case noAPIKey
        case unauthorized
        case networkError(String)
        case httpError(Int, String)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No OpenAI API key. Open Tabby Settings → Cloud and paste your key."
            case .unauthorized:
                return "OpenAI rejected the API key (HTTP 401). Update it in Settings."
            case .networkError(let m):
                return "Network error talking to OpenAI: \(m)"
            case .httpError(let code, let body):
                let preview = body.prefix(160)
                return "OpenAI returned HTTP \(code): \(preview)"
            case .decodingFailed:
                return "Couldn't decode OpenAI response."
            }
        }
    }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        if samples.isEmpty { throw TranscriberError.empty }

        let apiKey = await MainActor.run { SettingsStore.openAIKey }
        guard let apiKey, !apiKey.isEmpty else { throw CloudError.noAPIKey }

        let wav = WAVEncoder.encode(samples: samples, sampleRate: sampleRate)
        logger.info("Uploading \(wav.count) bytes (\(samples.count) samples, \(samples.count / 16000)s) to OpenAI")

        let boundary = "TabbyBoundary-\(UUID().uuidString)"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.buildMultipartBody(boundary: boundary, wav: wav, model: "gpt-4o-transcribe")

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
        if http.statusCode == 401 { throw CloudError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            throw CloudError.httpError(http.statusCode, body)
        }

        struct WhisperResponse: Decodable { let text: String }
        guard let decoded = try? JSONDecoder().decode(WhisperResponse.self, from: data) else {
            throw CloudError.decodingFailed
        }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Cloud transcript: \(text, privacy: .public)")
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

        // RIFF chunk
        data.append("RIFF".data(using: .ascii)!)
        appendLE32(&data, 36 + dataSize)
        data.append("WAVE".data(using: .ascii)!)

        // fmt subchunk
        data.append("fmt ".data(using: .ascii)!)
        appendLE32(&data, 16)              // subchunk1 size for PCM
        appendLE16(&data, 1)               // audio format = PCM
        appendLE16(&data, numChannels)
        appendLE32(&data, sampleRate32)
        appendLE32(&data, byteRate)
        appendLE16(&data, blockAlign)
        appendLE16(&data, bitsPerSample)

        // data subchunk
        data.append("data".data(using: .ascii)!)
        appendLE32(&data, dataSize)

        // PCM samples
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
