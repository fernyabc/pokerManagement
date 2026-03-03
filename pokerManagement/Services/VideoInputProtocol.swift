import Foundation
import CoreMedia

/// Glass-agnostic video input protocol.
/// Any video source (WebRTC, RTMP, HLS, iPhone camera) conforms to this
/// and the rest of the pipeline (VisionService, BackendService) is unaware
/// of which glasses are connected.
protocol VideoInputSource: ObservableObject {
    var isStreaming: Bool { get }
    var connectionStatus: String { get }
    var onFrameCaptured: ((CMSampleBuffer) -> Void)? { get set }

    func startCapture()
    func stopCapture()
}

/// Identifies available video input types for the source picker.
enum VideoInputType: String, CaseIterable, Identifiable {
    case camera = "iPhone Camera"
    case webRTC = "WebRTC Stream"

    var id: String { rawValue }
}
