import SwiftUI

struct PhoneLoginStepView: View {
    @ObservedObject private var telegram = TelegramClient.shared

    @State private var phone: String = ""
    @State private var submitting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in to Telegram")
                .font(.title3.weight(.semibold))

            Text("Tabby sends messages as you — so it needs to log in to your Telegram account. Enter your phone number in international format (e.g. +14155551234). Telegram will send you a one-time code.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Phone")
                    .frame(width: 70, alignment: .leading)
                    .foregroundStyle(.secondary)
                TextField("+14155551234", text: $phone)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                if submitting {
                    ProgressView().scaleEffect(0.7).padding(.trailing, 6)
                }
                Button("Send code") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || submitting)
            }
        }
    }

    private var isValid: Bool {
        phone.trimmingCharacters(in: .whitespaces).hasPrefix("+")
            && phone.trimmingCharacters(in: .whitespaces).count >= 8
    }

    private func submit() {
        submitting = true
        Task {
            await telegram.submitPhoneNumber(phone.trimmingCharacters(in: .whitespaces))
            submitting = false
        }
    }
}
