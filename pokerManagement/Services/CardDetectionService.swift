import Foundation
import CoreML
import Vision

/// A single card detection result produced by the YOLO model.
struct CardDetection {
    /// Raw class label from the model (e.g. "10C", "AC"). Caller normalises to poker notation.
    let label: String
    /// Bounding box in Vision-normalised coordinates:
    /// origin is bottom-left, x/y/width/height are all in [0, 1].
    let boundingBox: CGRect
    /// Detection confidence in [0, 1].
    let confidence: Float
}

class CardDetectionService {
    var modelLoaded = false
    private var model: VNCoreMLModel?

    // MARK: - Model constants (must match the exported YOLOv11 model)

    /// Input resolution the model was trained/exported at.
    private let modelInputSize: Float = 640.0
    /// 4 bbox coords + 52 class scores.
    private let numFeatures = 56
    /// Total anchor positions in the YOLO head (80×80 + 40×40 + 20×20).
    private let numAnchors = 8400
    private let numClasses = 52

    /// Minimum class probability to keep a detection.
    private let confThreshold: Float = 0.25
    /// IoU threshold for Non-Maximum Suppression.
    private let iouThreshold: Float = 0.45

    /// Class labels in the same order as the model's output indices.
    private let classLabels: [String] = [
        "10C", "10D", "10H", "10S",
        "2C",  "2D",  "2H",  "2S",
        "3C",  "3D",  "3H",  "3S",
        "4C",  "4D",  "4H",  "4S",
        "5C",  "5D",  "5H",  "5S",
        "6C",  "6D",  "6H",  "6S",
        "7C",  "7D",  "7H",  "7S",
        "8C",  "8D",  "8H",  "8S",
        "9C",  "9D",  "9H",  "9S",
        "AC",  "AD",  "AH",  "AS",
        "JC",  "JD",  "JH",  "JS",
        "KC",  "KD",  "KH",  "KS",
        "QC",  "QD",  "QH",  "QS",
    ]

    // MARK: - Init

    init() {
        // Priority: YOLOv11 mlpackage → YOLOv11 mlmodelc → YOLOv8 mlmodelc
        let candidates: [(String, String)] = [
            ("yolov11-playing-cards", "mlpackage"),
            ("yolov11-playing-cards", "mlmodelc"),
            ("yolov8-playing-cards",  "mlmodelc"),
        ]
        for (name, ext) in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                do {
                    self.model = try VNCoreMLModel(for: MLModel(contentsOf: url))
                    self.modelLoaded = true
                    print("CardDetectionService: loaded \(name).\(ext)")
                    return
                } catch {
                    print("CardDetectionService: load error for \(name).\(ext): \(error)")
                }
            }
        }
        print("CardDetectionService: no model found, will use mock fallback")
    }

    // MARK: - Public API

    func detectCards(
        in pixelBuffer: CVPixelBuffer,
        completion: @escaping ([CardDetection]?, Error?) -> Void
    ) {
        guard let model else { completion(nil, nil); return }

        let request = VNCoreMLRequest(model: model) { [weak self] req, err in
            guard let self else { completion(nil, nil); return }
            if let err {
                completion(nil, err)
                return
            }

            // ── Path A: Apple-style object detector → VNRecognizedObjectObservation ──
            // This fires if the model was exported with proper CoreML NMS/coordinates
            // metadata (e.g. via a CreateML-style object detection pipeline).
            if let observations = req.results as? [VNRecognizedObjectObservation],
               !observations.isEmpty {
                let detections = observations.compactMap { obs -> CardDetection? in
                    guard let top = obs.labels.first else { return nil }
                    return CardDetection(
                        label: top.identifier,
                        boundingBox: obs.boundingBox,
                        confidence: top.confidence
                    )
                }
                completion(detections, nil)
                return
            }

            // ── Path B: Raw YOLO tensor → VNCoreMLFeatureValueObservation ──
            // Our YOLOv11 mlpackage was exported without NMS, so Vision wraps
            // the raw [1, 56, 8400] output as VNCoreMLFeatureValueObservation.
            if let observations = req.results as? [VNCoreMLFeatureValueObservation] {
                let detections = self.decodeRawTensor(observations)
                completion(detections, nil)
                return
            }

            completion([], nil)
        }

        request.imageCropAndScaleOption = .scaleFill
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up
            ).perform([request])
        }
    }

    // MARK: - Raw YOLO Tensor Decoder

    /// Decodes the raw `[1, 56, 8400]` YOLO output tensor.
    ///
    /// Tensor layout per anchor *i*:
    /// - `[0, 0, i]` … `[0, 3, i]` — cx, cy, w, h in model-pixel units [0, 640]
    /// - `[0, 4, i]` … `[0, 55, i]` — class probabilities (sigmoid applied), [0, 1]
    ///
    /// Returns detections in Vision coordinates (origin bottom-left, [0, 1]).
    private func decodeRawTensor(
        _ observations: [VNCoreMLFeatureValueObservation]
    ) -> [CardDetection] {

        guard let multiArray = observations.first?.featureValue.multiArrayValue else {
            print("CardDetectionService: no multiarray in feature value observations")
            return []
        }

        // Validate shape [1, 56, 8400]
        let shape = multiArray.shape.map(\.intValue)
        guard shape.count == 3,
              shape[1] == numFeatures,
              shape[2] == numAnchors else {
            print("CardDetectionService: unexpected tensor shape \(shape), expected [1, \(numFeatures), \(numAnchors)]")
            return []
        }

        guard multiArray.dataType == .float32 else {
            print("CardDetectionService: unexpected data type \(multiArray.dataType)")
            return []
        }

        // Access raw memory for performance — avoids per-element NSNumber bridging.
        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        let featureStride = multiArray.strides[1].intValue  // stride between features (= 8400)
        let anchorStride  = multiArray.strides[2].intValue  // stride between anchors  (= 1)

        var raw: [(label: String, box: CGRect, score: Float)] = []
        raw.reserveCapacity(128)

        for i in 0..<numAnchors {
            let a = i * anchorStride

            // Bounding box (pixel units → normalise to [0, 1])
            let cx = ptr[0 * featureStride + a] / modelInputSize
            let cy = ptr[1 * featureStride + a] / modelInputSize
            let w  = ptr[2 * featureStride + a] / modelInputSize
            let h  = ptr[3 * featureStride + a] / modelInputSize

            // Max class score
            var maxScore: Float = 0
            var maxClass = 0
            for c in 0..<numClasses {
                let s = ptr[(4 + c) * featureStride + a]
                if s > maxScore { maxScore = s; maxClass = c }
            }

            guard maxScore >= confThreshold else { continue }

            // cx,cy,w,h → x1,y1 corner format, clamped to [0, 1]
            let x1 = max(0, cx - w / 2)
            let y1 = max(0, cy - h / 2)
            let bw = min(1, cx + w / 2) - x1
            let bh = min(1, cy + h / 2) - y1

            guard bw > 0, bh > 0 else { continue }

            // Vision coordinate system: origin at bottom-left → flip y.
            let visionY = 1.0 - (y1 + bh)
            let box = CGRect(
                x: CGFloat(x1), y: CGFloat(visionY),
                width: CGFloat(bw), height: CGFloat(bh)
            )

            raw.append((label: classLabels[maxClass], box: box, score: maxScore))
        }

        return nms(raw, iouThreshold: iouThreshold)
            .map { CardDetection(label: $0.label, boundingBox: $0.box, confidence: $0.score) }
    }

    // MARK: - Non-Maximum Suppression

    private func nms(
        _ detections: [(label: String, box: CGRect, score: Float)],
        iouThreshold: Float
    ) -> [(label: String, box: CGRect, score: Float)] {
        let sorted = detections.sorted { $0.score > $1.score }
        var suppressed = [Bool](repeating: false, count: sorted.count)
        var kept: [(label: String, box: CGRect, score: Float)] = []

        for i in 0..<sorted.count {
            guard !suppressed[i] else { continue }
            kept.append(sorted[i])
            for j in (i + 1)..<sorted.count {
                if iou(sorted[i].box, sorted[j].box) > iouThreshold {
                    suppressed[j] = true
                }
            }
        }
        return kept
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let inter = a.intersection(b)
        guard !inter.isNull else { return 0 }
        let interArea = Float(inter.width * inter.height)
        let unionArea = Float(a.width * a.height) + Float(b.width * b.height) - interArea
        return unionArea > 0 ? interArea / unionArea : 0
    }
}
