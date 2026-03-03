import ActivityKit
import Foundation

struct PokerSuggestionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var action: String
        var raiseSize: Double?
        var ev: Double?
        var reasoning: String
        var foldWeight: Double?
        var callWeight: Double?
        var raiseWeight: Double?
        var isSolving: Bool
    }

    var tableName: String
}
