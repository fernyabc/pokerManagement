package com.pokermanagement.service

import android.graphics.Bitmap
import com.pokermanagement.data.models.DetectedPokerState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class VisionService(private val cardDetectionService: CardDetectionService) {

    private val _isStateLocked = MutableStateFlow(false)
    val isStateLocked: StateFlow<Boolean> = _isStateLocked

    private val _currentState = MutableStateFlow<DetectedPokerState?>(null)
    val currentState: StateFlow<DetectedPokerState?> = _currentState

    private val _detectedCards = MutableStateFlow<List<String>>(emptyList())
    val detectedCards: StateFlow<List<String>> = _detectedCards

    // State lock tracking
    private var candidateState: DetectedPokerState? = null
    private var candidateFirstSeen: Long = 0L
    private val stabilityWindowMs = 500L

    fun processFrame(bitmap: Bitmap) {
        val state = if (cardDetectionService.modelLoaded) {
            val detected = cardDetectionService.detect(bitmap)
            val (holeCards, communityCards) = cardDetectionService.classifyCards(detected)
            _detectedCards.value = holeCards + communityCards

            DetectedPokerState(
                holeCards = holeCards,
                communityCards = communityCards,
                numPlayers = 2,
                dealerPosition = 0,
                myPosition = 0,
                activeAction = "none",
                potSize = 0.0
            )
        } else {
            // Fallback mock state when model is absent
            DetectedPokerState(
                holeCards = listOf("As", "Kd"),
                communityCards = listOf("2h", "7c", "Qd"),
                numPlayers = 2,
                dealerPosition = 0,
                myPosition = 0,
                activeAction = "none",
                potSize = 100.0
            )
        }

        evaluateStateLock(state)
    }

    private fun evaluateStateLock(newState: DetectedPokerState) {
        val now = System.currentTimeMillis()

        if (statesMatch(newState, candidateState)) {
            if (!_isStateLocked.value && now - candidateFirstSeen >= stabilityWindowMs) {
                _currentState.value = newState
                _isStateLocked.value = true
            }
        } else {
            // New candidate — reset tracking
            candidateState = newState
            candidateFirstSeen = now
            if (_isStateLocked.value) {
                _isStateLocked.value = false
            }
        }
    }

    private fun statesMatch(a: DetectedPokerState, b: DetectedPokerState?): Boolean {
        if (b == null) return false
        return a.holeCards.toSet() == b.holeCards.toSet() &&
                a.communityCards.toSet() == b.communityCards.toSet()
    }

    fun resetStateLock() {
        _isStateLocked.value = false
        candidateState = null
        candidateFirstSeen = 0L
    }

    fun updatePotSize(potSize: Double) {
        val current = _currentState.value ?: return
        _currentState.value = current.copy(potSize = potSize)
    }
}
