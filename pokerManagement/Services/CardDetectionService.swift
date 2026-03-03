import Foundation
import CoreML
import Vision

class CardDetectionService {
    var modelLoaded = false
    private var model: VNCoreMLModel?

    init() {
        guard let url = Bundle.main.url(forResource: "yolov8-playing-cards", withExtension: "mlmodelc") else { return }
        do {
            self.model = try VNCoreMLModel(for: MLModel(contentsOf: url))
            self.modelLoaded = true
        } catch {
            print("CoreML load error: \(error)")
        }
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
