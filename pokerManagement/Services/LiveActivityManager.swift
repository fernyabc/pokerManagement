import Foundation
import ActivityKit

class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published var currentActivity: Activity<PokerSuggestionAttributes>?

    func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attrs = PokerSuggestionAttributes(tableName: "Table 1")
        let state = PokerSuggestionAttributes.ContentState(
            action: "Waiting...", reasoning: "Waiting for next hand", isSolving: false
        )

        do {
            let activity = try Activity.request(attributes: attrs, contentState: state, pushType: nil)
            DispatchQueue.main.async { self.currentActivity = activity }
        } catch {
            print("Live Activity error: \(error)")
        }
    }

    func updateActivity(suggestion: GTOSuggestion) {
        guard let activity = currentActivity else { return }
        let state = PokerSuggestionAttributes.ContentState(
            action: suggestion.action, raiseSize: suggestion.raiseSize,
            ev: suggestion.ev, reasoning: suggestion.reasoning ?? "",
            foldWeight: suggestion.foldWeight, callWeight: suggestion.callWeight,
            raiseWeight: suggestion.raiseWeight, isSolving: suggestion.isSolving ?? false
        )
        Task { await activity.update(using: state) }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(using: activity.content.state, dismissalPolicy: .immediate)
            DispatchQueue.main.async { self.currentActivity = nil }
        }
    }
}
