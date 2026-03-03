package com.pokermanagement.viewmodel

import android.app.Application
import android.content.Intent
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.pokermanagement.data.db.AppDatabase
import com.pokermanagement.data.models.DetectedPokerState
import com.pokermanagement.data.models.GTOSuggestion
import com.pokermanagement.data.models.HandHistory
import com.pokermanagement.service.BackendService
import com.pokermanagement.service.CardDetectionService
import com.pokermanagement.service.GtoNotificationService
import com.pokermanagement.service.SpeechInputService
import com.pokermanagement.service.VideoInputSource
import com.pokermanagement.service.VisionService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

private val Application.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

data class MainUiState(
    val connectionStatus: String = "Idle",
    val isStreaming: Boolean = false,
    val isStateLocked: Boolean = false,
    val detectedCards: List<String> = emptyList(),
    val currentPokerState: DetectedPokerState? = null,
    val latestSuggestion: GTOSuggestion? = null,
    val isSolving: Boolean = false,
    val handHistory: List<HandHistory> = emptyList(),
    val transcribedText: String = "",
    val isListening: Boolean = false,
    val parsedPotSize: Double? = null,
    val parsedBetSize: Double? = null,
    val useMockSolver: Boolean = true,
    val solverEndpoint: String = "http://10.0.2.2:8000",
    val solverApiKey: String = "dev-token",
    val selectedVideoInput: String = "camera",
    val modelLoaded: Boolean = false
)

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val dataStore = application.dataStore
    private val db = AppDatabase.getInstance(application)
    private val dao = db.handHistoryDao()

    val cardDetectionService = CardDetectionService(application)
    val visionService = VisionService(cardDetectionService)
    val backendService = BackendService()
    val speechInputService = SpeechInputService(application)
    var notificationService: GtoNotificationService? = null

    private var activeVideoInput: VideoInputSource? = null

    // Settings keys
    private val KEY_USE_MOCK = booleanPreferencesKey("useMockSolver")
    private val KEY_ENDPOINT = stringPreferencesKey("solverEndpoint")
    private val KEY_API_KEY = stringPreferencesKey("solverApiKey")
    private val KEY_VIDEO_INPUT = stringPreferencesKey("selectedVideoInput")

    private val _uiState = MutableStateFlow(MainUiState(modelLoaded = cardDetectionService.modelLoaded))
    val uiState: StateFlow<MainUiState> = _uiState

    init {
        loadSettings()
        collectFlows()
        GtoNotificationService.createNotificationChannel(application)
    }

    private fun loadSettings() {
        viewModelScope.launch {
            dataStore.data.collect { prefs ->
                val useMock = prefs[KEY_USE_MOCK] ?: true
                val endpoint = prefs[KEY_ENDPOINT] ?: "http://10.0.2.2:8000"
                val apiKey = prefs[KEY_API_KEY] ?: "dev-token"
                val videoInput = prefs[KEY_VIDEO_INPUT] ?: "camera"

                backendService.useMock = useMock
                backendService.texasSolverUrl = endpoint
                backendService.llmSolverUrl = endpoint
                backendService.apiKey = apiKey

                _uiState.value = _uiState.value.copy(
                    useMockSolver = useMock,
                    solverEndpoint = endpoint,
                    solverApiKey = apiKey,
                    selectedVideoInput = videoInput
                )
            }
        }
    }

    private fun collectFlows() {
        // Hand history
        viewModelScope.launch {
            dao.getAllHands().collect { hands ->
                _uiState.value = _uiState.value.copy(handHistory = hands)
            }
        }

        // Vision state lock → trigger GTO query
        viewModelScope.launch {
            visionService.isStateLocked.collect { locked ->
                _uiState.value = _uiState.value.copy(isStateLocked = locked)
                if (locked) {
                    val state = visionService.currentState.value ?: return@collect
                    querySolver(state)
                }
            }
        }

        // Current poker state
        viewModelScope.launch {
            visionService.currentState.collect { state ->
                _uiState.value = _uiState.value.copy(currentPokerState = state)
            }
        }

        // Detected cards
        viewModelScope.launch {
            visionService.detectedCards.collect { cards ->
                _uiState.value = _uiState.value.copy(detectedCards = cards)
            }
        }

        // Backend suggestion
        viewModelScope.launch {
            backendService.latestSuggestion.collect { suggestion ->
                _uiState.value = _uiState.value.copy(latestSuggestion = suggestion)
                suggestion?.let { notificationService?.updateSuggestion(it) }
            }
        }

        // Backend solving state
        viewModelScope.launch {
            backendService.isSolving.collect { solving ->
                _uiState.value = _uiState.value.copy(isSolving = solving)
            }
        }

        // Speech
        viewModelScope.launch {
            speechInputService.transcribedText.collect { text ->
                _uiState.value = _uiState.value.copy(transcribedText = text)
            }
        }
        viewModelScope.launch {
            speechInputService.isListening.collect { listening ->
                _uiState.value = _uiState.value.copy(isListening = listening)
            }
        }
        viewModelScope.launch {
            speechInputService.parsedPotSize.collect { amount ->
                _uiState.value = _uiState.value.copy(parsedPotSize = amount)
                amount?.let { visionService.updatePotSize(it) }
            }
        }
        viewModelScope.launch {
            speechInputService.parsedBetSize.collect { amount ->
                _uiState.value = _uiState.value.copy(parsedBetSize = amount)
            }
        }
    }

    private suspend fun querySolver(state: DetectedPokerState) {
        val suggestion = backendService.queryGto(state)

        // Persist to Room
        val hand = HandHistory(
            holeCards = state.holeCards.toString(),
            communityCards = state.communityCards.toString(),
            action = suggestion.action,
            potSize = state.potSize,
            reasoning = suggestion.reasoning
        )
        dao.insert(hand)
    }

    fun setVideoInput(input: VideoInputSource, inputName: String) {
        activeVideoInput?.stopCapture()
        activeVideoInput = input
        input.onFrameCaptured = { bitmap ->
            visionService.processFrame(bitmap)
        }

        viewModelScope.launch {
            input.isStreaming.collect { streaming ->
                _uiState.value = _uiState.value.copy(isStreaming = streaming)
            }
        }
        viewModelScope.launch {
            input.connectionStatus.collect { status ->
                _uiState.value = _uiState.value.copy(connectionStatus = status)
            }
        }

        input.startCapture()

        viewModelScope.launch {
            dataStore.edit { prefs -> prefs[KEY_VIDEO_INPUT] = inputName }
        }
    }

    fun startMicInput() = speechInputService.startListening()
    fun stopMicInput() = speechInputService.stopListening()
    fun resetState() = visionService.resetStateLock()

    fun saveSetting(key: String, value: String) {
        viewModelScope.launch {
            dataStore.edit { prefs ->
                when (key) {
                    "useMockSolver" -> prefs[KEY_USE_MOCK] = value.toBoolean()
                    "solverEndpoint" -> prefs[KEY_ENDPOINT] = value
                    "solverApiKey" -> prefs[KEY_API_KEY] = value
                }
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        activeVideoInput?.stopCapture()
        cardDetectionService.close()
        speechInputService.stopListening()
    }
}
