import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \HandHistory.timestamp, order: .reverse) private var hands: [HandHistory]

    var body: some View {
        NavigationStack {
            List(hands) { hand in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(hand.action).font(.headline)
                        Spacer()
                        Text("Pot: $\(hand.potSize, specifier: "%.0f")")
                            .font(.caption)
                    }
                    HStack {
                        Text("Hole: \(hand.holeCards.joined(separator: " "))")
                        Text("Board: \(hand.communityCards.joined(separator: " "))")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if let reasoning = hand.reasoning {
                        Text(reasoning)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Text(hand.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .navigationTitle("Hand History")
            .overlay {
                if hands.isEmpty {
                    ContentUnavailableView("No Hands", systemImage: "suit.spade",
                                           description: Text("Hands will appear here after detection."))
                }
            }
        }
    }
}
