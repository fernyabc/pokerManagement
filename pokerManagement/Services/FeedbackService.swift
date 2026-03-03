import Foundation

/// Silent feedback service — TTS removed per architecture (no audio output).
class FeedbackService: ObservableObject {
    func handleSuggestion(_ suggestion: GTOSuggestion) {
        let weights: String
        if let f = suggestion.foldWeight, let c = suggestion.callWeight, let r = suggestion.raiseWeight {
            weights = "F:\(Int(f * 100))% C:\(Int(c * 100))% R:\(Int(r * 100))%"
        } else {
            weights = "no weights"
        }
        print("[Silent] \(suggestion.action) (\(weights))")
    }
}
