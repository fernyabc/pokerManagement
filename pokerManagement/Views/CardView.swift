import SwiftUI

struct CardView: View {
    let card: String
    
    var color: Color {
        let suit = card.last
        if suit == "h" || suit == "d" { return .red }
        return .black
    }
    
    var suitSymbol: String {
        switch card.last {
        case "s": return "♠"
        case "h": return "♥"
        case "d": return "♦"
        case "c": return "♣"
        default: return ""
        }
    }
    
    var rank: String {
        guard !card.isEmpty else { return "" }
        return String(card.dropLast())
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            VStack(spacing: 0) {
                Text(rank.uppercased())
                    .font(.system(size: 16, weight: .bold))
                Text(suitSymbol)
                    .font(.system(size: 14))
            }
            .foregroundColor(color)
        }
        .frame(width: 44, height: 60)
    }
}

#Preview {
    HStack {
        CardView(card: "As")
        CardView(card: "Th")
        CardView(card: "7d")
        CardView(card: "2c")
    }
    .padding()
    .background(Color.green.opacity(0.3))
}
