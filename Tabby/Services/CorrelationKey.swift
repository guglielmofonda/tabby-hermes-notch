import Foundation

enum CorrelationKey {
    /// Unambiguous base-32 alphabet (no 0/O/1/I/L confusion).
    private static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    /// Returns a 6-character key with ~30 bits of entropy — collision-safe for personal use.
    static func new() -> String {
        String((0..<6).map { _ in alphabet.randomElement()! })
    }

    /// Append the correlation key (and optional response-length cap) to the prompt so
    /// Hermes knows which message to echo the key in and how long to keep its reply.
    static func decorate(prompt: String, with key: String, maxLines: Int, extra: String = "") -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = max(1, maxLines)
        let extraTrimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = """
        \(trimmed)

        respond to this with key: \(key). Output should be \(lines) line\(lines == 1 ? "" : "s") long maximum.
        """
        if !extraTrimmed.isEmpty { result += " " + extraTrimmed }
        return result
    }
}
