package com.pokermanagement.data.network

import com.pokermanagement.data.models.DetectedPokerState
import com.pokermanagement.data.models.GTOSuggestion
import com.pokermanagement.data.models.HandHistory
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

data class SolveResponse(
    @SerializedName("job_id") val jobId: String,
    @SerializedName("status") val status: String
)

data class JobStatusResponse(
    @SerializedName("job_id") val jobId: String,
    @SerializedName("status") val status: String,
    @SerializedName("result") val result: GTOSuggestion?
)

data class LLMSolveResponse(
    @SerializedName("action") val action: String,
    @SerializedName("reasoning") val reasoning: String,
    @SerializedName("confidence") val confidence: Double,
    @SerializedName("ev") val ev: Double,
    @SerializedName("foldWeight") val foldWeight: Double,
    @SerializedName("callWeight") val callWeight: Double,
    @SerializedName("raiseWeight") val raiseWeight: Double
)

data class HudUpdateRequest(
    @SerializedName("player_id") val playerId: String,
    @SerializedName("action") val action: String
)

data class HealthResponse(
    @SerializedName("status") val status: String
)

interface ApiService {
    @POST("v1/solve")
    suspend fun solve(@Body state: DetectedPokerState): GTOSuggestion

    @POST("v1/solve/gto")
    suspend fun solveGto(@Body state: DetectedPokerState): SolveResponse

    @GET("v1/solve/status/{job_id}")
    suspend fun getSolveStatus(@Path("job_id") jobId: String): JobStatusResponse

    @POST("v1/solve/llm")
    suspend fun solveLlm(@Body state: DetectedPokerState): LLMSolveResponse

    @POST("v1/hud/update")
    suspend fun updateHud(@Body request: HudUpdateRequest)

    @POST("v1/log_hand")
    suspend fun logHand(@Body hand: HandHistory)

    @GET("v1/hands")
    suspend fun getHands(): List<HandHistory>

    @GET("health")
    suspend fun health(): HealthResponse
}
