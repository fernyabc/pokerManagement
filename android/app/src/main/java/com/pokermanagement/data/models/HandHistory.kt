package com.pokermanagement.data.models

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "hand_history")
data class HandHistory(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timestamp: Long = System.currentTimeMillis(),
    val holeCards: String = "",           // JSON array string e.g. "[\"As\",\"Kd\"]"
    val communityCards: String = "",      // JSON array string
    val action: String = "",
    val potSize: Double = 0.0,
    val reasoning: String = ""
)
