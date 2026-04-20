import Foundation
import Combine
import TDLibKit
import OSLog

@MainActor
final class TelegramClient: ObservableObject {
    static let shared = TelegramClient()

    @Published private(set) var authStep: AuthStep = .launching
    @Published private(set) var lastError: String?
    @Published private(set) var passwordHint: String?

    /// Published chat_id for the resolved Hermes bot. 0 when unresolved.
    @Published private(set) var hermesBotChatId: Int64 = SettingsStore.hermesBotChatId
    @Published private(set) var hermesBotUserId: Int64 = SettingsStore.hermesBotUserId
    @Published private(set) var hermesBotTitle: String? = SettingsStore.hermesBotUsername

    struct IncomingMessage: Sendable {
        let id: Int64
        let chatId: Int64
        let senderUserId: Int64
        let text: String
        let attributed: AttributedString
        let receivedAt: Foundation.Date
    }

    struct HermesReply: Sendable {
        let plain: String
        let attributed: AttributedString
    }

    enum ClientError: LocalizedError {
        case notReady
        case botNotSelected
        case sendFailed(String)

        var errorDescription: String? {
            switch self {
            case .notReady: return "Telegram client isn't ready."
            case .botNotSelected: return "No Hermes bot selected. Re-run setup."
            case .sendFailed(let m): return "Couldn't send to Telegram: \(m)"
            }
        }
    }

    private var manager: TDLibClientManager?
    private var client: TDLibClient?
    private let logger = Logger(subsystem: "com.guglielmofonda.Tabby", category: "Telegram")

    /// Subscribers receive every new incoming Telegram message (from any chat).
    /// Callers filter by chat_id as needed.
    private var messageContinuations: [UUID: AsyncStream<IncomingMessage>.Continuation] = [:]

    private init() {}

    func start() {
        guard manager == nil else { return }
        let mgr = TDLibClientManager()
        self.manager = mgr
        self.client = mgr.createClient { [weak self] data, client in
            self?.dispatchUpdate(data: data, client: client)
        }
        logger.info("TDLib started")
    }

    func stop() {
        try? client?.close(completion: { _ in })
        for c in messageContinuations.values { c.finish() }
        messageContinuations.removeAll()
        manager = nil
        client = nil
    }

    // MARK: - Wizard step handlers

    func submitApiCredentials(apiId: Int32, apiHash: String) {
        SettingsStore.apiId = apiId
        SettingsStore.apiHash = apiHash
        authStep = .launching
        sendTdlibParameters()
    }

    func submitPhoneNumber(_ phone: String) async {
        guard let client else { return }
        do {
            _ = try await client.setAuthenticationPhoneNumber(
                phoneNumber: phone,
                settings: nil
            )
        } catch {
            setError(error)
        }
    }

    func submitAuthCode(_ code: String) async {
        guard let client else { return }
        do {
            _ = try await client.checkAuthenticationCode(code: code)
        } catch {
            setError(error)
        }
    }

    func submitPassword(_ password: String) async {
        guard let client else { return }
        do {
            _ = try await client.checkAuthenticationPassword(password: password)
        } catch {
            setError(error)
        }
    }

    func resolveBot(username: String) async -> Chat? {
        guard let client else { return nil }
        let cleaned = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        do {
            let chat = try await client.searchPublicChat(username: cleaned)
            return chat
        } catch {
            setError(error)
            return nil
        }
    }

    func confirmBot(chat: Chat, username: String) {
        let userId: Int64
        switch chat.type {
        case .chatTypePrivate(let p):
            userId = p.userId
        default:
            userId = 0
        }
        SettingsStore.hermesBotChatId = chat.id
        SettingsStore.hermesBotUserId = userId
        SettingsStore.hermesBotUsername = username
        hermesBotChatId = chat.id
        hermesBotUserId = userId
        hermesBotTitle = chat.title.isEmpty ? username : chat.title
        advanceFromBotSelection()
    }

    func resetAuth() {
        stop()
        SettingsStore.resetAll()
        hermesBotChatId = 0
        hermesBotUserId = 0
        hermesBotTitle = nil
        let fm = FileManager.default
        try? fm.removeItem(at: SettingsStore.tdlibDatabaseDirectory)
        try? fm.removeItem(at: SettingsStore.tdlibFilesDirectory)
        authStep = .needApiCreds
        start()
    }

    // MARK: - Phase 3: send + observe

    /// Send a plain-text message to the configured Hermes bot DM.
    @discardableResult
    func sendPrompt(_ text: String) async throws -> Int64 {
        guard let client else { throw ClientError.notReady }
        guard hermesBotChatId != 0 else { throw ClientError.botNotSelected }

        let content = InputMessageContent.inputMessageText(
            InputMessageText(
                clearDraft: true,
                linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: text)
            )
        )
        do {
            let msg = try await client.sendMessage(
                chatId: hermesBotChatId,
                inputMessageContent: content,
                options: nil,
                replyMarkup: nil,
                replyTo: nil,
                topicId: nil
            )
            logger.info("Sent prompt to chatId=\(self.hermesBotChatId), localMessageId=\(msg.id)")
            return msg.id
        } catch {
            let desc = String(describing: error)
            logger.error("sendMessage failed: \(desc, privacy: .public)")
            throw ClientError.sendFailed(desc)
        }
    }

    /// Stream of every incoming Telegram message. Caller filters by chat_id.
    func incomingMessages() -> AsyncStream<IncomingMessage> {
        AsyncStream { continuation in
            let id = UUID()
            let cont = continuation
            Task { @MainActor [weak self] in
                self?.messageContinuations[id] = cont
            }
            cont.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.messageContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    /// Wait for the next incoming DM from the Hermes bot whose text contains `key`
    /// AND doesn't look like a tool call. Returns nil on timeout.
    func awaitHermesReply(containingKey key: String, timeout: TimeInterval = 120) async -> HermesReply? {
        let hermesChatId = hermesBotChatId
        guard hermesChatId != 0 else { return nil }

        return await withTaskGroup(of: HermesReply?.self) { group in
            group.addTask { [weak self] in
                guard let self else { return nil }
                let stream = await self.incomingMessages()
                for await msg in stream {
                    guard msg.chatId == hermesChatId else { continue }
                    guard msg.text.localizedCaseInsensitiveContains(key) else { continue }
                    if TelegramClient.looksLikeToolCall(msg.text) {
                        continue
                    }
                    return HermesReply(plain: msg.text, attributed: msg.attributed)
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Heuristic: Hermes agent tool calls come through the DM as strict-format lines
    /// like `clarify: "h4gcya" — I need your location to get …` — a lowercase identifier,
    /// a colon, an optionally-quoted argument, then an em- or en-dash before a description.
    /// User-visible replies don't follow that pattern.
    nonisolated static func looksLikeToolCall(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[a-z][a-z0-9_]*:\s+["']?[^"'\n]+["']?\s*[—–\-]\s+"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Internals

    private func dispatchUpdate(data: Data, client: TDLibClient) {
        do {
            let update = try client.decoder.decode(Update.self, from: data)
            Task { @MainActor [weak self] in
                self?.process(update: update)
            }
        } catch {
            logger.error("Decode update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func process(update: Update) {
        switch update {
        case .updateAuthorizationState(let payload):
            handleAuthState(payload.authorizationState)
        case .updateNewMessage(let payload):
            handleNewMessage(payload.message)
        default:
            break
        }
    }

    private func handleNewMessage(_ message: Message) {
        // Skip outgoing (our own) messages — we care about replies from the bot.
        if message.isOutgoing { return }

        guard let extracted = Self.extractFormattedText(from: message) else { return }

        var senderUserId: Int64 = 0
        switch message.senderId {
        case .messageSenderUser(let u): senderUserId = u.userId
        default: break
        }

        let incoming = IncomingMessage(
            id: message.id,
            chatId: message.chatId,
            senderUserId: senderUserId,
            text: extracted.plain,
            attributed: extracted.attributed,
            receivedAt: Foundation.Date()
        )

        if message.chatId == hermesBotChatId {
            logger.info("New Hermes message (chatId=\(message.chatId), messageId=\(message.id), \(extracted.plain.count) chars)")
        }

        for c in messageContinuations.values {
            c.yield(incoming)
        }
    }

    private static func extractFormattedText(from message: Message) -> (plain: String, attributed: AttributedString)? {
        switch message.content {
        case .messageText(let t):
            return (t.text.text, attributed(from: t.text))
        default:
            return nil
        }
    }

    /// Convert a TDLib `FormattedText` (plain string + UTF-16-indexed entity ranges)
    /// into an `AttributedString` for SwiftUI `Text`. Unknown entity types are left
    /// unstyled so the raw substring still appears.
    private static func attributed(from ft: FormattedText) -> AttributedString {
        var attr = AttributedString(ft.text)
        let plain = ft.text
        let utf16 = plain.utf16

        for entity in ft.entities {
            guard
                let startU16 = utf16.index(utf16.startIndex, offsetBy: entity.offset, limitedBy: utf16.endIndex),
                let endU16 = utf16.index(startU16, offsetBy: entity.length, limitedBy: utf16.endIndex),
                let startStr = String.Index(startU16, within: plain),
                let endStr = String.Index(endU16, within: plain),
                let aStart = AttributedString.Index(startStr, within: attr),
                let aEnd = AttributedString.Index(endStr, within: attr)
            else { continue }
            let attrRange = aStart..<aEnd

            switch entity.type {
            case .textEntityTypeBold:
                attr[attrRange].inlinePresentationIntent = .stronglyEmphasized
            case .textEntityTypeItalic:
                attr[attrRange].inlinePresentationIntent = .emphasized
            case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
                attr[attrRange].inlinePresentationIntent = .code
            case .textEntityTypeStrikethrough:
                attr[attrRange].strikethroughStyle = .single
            case .textEntityTypeUnderline:
                attr[attrRange].underlineStyle = .single
            case .textEntityTypeTextUrl(let u):
                if let url = URL(string: u.url) {
                    attr[attrRange].link = url
                }
            case .textEntityTypeUrl:
                if let url = URL(string: String(plain[startStr..<endStr])) {
                    attr[attrRange].link = url
                }
            default:
                break
            }
        }
        return attr
    }

    private func handleAuthState(_ state: AuthorizationState) {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            sendTdlibParameters()

        case .authorizationStateWaitPhoneNumber:
            authStep = .needPhoneNumber

        case .authorizationStateWaitCode:
            authStep = .needAuthCode

        case .authorizationStateWaitPassword(let p):
            passwordHint = p.passwordHint.isEmpty ? nil : p.passwordHint
            authStep = .needPassword(hint: passwordHint)

        case .authorizationStateReady:
            advanceFromAuthReady()

        case .authorizationStateClosed, .authorizationStateClosing, .authorizationStateLoggingOut:
            authStep = .launching

        case .authorizationStateWaitEmailAddress,
             .authorizationStateWaitEmailCode,
             .authorizationStateWaitRegistration,
             .authorizationStateWaitOtherDeviceConfirmation,
             .authorizationStateWaitPremiumPurchase:
            authStep = .error("Telegram requested a state Tabby doesn't yet support: \(state). Complete it in Telegram Desktop, then restart Tabby.")

        @unknown default:
            authStep = .error("Unknown Telegram authorization state.")
        }
    }

    private func sendTdlibParameters() {
        guard let client else { return }
        guard let apiId = SettingsStore.apiId, let apiHashString = SettingsStore.apiHash else {
            authStep = .needApiCreds
            return
        }
        let dbDir = SettingsStore.tdlibDatabaseDirectory.path
        let filesDir = SettingsStore.tdlibFilesDirectory.path
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        Task {
            do {
                _ = try await client.setTdlibParameters(
                    apiHash: apiHashString,
                    apiId: Int(apiId),
                    applicationVersion: "0.1.0",
                    databaseDirectory: dbDir,
                    databaseEncryptionKey: Data(),
                    deviceModel: "MacBook",
                    filesDirectory: filesDir,
                    systemLanguageCode: lang,
                    systemVersion: systemVersion,
                    useChatInfoDatabase: true,
                    useFileDatabase: true,
                    useMessageDatabase: true,
                    useSecretChats: false,
                    useTestDc: false
                )
            } catch {
                setError(error)
            }
        }
    }

    private func advanceFromAuthReady() {
        if SettingsStore.hermesBotChatId != 0 {
            hermesBotChatId = SettingsStore.hermesBotChatId
            hermesBotUserId = SettingsStore.hermesBotUserId
            hermesBotTitle = SettingsStore.hermesBotUsername
            authStep = .authenticated
        } else {
            authStep = .needBotSelection
        }
    }

    private func advanceFromBotSelection() {
        authStep = .authenticated
    }

    private func setError(_ error: Swift.Error) {
        let message = String(describing: error)
        lastError = message
        logger.error("TDLib error: \(message, privacy: .public)")
        if message.contains("API_ID_INVALID") || message.contains("API_HASH_INVALID") {
            resetAuth()
        }
    }
}
