package com.pokermanagement.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pokermanagement.data.models.HandHistory
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val dateFormat = SimpleDateFormat("MMM dd, HH:mm", Locale.getDefault())

private fun actionColor(action: String): Color = when (action.lowercase()) {
    "fold" -> Color(0xFFEF5350)
    "call", "check" -> Color(0xFF42A5F5)
    else -> Color(0xFF66BB6A)
}

@Composable
fun HandHistoryItem(hand: HandHistory) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = Color(0xFF1E1E2E),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = hand.holeCards,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 15.sp
                )
                Text(
                    text = hand.action.uppercase(),
                    color = actionColor(hand.action),
                    fontWeight = FontWeight.Bold,
                    fontSize = 14.sp
                )
            }

            if (hand.communityCards.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text(
                    text = "Board: ${hand.communityCards}",
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 12.sp
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "Pot: ${"%.0f".format(hand.potSize)} BB",
                    color = Color.White.copy(alpha = 0.5f),
                    fontSize = 11.sp
                )
                Text(
                    text = dateFormat.format(Date(hand.timestamp)),
                    color = Color.White.copy(alpha = 0.4f),
                    fontSize = 11.sp
                )
            }

            if (hand.reasoning.isNotEmpty()) {
                Spacer(Modifier.height(6.dp))
                Text(
                    text = hand.reasoning,
                    color = Color.White.copy(alpha = 0.65f),
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    maxLines = 3
                )
            }
        }
    }
}

@Composable
fun HistoryScreen(hands: List<HandHistory>, onExportCsv: () -> Unit, modifier: Modifier = Modifier) {
    if (hands.isEmpty()) {
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = "No hands recorded yet",
                color = Color.White.copy(alpha = 0.5f),
                fontSize = 16.sp
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = "Play a hand to see it here",
                color = Color.White.copy(alpha = 0.3f),
                fontSize = 13.sp
            )
        }
    } else {
        LazyColumn(
            modifier = modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "${hands.size} Hand${if (hands.size == 1) "" else "s"}",
                        color = Color.White.copy(alpha = 0.6f),
                        fontSize = 13.sp
                    )
                    IconButton(onClick = onExportCsv) {
                        Icon(
                            imageVector = Icons.Default.Share,
                            contentDescription = "Export CSV",
                            tint = Color(0xFF7C83FD)
                        )
                    }
                }
            }
            items(hands, key = { it.id }) { hand ->
                HandHistoryItem(hand)
            }
        }
    }
}
