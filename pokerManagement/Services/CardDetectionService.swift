import Foundation
import Vision
import CoreML

class CardDetectionService: ObservableObject {
    @Published var modelLoaded = false
    private var visionModel: VNCoreMLModel?
    private let modelName = "yolov8-playing-cards" // Configurable
    
    init() {
        loadModel()
    }
    
    func loadModel() {
        if let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            do {
                let mlModel = try MLModel(contentsOf: modelURL)
                let model = try VNCoreMLModel(for: mlModel)
                self.visionModel = model
                
                DispatchQueue.main.async {
                    self.modelLoaded = true
                    print("Successfully loaded \(self.modelName) CoreML model.")
                }
            } catch {
                print("Failed to initialize Vision ML model: \(error.localizedDescription)")
            }
        } else {
            print("Model file \(modelName).mlmodelc not found in bundle. Continuing with fallback.")
        }
    }
    
    func detectCards(in pixelBuffer: CVPixelBuffer, completion: @escaping ([VNRecognizedObjectObservation]?, Error?) -> Void) {
        guard let model = visionModel else {
            completion(nil, NSError(domain: "CardDetectionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"]))
            return
        }
        
        let request = VNCoreMLRequest(model: model) { request, error in
            completion(request.results as? [VNRecognizedObjectObservation], error)
        }
        request.imageCropAndScaleOption = .scaleFill
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            completion(nil, error)
        }
    }
}
