package com.pokermanagement

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.lifecycleScope
import com.pokermanagement.service.CameraVideoInput
import com.pokermanagement.service.GtoNotificationService
import com.pokermanagement.service.WebRTCVideoInput
import com.pokermanagement.ui.MainScreen
import com.pokermanagement.viewmodel.MainViewModel
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val viewModel: MainViewModel by viewModels()

    private val permissionsLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { results ->
        val cameraGranted = results[Manifest.permission.CAMERA] == true
        if (cameraGranted) {
            startCameraInput()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Start foreground notification service
        val serviceIntent = Intent(this, GtoNotificationService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        requestPermissions()

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                val uiState by viewModel.uiState.collectAsState()
                MainScreen(
                    uiState = uiState,
                    onStartMic = { viewModel.startMicInput() },
                    onStopMic = { viewModel.stopMicInput() },
                    onResetState = { viewModel.resetState() },
                    onSaveSetting = { key, value -> viewModel.saveSetting(key, value) },
                    onVideoInputChanged = { inputName ->
                        when (inputName) {
                            "camera" -> startCameraInput()
                            "webrtc" -> startWebRtcInput(uiState.solverEndpoint)
                        }
                    }
                )
            }
        }
    }

    private fun requestPermissions() {
        val permissions = mutableListOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        permissionsLauncher.launch(permissions.toTypedArray())
    }

    private fun startCameraInput() {
        val input = CameraVideoInput(this, this)
        viewModel.setVideoInput(input, "camera")
    }

    private fun startWebRtcInput(endpoint: String) {
        val host = endpoint
            .removePrefix("http://")
            .removePrefix("https://")
            .trimEnd('/')
        val input = WebRTCVideoInput(this, host)
        viewModel.setVideoInput(input, "webrtc")
    }
}
