import Foundation
import SwiftData

@Model
final class HandHistory {
    var id: UUID
    var timestamp: Date
    var holeCards: [String]
    var communityCards: [String]
    var numPlayers: Int
    var myPosition: Int
    var potSize: Double
    var recommendedAction: String
    var recommendedRaiseSize: Double?
    var ev: Double?
    
    init(holeCards: [String],
         communityCards: [String],
         numPlayers: Int,
         myPosition: Int,
         potSize: Double,
         recommendedAction: String,
         recommendedRaiseSize: Double? = nil,
         ev: Double? = nil) {
        
        self.id = UUID()
        self.timestamp = Date()
        self.holeCards = holeCards
        self.communityCards = communityCards
        self.numPlayers = numPlayers
        self.myPosition = myPosition
        self.potSize = potSize
        self.recommendedAction = recommendedAction
        self.recommendedRaiseSize = recommendedRaiseSize
        self.ev = ev
    }
}
