import Foundation
import Security

enum SettingsStore {
    private static let service = "com.guglielmofonda.Tabby"
    private static let defaults = UserDefaults.standard

    // MARK: - Keychain-backed (sensitive)

    static var apiId: Int32? {
        get { readKeychain(account: "apiId").flatMap { Int32($0) } }
        set { writeKeychain(newValue.map(String.init), account: "apiId") }
    }

    static var apiHash: String? {
        get { readKeychain(account: "apiHash") }
        set { writeKeychain(newValue, account: "apiHash") }
    }

    static var openAIKey: String? {
        get { readKeychain(account: "openAIKey") }
        set { writeKeychain(newValue, account: "openAIKey") }
    }

    // MARK: - UserDefaults-backed (non-sensitive)

    static var hermesBotUsername: String? {
        get { defaults.string(forKey: "hermesBotUsername") }
        set { defaults.set(newValue, forKey: "hermesBotUsername") }
    }

    static var hermesBotChatId: Int64 {
        get {
            let v = defaults.object(forKey: "hermesBotChatId") as? NSNumber
            return v?.int64Value ?? 0
        }
        set {
            if newValue == 0 { defaults.removeObject(forKey: "hermesBotChatId") }
            else { defaults.set(NSNumber(value: newValue), forKey: "hermesBotChatId") }
        }
    }

    static var hermesBotUserId: Int64 {
        get {
            let v = defaults.object(forKey: "hermesBotUserId") as? NSNumber
            return v?.int64Value ?? 0
        }
        set {
            if newValue == 0 { defaults.removeObject(forKey: "hermesBotUserId") }
            else { defaults.set(NSNumber(value: newValue), forKey: "hermesBotUserId") }
        }
    }

    enum TranscriptionEngine: String {
        case local, cloud
    }

    static var transcriptionEngine: TranscriptionEngine {
        get { TranscriptionEngine(rawValue: defaults.string(forKey: "transcriptionEngine") ?? "") ?? .local }
        set { defaults.set(newValue.rawValue, forKey: "transcriptionEngine") }
    }

    static var whisperKitModel: String {
        get { defaults.string(forKey: "whisperKitModel") ?? "openai_whisper-small.en" }
        set { defaults.set(newValue, forKey: "whisperKitModel") }
    }

    /// Cap how long Hermes's reply should be. Appended to every outgoing prompt.
    static var maxResponseLines: Int {
        get {
            let v = defaults.integer(forKey: "maxResponseLines")
            return v > 0 ? v : 5
        }
        set { defaults.set(max(1, min(30, newValue)), forKey: "maxResponseLines") }
    }

    /// User-facing name for the bot (shown in the notch, settings, error messages).
    /// Does NOT rename the Telegram bot itself — that's `hermesBotUsername`.
    static var botDisplayName: String {
        get {
            let v = defaults.string(forKey: "botDisplayName")?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v, !v.isEmpty { return v }
            return "Hermes"
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { defaults.removeObject(forKey: "botDisplayName") }
            else { defaults.set(trimmed, forKey: "botDisplayName") }
        }
    }

    /// nil means "use the built-in MacBook microphone if present, else system default."
    static var selectedInputDeviceID: UInt32? {
        get {
            let v = defaults.object(forKey: "selectedInputDeviceID") as? NSNumber
            return v?.uint32Value
        }
        set {
            if let newValue { defaults.set(NSNumber(value: newValue), forKey: "selectedInputDeviceID") }
            else { defaults.removeObject(forKey: "selectedInputDeviceID") }
        }
    }

    // MARK: - Paths

    static var tdlibDatabaseDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Tabby", isDirectory: true).appendingPathComponent("tdlib_db", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var tdlibFilesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Tabby", isDirectory: true).appendingPathComponent("tdlib_files", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Reset

    static func resetAll() {
        for account in ["apiId", "apiHash", "openAIKey"] {
            writeKeychain(nil, account: account)
        }
        for key in ["hermesBotUsername", "hermesBotChatId", "hermesBotUserId", "transcriptionEngine", "whisperKitModel"] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Keychain primitives

    private static func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func writeKeychain(_ value: String?, account: String) -> OSStatus {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let value, let data = value.data(using: .utf8) {
            let updateAttrs: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
            if status == errSecItemNotFound {
                var addQuery = baseQuery
                addQuery[kSecValueData as String] = data
                return SecItemAdd(addQuery as CFDictionary, nil)
            }
            return status
        } else {
            return SecItemDelete(baseQuery as CFDictionary)
        }
    }
}
