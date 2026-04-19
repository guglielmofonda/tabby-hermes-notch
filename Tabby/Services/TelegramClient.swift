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

    private var manager: TDLibClientManager?
    private var client: TDLibClient?
    private let logger = Logger(subsystem: "com.guglielmofonda.Tabby", category: "Telegram")

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
        default:
            break
        }
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
            // Less common states; prompt user to handle via normal Telegram first then re-run.
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
            // Credentials are bad. Clear and restart from step 1 with a fresh TDLib DB.
            resetAuth()
        }
    }
}
