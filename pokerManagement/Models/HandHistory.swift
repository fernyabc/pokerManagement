import Foundation
import SwiftData

@Model
final class HandHistory {
    var timestamp: Date
    var holeCards: [String]
    var communityCards: [String]
    var action: String
    var potSize: Double
    var reasoning: String?

    init(timestamp: Date = .now, holeCards: [String], communityCards: [String],
         action: String, potSize: Double, reasoning: String? = nil) {
        self.timestamp = timestamp
        self.holeCards = holeCards
        self.communityCards = communityCards
        self.action = action
        self.potSize = potSize
        self.reasoning = reasoning
    }
}
