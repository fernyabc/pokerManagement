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

/// The Vision Pipeline based on Apple Vision Framework
class VisionService: ObservableObject {
    @Published var currentState = DetectedPokerState()
    @Published var isProcessing = false
    
    // We use a sequence request handler for continuous video processing
    private var sequenceHandler = VNSequenceRequestHandler()
    
    // To be loaded from Settings or App bundle
    private var customYOLOModel: VNCoreMLModel?
    
    init() {
        setupVisionModels()
    }
    
    private func setupVisionModels() {
        // Load the compiled CoreML model (.mlmodelc)
        // using the name provided in Settings (e.g., "YOLO_Cards_v2")
        // Example:
        // guard let modelURL = Bundle.main.url(forResource: "YOLO_Cards_v2", withExtension: "mlmodelc"),
        //       let mlModel = try? MLModel(contentsOf: modelURL),
        //       let visionModel = try? VNCoreMLModel(for: mlModel) else {
        //     print("Failed to load Vision ML model")
        //     return
        // }
        // self.customYOLOModel = visionModel
    }
    
    /// Called when a frame is received from the Ray-Ban Meta stream workaround
    func processFrame(_ buffer: CMSampleBuffer) {
        guard !isProcessing else { return } // Drop frames if backend is busy
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        
        DispatchQueue.main.async { self.isProcessing = true }
        
        // Setup Vision Request (using generic text/barcode as fallback if CoreML not loaded)
        var requests: [VNRequest] = []
        
        if let yoloModel = customYOLOModel {
            let coreMLRequest = VNCoreMLRequest(model: yoloModel) { [weak self] request, error in
                self?.handleCoreMLResults(request: request, error: error)
            }
            coreMLRequest.imageCropAndScaleOption = .scaleFill
            requests.append(coreMLRequest)
        } else {
            // Fallback for simulation / MVP: Text Recognition (trying to read numbers/suits off cards)
            let textRequest = VNRecognizeTextRequest { [weak self] request, error in
                self?.handleTextResults(request: request, error: error)
            }
            textRequest.recognitionLevel = .accurate
            requests.append(textRequest)
        }
        
        // Execute Vision Pipeline on background thread
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
    
    // MARK: - Result Handlers
    
    private func handleCoreMLResults(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
        
        var newHoleCards: [String] = []
        var newCommunityCards: [String] = []
        
        for observation in results {
            // e.g. "As" (Ace of Spades)
            guard let topLabel = observation.labels.first?.identifier else { continue }
            
            // Basic heuristic: bounding box lower down the screen = Hole Cards, higher = Community Cards
            if observation.boundingBox.origin.y < 0.3 {
                newHoleCards.append(topLabel)
            } else {
                newCommunityCards.append(topLabel)
            }
        }
        
        updateStateIfValid(hole: newHoleCards, community: newCommunityCards)
    }
    
    private func handleTextResults(request: VNRequest, error: Error?) {
        // Mock fallback when no ML Model is provided, simply returns the hardcoded MVP state
        // In reality, this would parse text results looking for strings like "A♠" or "10♥"
        DispatchQueue.main.async {
            self.currentState = DetectedPokerState(
                holeCards: ["As", "Kd"],
                communityCards: ["2h", "7c", "Qd"],
                numPlayers: 6,
                dealerPosition: 1,
                myPosition: 3,
                potSize: 15.5
            )
        }
    }
    
    private func updateStateIfValid(hole: [String], community: [String]) {
        DispatchQueue.main.async {
            self.currentState.holeCards = hole
            self.currentState.communityCards = community
        }
    }
}
