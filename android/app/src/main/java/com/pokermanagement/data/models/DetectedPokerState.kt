package com.pokermanagement.data.models

import com.google.gson.annotations.SerializedName

data class DetectedPokerState(
    @SerializedName("holeCards") val holeCards: List<String> = emptyList(),
    @SerializedName("communityCards") val communityCards: List<String> = emptyList(),
    @SerializedName("numPlayers") val numPlayers: Int = 2,
    @SerializedName("dealerPosition") val dealerPosition: Int = 0,
    @SerializedName("myPosition") val myPosition: Int = 0,
    @SerializedName("activeAction") val activeAction: String = "none",
    @SerializedName("potSize") val potSize: Double = 0.0
)
