package com.pokermanagement.service

import com.pokermanagement.data.models.DetectedPokerState
import com.pokermanagement.data.models.GTOSuggestion
import com.pokermanagement.data.network.ApiClient
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class BackendService {

    var useMock: Boolean = true
    var texasSolverUrl: String = "http://10.0.2.2:8000"
    var llmSolverUrl: String = "http://10.0.2.2:8000"
    var apiKey: String = "dev-token"

    private val _latestSuggestion = MutableStateFlow<GTOSuggestion?>(null)
    val latestSuggestion: StateFlow<GTOSuggestion?> = _latestSuggestion

    private val _isSolving = MutableStateFlow(false)
    val isSolving: StateFlow<Boolean> = _isSolving

    // Determines if LLM path is preferred for this state
    private fun shouldUseLlm(state: DetectedPokerState): Boolean {
        return state.communityCards.isEmpty() || state.numPlayers > 2
    }

    suspend fun queryGto(state: DetectedPokerState): GTOSuggestion {
        _isSolving.value = true
        return try {
            val suggestion = when {
                useMock -> mockSuggestion()
                shouldUseLlm(state) -> queryLlm(state)
                else -> queryGtoEndpoint(state)
            }
            _latestSuggestion.value = suggestion
            suggestion
        } catch (e: Exception) {
            val fallback = GTOSuggestion(
                action = "fold",
                reasoning = "Backend error: ${e.message}",
                foldWeight = 0.6,
                callWeight = 0.3,
                raiseWeight = 0.1
            )
            _latestSuggestion.value = fallback
            fallback
        } finally {
            _isSolving.value = false
        }
    }

    private suspend fun mockSuggestion(): GTOSuggestion {
        delay(1500)
        return GTOSuggestion(
            action = "raise",
            raiseSize = 3.0,
            ev = 0.85,
            confidence = 0.9,
            reasoning = "Mock: Strong hand. Raise for value.",
            foldWeight = 0.1,
            callWeight = 0.15,
            raiseWeight = 0.75
        )
    }

    private suspend fun queryLlm(state: DetectedPokerState): GTOSuggestion {
        ApiClient.configure(llmSolverUrl, apiKey)
        val response = ApiClient.getService().solveLlm(state)
        return GTOSuggestion(
            action = response.action,
            ev = response.ev,
            confidence = response.confidence,
            reasoning = response.reasoning,
            foldWeight = response.foldWeight,
            callWeight = response.callWeight,
            raiseWeight = response.raiseWeight
        )
    }

    private suspend fun queryGtoEndpoint(state: DetectedPokerState): GTOSuggestion {
        ApiClient.configure(texasSolverUrl, apiKey)
        return ApiClient.getService().solve(state)
    }
}
