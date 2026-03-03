import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \HandHistory.timestamp, order: .reverse) private var hands: [HandHistory]
    @State private var showShareSheet = false
    @State private var shareURL: URL?

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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        shareURL = exportToCSV()
                        if shareURL != nil { showShareSheet = true }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(hands.isEmpty)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ActivityView(activityItems: [url])
                }
            }
            .overlay {
                if hands.isEmpty {
                    ContentUnavailableView("No Hands", systemImage: "suit.spade",
                                           description: Text("Hands will appear here after detection."))
                }
            }
        }
    }

    private func exportToCSV() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = ["Timestamp,Hole Cards,Community Cards,Action,Pot Size,Reasoning"]
        for hand in hands {
            func quoted(_ s: String) -> String {
                "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            let timestamp = quoted(formatter.string(from: hand.timestamp))
            let hole = quoted(hand.holeCards.joined(separator: " "))
            let community = quoted(hand.communityCards.joined(separator: " "))
            let action = quoted(hand.action)
            let pot = "\(hand.potSize)"
            let reasoning = quoted(hand.reasoning ?? "")
            lines.append("\(timestamp),\(hole),\(community),\(action),\(pot),\(reasoning)")
        }

        let csvString = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hand_history.csv")
        do {
            try csvString.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
