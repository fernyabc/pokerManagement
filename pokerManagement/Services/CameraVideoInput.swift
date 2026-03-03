import Foundation
import AVFoundation
import CoreMedia

/// iPhone camera fallback adapter conforming to `VideoInputSource`.
/// Uses AVCaptureSession to capture frames from the rear camera.
class CameraVideoInput: NSObject, ObservableObject, VideoInputSource {

    @Published var isStreaming = false
    @Published var connectionStatus = "Disconnected"

    var onFrameCaptured: ((CMSampleBuffer) -> Void)?

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.pokerManagement.cameraInput")

    override init() {
        super.init()
        configureCaptureSession()
    }

    func startCapture() {
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isStreaming = true
                self.connectionStatus = "Camera Active"
            }
        }
    }

    func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isStreaming = false
                self.connectionStatus = "Disconnected"
            }
        }
    }

    // MARK: - Private

    private func configureCaptureSession() {
        captureSession.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            DispatchQueue.main.async { self.connectionStatus = "Camera Unavailable" }
            return
        }

        guard captureSession.canAddInput(input) else { return }
        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.alwaysDiscardsLateVideoFrames = true

        guard captureSession.canAddOutput(output) else { return }
        captureSession.addOutput(output)

        DispatchQueue.main.async { self.connectionStatus = "Camera Ready" }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraVideoInput: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onFrameCaptured?(sampleBuffer)
    }
}
