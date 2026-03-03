import SwiftUI

struct PokerTableView: View {
    let state: DetectedPokerState

    var body: some View {
        VStack(spacing: 12) {
            // Community cards
            HStack(spacing: 8) {
                if state.communityCards.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        cardPlaceholder
                    }
                } else {
                    ForEach(state.communityCards, id: \.self) { card in
                        cardView(card)
                    }
                }
            }

            // Hole cards
            HStack(spacing: 8) {
                if state.holeCards.isEmpty {
                    cardPlaceholder
                    cardPlaceholder
                } else {
                    ForEach(state.holeCards, id: \.self) { card in
                        cardView(card)
                    }
                }
            }

            // Info row
            HStack {
                Text("Players: \(state.numPlayers)")
                Spacer()
                Text("Pot: $\(state.potSize, specifier: "%.1f")")
                Spacer()
                Text("Pos: \(state.myPosition)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func cardView(_ card: String) -> some View {
        Text(card)
            .font(.system(.body, design: .monospaced))
            .bold()
            .frame(width: 44, height: 60)
            .background(.white, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray, lineWidth: 1))
    }

    private var cardPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.blue.opacity(0.3))
            .frame(width: 44, height: 60)
            .overlay(Text("?").foregroundColor(.white))
    }
}
