import Foundation
import AVFoundation

/// Handles Text-To-Speech (TTS) for discrete audio feedback via Meta glasses
class FeedbackService: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    
    // Configures the speech rate and pitch for discretion
    func speakSuggestion(_ suggestion: GTOSuggestion) {
        var text = suggestion.action
        
        if suggestion.action == "Raise", let size = suggestion.raiseSize {
            text += " to \(Int(size))"
        }
        
        // Add confidence if available to help the user gauge the action
        if let conf = suggestion.confidence {
            text += ". \(Int(conf * 100)) percent frequency."
        }
        
        print("🗣️ [TTS Triggered]: \(text)")
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9 // slightly slower
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.5 // Keep it low for privacy in glasses
        
        // Since iOS manages audio routing automatically,
        // if Ray-Ban Meta is paired via Bluetooth, it will play through them.
        synthesizer.speak(utterance)
    }
}
