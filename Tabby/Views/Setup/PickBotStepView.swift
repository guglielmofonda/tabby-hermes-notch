import SwiftUI
import TDLibKit

struct PickBotStepView: View {
    @ObservedObject private var telegram = TelegramClient.shared

    @State private var username: String = ""
    @State private var resolving: Bool = false
    @State private var resolved: Chat?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your Hermes bot")
                .font(.title3.weight(.semibold))

            Text("Enter the username of your Hermes Telegram bot — this is the one that listens for your messages on your Mac Mini. Tabby will DM it directly from your account.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("@")
                    .foregroundStyle(.secondary)
                TextField("my_hermes_bot", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: username) { _, _ in
                        // Editing after a successful lookup must invalidate the cached
                        // chat; otherwise Finish would save the old chat_id under the
                        // new username (chat for `botA`, label `botB`).
                        if resolved != nil { resolved = nil }
                        errorText = nil
                    }
                Button("Look up") { lookup() }
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || resolving)
            }

            if resolving {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Resolving @\(username)…")
                        .foregroundStyle(.secondary)
                }
            }

            if let chat = resolved {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text(chat.title.isEmpty ? username : chat.title)
                            .font(.headline)
                    }
                    Text("chat_id: \(chat.id)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Finish") { finish() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(resolved == nil)
            }
        }
    }

    private func lookup() {
        resolving = true
        errorText = nil
        resolved = nil
        let clean = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        Task {
            if let chat = await telegram.resolveBot(username: clean) {
                resolved = chat
            } else {
                errorText = telegram.lastError ?? "Couldn't find @\(clean)"
            }
            resolving = false
        }
    }

    private func finish() {
        guard let chat = resolved else { return }
        let clean = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        telegram.confirmBot(chat: chat, username: clean)
    }
}
