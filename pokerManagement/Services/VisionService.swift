import Foundation
import Vision
import CoreImage
import CoreMedia

/// Represents the visual state detected from the camera stream
struct DetectedPokerState: Codable {
    var holeCards: [String] = []
    var communityCards: [String] = []
    var numPlayers: Int = 0
    var dealerPosition: Int = 0
    var myPosition: Int = 0
    var activeAction: String? = nil
    var potSize: Double = 0.0
}

/// The Vision Pipeline based on Apple Vision Framework.
/// Includes a state lock engine that requires 0.5s of stable card detection
/// before publishing a locked state to downstream consumers.
class VisionService: ObservableObject {
    @Published var currentState = DetectedPokerState()
    @Published var isProcessing = false
    @Published var isStateLocked = false

    private var sequenceHandler = VNSequenceRequestHandler()
    private let cardDetectionService = CardDetectionService()

    // MARK: - State Lock Engine

    /// How long (seconds) the detected cards must remain stable before locking.
    private let lockStabilityDuration: TimeInterval = 0.5

    /// The candidate state being tracked for stability.
    private var candidateHoleCards: [String] = []
    private var candidateCommunityCards: [String] = []

    /// Timestamp when the current candidate first appeared.
    private var candidateFirstSeen: Date?

    init() {
        setupVisionModels()
    }

    private func setupVisionModels() {
        // CardDetectionService handles the CoreML model loading
    }

    /// Called when a frame is received from any VideoInputSource.
    func processFrame(_ buffer: CMSampleBuffer) {
        guard !isProcessing else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }

        DispatchQueue.main.async { self.isProcessing = true }

        if cardDetectionService.modelLoaded {
            cardDetectionService.detectCards(in: pixelBuffer) { [weak self] results, error in
                defer {
                    DispatchQueue.main.async { self?.isProcessing = false }
                }
                guard let results = results else { return }

                var newHoleCards: [String] = []
                var newCommunityCards: [String] = []

                for observation in results {
                    guard let topLabel = observation.labels.first?.identifier else { continue }
                    if observation.boundingBox.origin.y < 0.3 {
                        newHoleCards.append(topLabel)
                    } else {
                        newCommunityCards.append(topLabel)
                    }
                }

                self?.evaluateStateLock(hole: newHoleCards.sorted(), community: newCommunityCards.sorted())
            }
            return
        }

        // Fallback: Text Recognition (mock state for development)
        var requests: [VNRequest] = []
        let textRequest = VNRecognizeTextRequest { [weak self] request, error in
            self?.handleTextResults(request: request, error: error)
        }
        textRequest.recognitionLevel = .accurate
        requests.append(textRequest)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer {
                DispatchQueue.main.async { self?.isProcessing = false }
            }
            do {
                try self?.sequenceHandler.perform(requests, on: pixelBuffer, orientation: .up)
            } catch {
                print("Failed to perform Vision request: \(error.localizedDescription)")
            }
        }
    }

    /// Resets the state lock so the engine can detect a new board.
    func resetStateLock() {
        candidateHoleCards = []
        candidateCommunityCards = []
        candidateFirstSeen = nil
        DispatchQueue.main.async {
            self.isStateLocked = false
        }
    }

    // MARK: - State Lock Engine

    /// Compare incoming detection against the current candidate.
    /// If cards match the candidate and have been stable for `lockStabilityDuration`,
    /// lock the state and publish it.
    private func evaluateStateLock(hole: [String], community: [String]) {
        // If already locked with the same cards, skip.
        if isStateLocked,
           currentState.holeCards.sorted() == hole,
           currentState.communityCards.sorted() == community {
            return
        }

        // If the board changed while locked, reset and start tracking new candidate.
        if isStateLocked {
            resetStateLock()
        }

        let now = Date()

        if hole == candidateHoleCards && community == candidateCommunityCards {
            // Same candidate — check if stability threshold is met.
            if let firstSeen = candidateFirstSeen,
               now.timeIntervalSince(firstSeen) >= lockStabilityDuration,
               !hole.isEmpty {
                // Lock the state.
                DispatchQueue.main.async {
                    self.currentState.holeCards = hole
                    self.currentState.communityCards = community
                    self.isStateLocked = true
                }
            }
        } else {
            // New candidate — reset tracking.
            candidateHoleCards = hole
            candidateCommunityCards = community
            candidateFirstSeen = now
        }
    }

    // MARK: - Fallback Result Handlers

    private func handleTextResults(request: VNRequest, error: Error?) {
        // Mock fallback when no ML Model is provided
        DispatchQueue.main.async {
            self.currentState = DetectedPokerState(
                holeCards: ["As", "Kd"],
                communityCards: ["2h", "7c", "Qd"],
                numPlayers: 6,
                dealerPosition: 1,
                myPosition: 3,
                potSize: 15.5
            )
            self.isStateLocked = true
        }
    }
}
