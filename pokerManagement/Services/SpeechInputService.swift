import Foundation
import Speech
import AVFoundation
import RegexBuilder

/// On-device voice input for pot/bet sizes via SFSpeechRecognizer (iOS 17+).
class SpeechInputService: ObservableObject {
    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var parsedPotSize: Double?
    @Published var parsedBetSize: Double?
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { self?.authorizationStatus = status }
        }
    }

    func startListening() {
        guard authorizationStatus == .authorized, !isListening else { return }
        parsedPotSize = nil; parsedBetSize = nil; transcribedText = ""

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        self.request = req

        let node = audioEngine.inputNode
        node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buf, _ in
            req.append(buf)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            audioEngine.prepare()
            try audioEngine.start()
        } catch { print("[Speech] audio error: \(error)"); return }

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcribedText = text
                    self.parseAmounts(from: text)
                }
                if result.isFinal { self.stopListening() }
            }
            if error != nil { self.stopListening() }
        }

        DispatchQueue.main.async { self.isListening = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.stopListening() }
    }

    func stopListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.cancel()
        request = nil; task = nil
        DispatchQueue.main.async { self.isListening = false }
    }

    // MARK: - Parsing

    private static let words: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "hundred": 100, "thousand": 1000
    ]

    private func parseAmounts(from text: String) {
        let low = text.lowercased()
        if let v = extract(after: ["the pot is", "pot is", "pot's", "pot"], in: low) { parsedPotSize = v }
        if let v = extract(after: ["facing a bet of", "bet is", "bet of", "facing", "bet"], in: low) { parsedBetSize = v }
    }

    private func extract(after prefixes: [String], in text: String) -> Double? {
        for p in prefixes {
            guard let r = text.range(of: p) else { continue }
            let after = String(text[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            let digits = Regex { Capture { OneOrMore(.digit) } }
            if let m = after.prefixMatch(of: digits), let v = Double(m.1) { return v }
            if let v = parseWords(after) { return v }
        }
        return nil
    }

    private func parseWords(_ text: String) -> Double? {
        var total = 0.0, cur = 0.0, found = false
        for w in text.split(separator: " ").map({ String($0).lowercased() }) {
            guard let v = Self.words[w] else { if found { break } else { continue } }
            found = true
            if v == 100 { cur = (cur == 0 ? 1 : cur) * 100 }
            else if v == 1000 { cur = (cur == 0 ? 1 : cur) * 1000; total += cur; cur = 0 }
            else { cur += v }
        }
        total += cur
        return found ? total : nil
    }
}
