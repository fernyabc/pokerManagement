package com.pokermanagement.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.pokermanagement.data.models.HandHistory
import kotlinx.coroutines.flow.Flow

@Dao
interface HandHistoryDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(hand: HandHistory)

    @Query("SELECT * FROM hand_history ORDER BY timestamp DESC")
    fun getAllHands(): Flow<List<HandHistory>>

    @Query("DELETE FROM hand_history")
    suspend fun deleteAll()
}
