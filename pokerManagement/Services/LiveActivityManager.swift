import Foundation
import ActivityKit

class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    
    @Published var currentActivity: Activity<PokerSuggestionAttributes>?
    
    func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities not enabled by user")
            return
        }
        
        let attributes = PokerSuggestionAttributes(tableName: "Table 1")
        let initialState = PokerSuggestionAttributes.ContentState(
            action: "Waiting...",
            raiseSize: nil,
            ev: nil,
            reasoning: "Waiting for next hand state",
            timestamp: Date()
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                contentState: initialState,
                pushType: nil
            )
            DispatchQueue.main.async {
                self.currentActivity = activity
            }
            print("Live Activity started with ID: \(activity.id)")
        } catch {
            print("Error starting Live Activity: \(error.localizedDescription)")
        }
    }
    
    func updateActivity(action: String, raiseSize: Double?, ev: Double?, reasoning: String?) {
        guard let activity = currentActivity else { return }
        
        let updatedState = PokerSuggestionAttributes.ContentState(
            action: action,
            raiseSize: raiseSize,
            ev: ev,
            reasoning: reasoning,
            timestamp: Date()
        )
        
        Task {
            await activity.update(using: updatedState)
            print("Live Activity updated: \(action)")
        }
    }
    
    func endActivity() {
        guard let activity = currentActivity else { return }
        let finalState = activity.content.state
        
        Task {
            await activity.end(using: finalState, dismissalPolicy: .immediate)
            DispatchQueue.main.async {
                self.currentActivity = nil
            }
            print("Live Activity ended")
        }
    }
}
