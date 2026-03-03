package com.pokermanagement.service

import android.graphics.Bitmap
import kotlinx.coroutines.flow.StateFlow

interface VideoInputSource {
    val isStreaming: StateFlow<Boolean>
    val connectionStatus: StateFlow<String>
    var onFrameCaptured: ((Bitmap) -> Unit)?
    fun startCapture()
    fun stopCapture()
}
