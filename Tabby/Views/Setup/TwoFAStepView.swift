import SwiftUI

struct TwoFAStepView: View {
    @ObservedObject private var telegram = TelegramClient.shared
    let hint: String?

    @State private var password: String = ""
    @State private var submitting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("2-step verification")
                .font(.title3.weight(.semibold))

            Text("Your account is protected by a 2-step verification password. Enter it to finish signing in.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let hint, !hint.isEmpty {
                Text("Hint: \(hint)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }

            HStack {
                Text("Password")
                    .frame(width: 70, alignment: .leading)
                    .foregroundStyle(.secondary)
                SecureField("••••••••", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                if submitting {
                    ProgressView().scaleEffect(0.7).padding(.trailing, 6)
                }
                Button("Verify") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || submitting)
            }
        }
    }

    private func submit() {
        submitting = true
        Task {
            await telegram.submitPassword(password)
            submitting = false
        }
    }
}
