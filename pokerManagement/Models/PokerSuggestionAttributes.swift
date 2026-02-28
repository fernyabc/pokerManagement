import Foundation
import ActivityKit

public struct PokerSuggestionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var action: String
        public var raiseSize: Double?
        public var ev: Double?
        public var reasoning: String?
        public var timestamp: Date
        
        public init(action: String, raiseSize: Double? = nil, ev: Double? = nil, reasoning: String? = nil, timestamp: Date = Date()) {
            self.action = action
            self.raiseSize = raiseSize
            self.ev = ev
            self.reasoning = reasoning
            self.timestamp = timestamp
        }
    }
    
    public var tableName: String
    
    public init(tableName: String) {
        self.tableName = tableName
    }
}
