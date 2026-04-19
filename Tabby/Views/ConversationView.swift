import SwiftUI

struct ConversationView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(state.conversation) { turn in
                            ConversationBubble(turn: turn)
                                .id(turn.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: state.conversation.count) { _, _ in
                    guard let last = state.conversation.last else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = state.conversation.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .frame(minHeight: 80, maxHeight: 260)

            Divider().background(.white.opacity(0.12))

            footer
        }
        .frame(minWidth: 420, maxWidth: 520)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                state.recordFollowUp()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                    Text("Ask more")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Record a follow-up to continue the thread")

            Spacer()

            Button {
                state.dismissConversation()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Close conversation")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct ConversationBubble: View {
    let turn: AppState.ConversationTurn
    @ObservedObject private var state = AppState.shared

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if turn.role == .user {
                Spacer(minLength: 36)
            }
            bubble
            if turn.role == .hermes {
                Spacer(minLength: 36)
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(turn.role == .hermes ? state.botDisplayName : "You")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(turn.text)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(turn.role == .hermes
                    ? Color.white.opacity(0.12)
                    : Color.accentColor.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
