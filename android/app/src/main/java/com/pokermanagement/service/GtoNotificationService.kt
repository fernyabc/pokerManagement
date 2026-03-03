package com.pokermanagement.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.pokermanagement.data.models.GTOSuggestion

class GtoNotificationService : Service() {

    companion object {
        const val CHANNEL_ID = "poker_gto"
        const val NOTIFICATION_ID = 1001
        private const val CHANNEL_NAME = "GTO Suggestions"

        fun createNotificationChannel(context: Context) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Real-time GTO poker suggestions"
                setShowBadge(false)
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private lateinit var notificationManager: NotificationManager

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(NotificationManager::class.java)
        createNotificationChannel(this)
        startForeground(NOTIFICATION_ID, buildIdleNotification())
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    fun updateSuggestion(suggestion: GTOSuggestion) {
        val notification = buildSuggestionNotification(suggestion)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun buildIdleNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Poker GTO")
            .setContentText("Waiting for cards...")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun buildSuggestionNotification(suggestion: GTOSuggestion): Notification {
        val actionTitle = suggestion.action.uppercase()
        val raiseSuffix = suggestion.raiseSize?.let { " ${it}x" } ?: ""
        val title = "$actionTitle$raiseSuffix"

        val foldPct = (suggestion.foldWeight * 100).toInt()
        val callPct = (suggestion.callWeight * 100).toInt()
        val raisePct = (suggestion.raiseWeight * 100).toInt()
        val weightsText = "F:$foldPct% C:$callPct% R:$raisePct%"

        val evText = if (suggestion.ev != 0.0) " | EV: %.2f".format(suggestion.ev) else ""

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("$weightsText$evText")
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText("$weightsText$evText\n${suggestion.reasoning}")
            )
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }
}
