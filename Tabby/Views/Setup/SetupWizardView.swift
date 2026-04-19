import SwiftUI

struct SetupWizardView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var telegram = TelegramClient.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 520, height: 440)
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tabby Setup")
                    .font(.headline)
                Text(stepSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let err = telegram.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
            Menu {
                Button("Start over (clear credentials + session)", role: .destructive) {
                    telegram.resetAuth()
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var stepSubtitle: String {
        switch telegram.authStep {
        case .launching: return "Starting TDLib…"
        case .needApiCreds: return "Step 1 of 3 — Telegram API credentials"
        case .needPhoneNumber: return "Step 2 of 3 — Telegram login"
        case .needAuthCode: return "Step 2 of 3 — Verify authentication code"
        case .needPassword: return "Step 2 of 3 — 2-step verification"
        case .needBotSelection: return "Step 3 of 3 — Connect your Hermes bot"
        case .authenticated: return "Ready"
        case .error: return "Something went wrong"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch telegram.authStep {
        case .launching:
            VStack(spacing: 12) {
                ProgressView()
                Text("Starting Telegram…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .needApiCreds:
            APICredsStepView()

        case .needPhoneNumber:
            PhoneLoginStepView()

        case .needAuthCode:
            AuthCodeStepView()

        case .needPassword(let hint):
            TwoFAStepView(hint: hint)

        case .needBotSelection:
            PickBotStepView()

        case .authenticated:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("You're set up!")
                    .font(.title3.weight(.semibold))
                Text("Tabby is listening at the notch. Tap it to start dictating.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Reset and try again") {
                    telegram.resetAuth()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
