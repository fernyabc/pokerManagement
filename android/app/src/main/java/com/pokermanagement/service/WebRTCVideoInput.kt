package com.pokermanagement.service

import android.content.Context
import android.graphics.Bitmap
import com.pokermanagement.data.network.ApiClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import org.webrtc.DataChannel
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.DefaultVideoEncoderFactory
import org.webrtc.RtpTransceiver
import org.webrtc.EglBase
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.VideoFrame
import org.webrtc.VideoSink
import org.webrtc.VideoTrack
import java.nio.ByteBuffer

class WebRTCVideoInput(
    private val context: Context,
    private val signalingHost: String
) : VideoInputSource {

    private val _isStreaming = MutableStateFlow(false)
    override val isStreaming: StateFlow<Boolean> = _isStreaming

    private val _connectionStatus = MutableStateFlow("Idle")
    override val connectionStatus: StateFlow<String> = _connectionStatus

    override var onFrameCaptured: ((Bitmap) -> Unit)? = null

    private var webSocket: WebSocket? = null
    private var peerConnection: PeerConnection? = null
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private val eglBase = EglBase.create()

    override fun startCapture() {
        initializePeerConnectionFactory()
        connectSignaling()
    }

    private fun initializePeerConnectionFactory() {
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(context)
                .createInitializationOptions()
        )

        val encoderFactory = DefaultVideoEncoderFactory(eglBase.eglBaseContext, true, true)
        val decoderFactory = DefaultVideoDecoderFactory(eglBase.eglBaseContext)

        peerConnectionFactory = PeerConnectionFactory.builder()
            .setVideoEncoderFactory(encoderFactory)
            .setVideoDecoderFactory(decoderFactory)
            .createPeerConnectionFactory()
    }

    private fun connectSignaling() {
        _connectionStatus.value = "Connecting..."
        val client = ApiClient.buildWebSocketClient()
        val request = Request.Builder()
            .url("ws://$signalingHost/ws")
            .build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                _connectionStatus.value = "Signaling Connected"
                val startMsg = JSONObject().apply { put("type", "start") }
                webSocket.send(startMsg.toString())
                createPeerConnection()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleSignalingMessage(JSONObject(text))
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                _isStreaming.value = false
                _connectionStatus.value = "Signaling Error: ${t.message}"
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                _isStreaming.value = false
                _connectionStatus.value = "Disconnected"
            }
        })
    }

    private fun createPeerConnection() {
        val iceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer()
        )
        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        }

        peerConnection = peerConnectionFactory?.createPeerConnection(
            rtcConfig,
            object : PeerConnection.Observer {
                override fun onIceCandidate(candidate: IceCandidate) {
                    val msg = JSONObject().apply {
                        put("type", "iceCandidate")
                        put("candidate", JSONObject().apply {
                            put("candidate", candidate.sdp)
                            put("sdpMid", candidate.sdpMid)
                            put("sdpMLineIndex", candidate.sdpMLineIndex)
                        })
                    }
                    webSocket?.send(msg.toString())
                }

                override fun onTrack(transceiver: org.webrtc.RtpTransceiver) {
                    val track = transceiver.receiver.track()
                    if (track is VideoTrack) {
                        track.addSink(videoSink)
                        _isStreaming.value = true
                        _connectionStatus.value = "Receiving Stream"
                    }
                }

                override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {}
                override fun onSignalingChange(state: PeerConnection.SignalingState) {}
                override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
                    _connectionStatus.value = "ICE: ${state.name}"
                }
                override fun onIceConnectionReceivingChange(receiving: Boolean) {}
                override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {}
                override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
                override fun onAddStream(stream: MediaStream) {}
                override fun onRemoveStream(stream: MediaStream) {}
                override fun onDataChannel(channel: DataChannel) {}
                override fun onRenegotiationNeeded() {}
            }
        )

        // Add recv-only video transceiver
        peerConnection?.addTransceiver(
            org.webrtc.MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO,
            org.webrtc.RtpTransceiver.RtpTransceiverInit(
                org.webrtc.RtpTransceiver.RtpTransceiverDirection.RECV_ONLY
            )
        )
    }

    private val videoSink = VideoSink { frame ->
        frame.retain()
        val bitmap = videoFrameToBitmap(frame)
        frame.release()
        bitmap?.let { onFrameCaptured?.invoke(it) }
    }

    private fun videoFrameToBitmap(frame: VideoFrame): Bitmap? {
        return try {
            val buffer = frame.buffer
            val i420 = buffer.toI420() ?: return null
            val width = i420.width
            val height = i420.height
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)

            // Convert I420 to ARGB using libyuv via Android's built-in converter
            val argbBytes = convertI420ToArgb(i420, width, height)
            bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(argbBytes))
            i420.release()
            bitmap
        } catch (e: Exception) {
            null
        }
    }

    private fun convertI420ToArgb(
        i420: org.webrtc.VideoFrame.I420Buffer,
        width: Int,
        height: Int
    ): ByteArray {
        val yPlane = i420.dataY
        val uPlane = i420.dataU
        val vPlane = i420.dataV
        val strideY = i420.strideY
        val strideU = i420.strideU
        val strideV = i420.strideV

        val argb = ByteArray(width * height * 4)
        for (row in 0 until height) {
            for (col in 0 until width) {
                val y = yPlane.get(row * strideY + col).toInt() and 0xFF
                val u = uPlane.get((row / 2) * strideU + col / 2).toInt() and 0xFF
                val v = vPlane.get((row / 2) * strideV + col / 2).toInt() and 0xFF

                val r = (y + 1.402 * (v - 128)).coerceIn(0.0, 255.0).toInt()
                val g = (y - 0.344136 * (u - 128) - 0.714136 * (v - 128)).coerceIn(0.0, 255.0).toInt()
                val b = (y + 1.772 * (u - 128)).coerceIn(0.0, 255.0).toInt()

                val idx = (row * width + col) * 4
                argb[idx] = r.toByte()
                argb[idx + 1] = g.toByte()
                argb[idx + 2] = b.toByte()
                argb[idx + 3] = 0xFF.toByte()
            }
        }
        return argb
    }

    private fun handleSignalingMessage(msg: JSONObject) {
        when (msg.getString("type")) {
            "offer" -> {
                val sdp = msg.getJSONObject("sdp")
                val sessionDesc = SessionDescription(
                    SessionDescription.Type.OFFER,
                    sdp.getString("sdp")
                )
                peerConnection?.setRemoteDescription(simpleSdpObserver(), sessionDesc)
                peerConnection?.createAnswer(object : SdpObserver {
                    override fun onCreateSuccess(desc: SessionDescription) {
                        peerConnection?.setLocalDescription(simpleSdpObserver(), desc)
                        val answer = JSONObject().apply {
                            put("type", "answer")
                            put("sdp", JSONObject().apply {
                                put("type", "answer")
                                put("sdp", desc.description)
                            })
                        }
                        webSocket?.send(answer.toString())
                    }
                    override fun onSetSuccess() {}
                    override fun onCreateFailure(error: String) {}
                    override fun onSetFailure(error: String) {}
                }, MediaConstraints())
            }
            "iceCandidate" -> {
                val candidateObj = msg.getJSONObject("candidate")
                val candidate = IceCandidate(
                    candidateObj.getString("sdpMid"),
                    candidateObj.getInt("sdpMLineIndex"),
                    candidateObj.getString("candidate")
                )
                peerConnection?.addIceCandidate(candidate)
            }
        }
    }

    private fun simpleSdpObserver() = object : SdpObserver {
        override fun onCreateSuccess(desc: SessionDescription) {}
        override fun onSetSuccess() {}
        override fun onCreateFailure(error: String) {}
        override fun onSetFailure(error: String) {}
    }

    override fun stopCapture() {
        webSocket?.close(1000, "Stopped")
        peerConnection?.close()
        peerConnection = null
        _isStreaming.value = false
        _connectionStatus.value = "Idle"
    }
}
