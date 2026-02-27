import SwiftUI

struct PokerTableView: View {
    let state: DetectedPokerState
    
    var body: some View {
        VStack(spacing: 16) {
            // Community Cards (Board)
            VStack {
                Text("Board")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                HStack(spacing: 8) {
                    if state.communityCards.isEmpty {
                        Text("Pre-Flop")
                            .foregroundColor(.gray)
                            .italic()
                    } else {
                        ForEach(state.communityCards, id: \.self) { card in
                            CardView(card: card)
                        }
                    }
                }
                .frame(height: 60)
            }
            .padding(.horizontal)
            
            Divider()
            
            // Hole Cards
            VStack {
                Text("My Hand")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                HStack(spacing: 8) {
                    if state.holeCards.isEmpty {
                        Text("Looking for cards...")
                            .foregroundColor(.gray)
                            .italic()
                    } else {
                        ForEach(state.holeCards, id: \.self) { card in
                            CardView(card: card)
                        }
                    }
                }
                .frame(height: 60)
            }
            
            // Meta Info
            HStack(spacing: 24) {
                VStack {
                    Text("Players")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(state.numPlayers)")
                        .font(.headline)
                }
                
                VStack {
                    Text("Position")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("P\(state.myPosition)")
                        .font(.headline)
                }
                
                VStack {
                    Text("Pot")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "$%.1f", state.potSize))
                        .font(.headline)
                        .foregroundColor(.green)
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
}
