import Foundation
import CoreML
import Vision

class CardDetectionService {
    var modelLoaded = false
    private var model: VNCoreMLModel?

    init() {
        // Try YOLOv11 .mlpackage first, then fall back to YOLOv8 .mlmodelc
        let candidates: [(String, String)] = [
            ("yolov11-playing-cards", "mlmodelc"),
            ("yolov11-playing-cards", "mlpackage"),
            ("yolov8-playing-cards", "mlmodelc"),
        ]
        for (name, ext) in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                do {
                    self.model = try VNCoreMLModel(for: MLModel(contentsOf: url))
                    self.modelLoaded = true
                    print("CardDetectionService: loaded \(name).\(ext)")
                    return
                } catch {
                    print("CoreML load error for \(name).\(ext): \(error)")
                }
            }
        }
        print("CardDetectionService: no model found, will use mock fallback")
    }

    func detectCards(in pixelBuffer: CVPixelBuffer, completion: @escaping ([VNRecognizedObjectObservation]?, Error?) -> Void) {
        guard let model else { completion(nil, nil); return }
        let request = VNCoreMLRequest(model: model) { req, err in
            completion(req.results as? [VNRecognizedObjectObservation], err)
        }
        request.imageCropAndScaleOption = .scaleFill
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
        }
    }
}
