import SwiftUI

struct APICredsStepView: View {
    @ObservedObject private var telegram = TelegramClient.shared

    @State private var apiIdString: String = ""
    @State private var apiHash: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generate Telegram API credentials")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                instructionRow(1) {
                    Text("Open ") + Text("[my.telegram.org](https://my.telegram.org)").underline() + Text(" in your browser and sign in with your phone number.")
                }
                instructionRow(2) {
                    Text("Click ") + Text("API development tools").bold() + Text(".")
                }
                instructionRow(3) {
                    Text("Create a new application — any title and short name works (e.g. ") + Text("Tabby").bold() + Text(").")
                }
                instructionRow(4) {
                    Text("Copy the ") + Text("App api_id").bold() + Text(" and ") + Text("App api_hash").bold() + Text(" and paste them below.")
                }
                Text("These are stored only on this Mac, in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
            }

            Divider().padding(.vertical, 2)

            HStack {
                Text("api_id")
                    .frame(width: 70, alignment: .leading)
                    .foregroundStyle(.secondary)
                TextField("12345678", text: $apiIdString)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("api_hash")
                    .frame(width: 70, alignment: .leading)
                    .foregroundStyle(.secondary)
                TextField("abcdef1234567890abcdef1234567890", text: $apiHash)
                    .textFieldStyle(.roundedBorder)
                    .monospaced()
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Continue") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
    }

    private var isValid: Bool {
        Int32(apiIdString.trimmingCharacters(in: .whitespaces)) != nil
            && apiHash.trimmingCharacters(in: .whitespaces).count >= 16
    }

    private func submit() {
        guard let apiId = Int32(apiIdString.trimmingCharacters(in: .whitespaces)) else { return }
        telegram.submitApiCredentials(
            apiId: apiId,
            apiHash: apiHash.trimmingCharacters(in: .whitespaces)
        )
    }

    @ViewBuilder
    private func instructionRow(_ n: Int, @ViewBuilder content: () -> Text) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n).")
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            content()
                .font(.system(size: 13))
        }
    }
}
