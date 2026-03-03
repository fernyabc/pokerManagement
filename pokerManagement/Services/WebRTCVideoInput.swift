import Foundation
import WebRTC
import Combine
import Starscream

/// WebRTC video input adapter conforming to `VideoInputSource`.
/// Connects to a WebSocket signaling server, establishes a WebRTC peer
/// connection, and delivers frames via `onFrameCaptured`.
class WebRTCVideoInput: NSObject, ObservableObject, VideoInputSource, RTCPeerConnectionDelegate {

    @Published var isStreaming = false
    @Published var connectionStatus = "Disconnected"

    var onFrameCaptured: ((CMSampleBuffer) -> Void)?

    /// The signaling server URL. Defaults to the local backend.
    var signalingURL: String = "ws://localhost:8000/ws"

    private var peerConnectionFactory: RTCPeerConnectionFactory!
    private var peerConnection: RTCPeerConnection?
    private var videoTrack: RTCVideoTrack?
    private var webSocket: Starscream.WebSocket!

    override init() {
        super.init()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
    }

    func startCapture() {
        connectionStatus = "Connecting to Signaling..."
        guard let url = URL(string: signalingURL) else {
            connectionStatus = "Invalid Signaling URL"
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        webSocket = WebSocket(request: request)
        webSocket.delegate = self
        webSocket.connect()
    }

    func stopCapture() {
        isStreaming = false
        connectionStatus = "Disconnected"
        webSocket?.disconnect()
        peerConnection?.close()
        peerConnection = nil
    }

    // MARK: - Signaling

    private func handleWebSocketMessage(_ string: String) {
        guard let data = string.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let offerData = message["offer"] as? [String: Any], let sdp = offerData["sdp"] as? String {
            createPeerConnection()
            let offer = RTCSessionDescription(type: .offer, sdp: sdp)
            peerConnection?.setRemoteDescription(offer) { [weak self] error in
                guard error == nil else { return }
                self?.createAnswer()
            }
        } else if let iceCandidateData = message["iceCandidate"] as? [String: Any],
                  let sdp = iceCandidateData["sdp"] as? String,
                  let sdpMid = iceCandidateData["sdpMid"] as? String,
                  let sdpMLineIndex = iceCandidateData["sdpMLineIndex"] as? Int32 {
            let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
            peerConnection?.add(candidate) { error in
                if let error = error {
                    print("Error adding ICE candidate: \(error.localizedDescription)")
                }
            }
        }
    }

    private func createPeerConnection() {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        self.peerConnection = peerConnectionFactory.peerConnection(
            with: config, constraints: constraints, delegate: self
        )

        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .recvOnly
        self.peerConnection?.addTransceiver(of: .video, init: transceiverInit)
    }

    private func createAnswer() {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection?.answer(for: constraints) { [weak self] answer, error in
            guard let answer = answer, error == nil else { return }

            self?.peerConnection?.setLocalDescription(answer) { error in
                guard error == nil else { return }
                let answerMessage: [String: Any] = [
                    "answer": ["type": "answer", "sdp": answer.sdp]
                ]
                if let data = try? JSONSerialization.data(withJSONObject: answerMessage),
                   let message = String(data: data, encoding: .utf8) {
                    self?.webSocket.write(string: message)
                }
            }
        }
    }

    // MARK: - RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectionStatus = "P2P Connected. Streaming..."
                self.isStreaming = true
            case .failed, .closed, .disconnected:
                self.isStreaming = false
                self.connectionStatus = "Disconnected"
            default:
                break
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let track = stream.videoTracks.first {
            self.videoTrack = track
            track.add(self)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let candidateMessage: [String: Any] = [
            "iceCandidate": [
                "sdp": candidate.sdp,
                "sdpMid": candidate.sdpMid ?? "",
                "sdpMLineIndex": candidate.sdpMLineIndex
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: candidateMessage),
           let message = String(data: data, encoding: .utf8) {
            webSocket.write(string: message)
        }
    }

    // Boilerplate delegate stubs
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: - RTCVideoRenderer

extension WebRTCVideoInput: RTCVideoRenderer {
    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame = frame, let buffer = frame.buffer as? RTCCVPixelBuffer else { return }

        var sampleBuffer: CMSampleBuffer?
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: Int32(buffer.width),
            height: Int32(buffer.height),
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )

        var timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: frame.timeStampNs, timescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )

        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer.pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc!,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        if let sampleBuffer = sampleBuffer {
            onFrameCaptured?(sampleBuffer)
        }
    }
}

// MARK: - WebSocketDelegate

extension WebRTCVideoInput: Starscream.WebSocketDelegate {
    func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        switch event {
        case .connected:
            self.connectionStatus = "Signaling Connected. Waiting for offer..."
            client.write(string: "{\"type\": \"start\"}")
        case .disconnected:
            self.connectionStatus = "Signaling Disconnected"
        case .text(let string):
            handleWebSocketMessage(string)
        case .error(let error):
            print("WebSocket Error: \(error?.localizedDescription ?? "Unknown")")
            self.connectionStatus = "Signaling Error"
        default:
            break
        }
    }
}
