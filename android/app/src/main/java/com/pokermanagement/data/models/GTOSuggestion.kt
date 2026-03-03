package com.pokermanagement.data.models

import com.google.gson.annotations.SerializedName

data class GTOSuggestion(
    @SerializedName("action") val action: String = "fold",
    @SerializedName("raiseSize") val raiseSize: Double? = null,
    @SerializedName("ev") val ev: Double = 0.0,
    @SerializedName("confidence") val confidence: Double = 0.0,
    @SerializedName("reasoning") val reasoning: String = "",
    @SerializedName("foldWeight") val foldWeight: Double = 0.33,
    @SerializedName("callWeight") val callWeight: Double = 0.33,
    @SerializedName("raiseWeight") val raiseWeight: Double = 0.34,
    @SerializedName("isSolving") val isSolving: Boolean = false,
    @SerializedName("jobId") val jobId: String? = null
)
