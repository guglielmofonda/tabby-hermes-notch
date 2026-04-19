import SwiftUI

struct AuthCodeStepView: View {
    @ObservedObject private var telegram = TelegramClient.shared

    @State private var code: String = ""
    @State private var submitting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enter the authentication code")
                .font(.title3.weight(.semibold))

            Text("Telegram sent you a 5-digit code. If you already have Telegram Desktop or Telegram mobile installed, the code arrives there as an in-app message. Otherwise it arrives as an SMS.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Code")
                    .frame(width: 70, alignment: .leading)
                    .foregroundStyle(.secondary)
                TextField("12345", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .monospaced()
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                if submitting {
                    ProgressView().scaleEffect(0.7).padding(.trailing, 6)
                }
                Button("Verify") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || submitting)
            }
        }
    }

    private var isValid: Bool {
        let cleaned = code.trimmingCharacters(in: .whitespaces)
        return cleaned.count >= 4 && cleaned.allSatisfy(\.isNumber)
    }

    private func submit() {
        submitting = true
        Task {
            await telegram.submitAuthCode(code.trimmingCharacters(in: .whitespaces))
            submitting = false
        }
    }
}
