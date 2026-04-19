import Foundation

protocol Transcriber {
    /// Transcribe a PCM Float32 array at `sampleRate` to text.
    func transcribe(samples: [Float], sampleRate: Double) async throws -> String

    /// Human-readable name, for settings UI.
    var displayName: String { get }
}

enum TranscriberError: Error, LocalizedError {
    case empty
    case modelLoad(String)
    case inference(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "The recording was too short."
        case .modelLoad(let m): return "Could not load transcription model: \(m)"
        case .inference(let m): return "Transcription failed: \(m)"
        }
    }
}
