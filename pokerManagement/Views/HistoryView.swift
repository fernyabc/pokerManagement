import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HandHistory.timestamp, order: .reverse) private var handHistories: [HandHistory]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(handHistories) { hand in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(hand.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(hand.recommendedAction)
                                .font(.subheadline)
                                .bold()
                                .foregroundColor(hand.recommendedAction == "Raise" ? .red : .blue)
                        }
                        
                        HStack {
                            Text("Hand: \(hand.holeCards.joined(separator: ", "))")
                                .font(.headline)
                            Spacer()
                            Text("Pot: $\(String(format: "%.1f", hand.potSize))")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }
                        
                        if !hand.communityCards.isEmpty {
                            Text("Board: \(hand.communityCards.joined(separator: ", "))")
                                .font(.subheadline)
                        }
                        
                        HStack {
                            Text("Players: \(hand.numPlayers) | Pos: P\(hand.myPosition)")
                            Spacer()
                            if let ev = hand.ev {
                                Text("EV: \(String(format: "%.2f", ev))")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteHands)
            }
            .navigationTitle("Session History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .overlay {
                if handHistories.isEmpty {
                    ContentUnavailableView(
                        "No Hand History",
                        systemImage: "clock.badge.xmark",
                        description: Text("Saved hands and GTO suggestions will appear here.")
                    )
                }
            }
        }
    }
    
    private func deleteHands(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(handHistories[index])
            }
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: HandHistory.self, inMemory: true)
}
