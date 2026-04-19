import SwiftUI

struct IdleExpandedView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tabby")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Ready")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 240)
    }
}

#Preview {
    IdleExpandedView()
        .background(.black)
}
