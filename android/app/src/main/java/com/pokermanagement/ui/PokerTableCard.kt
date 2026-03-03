package com.pokermanagement.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pokermanagement.data.models.DetectedPokerState

private val green700 = Color(0xFF388E3C)
private val green800 = Color(0xFF2E7D32)
private val cardRed = Color(0xFFD32F2F)
private val cardBlack = Color(0xFF212121)
private val cardBackground = Color(0xFFFAFAFA)

private fun suitColor(card: String): Color {
    return when {
        card.endsWith("h") || card.endsWith("d") -> cardRed
        else -> cardBlack
    }
}

private fun suitSymbol(card: String): String {
    return when {
        card.endsWith("h") -> "♥"
        card.endsWith("d") -> "♦"
        card.endsWith("c") -> "♣"
        card.endsWith("s") -> "♠"
        else -> ""
    }
}

private fun rankDisplay(card: String): String {
    if (card.length < 2) return card
    return when (card.dropLast(1)) {
        "T" -> "10"
        "J" -> "J"
        "Q" -> "Q"
        "K" -> "K"
        "A" -> "A"
        else -> card.dropLast(1)
    }
}

@Composable
fun PlayingCardChip(card: String, modifier: Modifier = Modifier) {
    val color = suitColor(card)
    Box(
        modifier = modifier
            .size(width = 40.dp, height = 56.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(cardBackground)
            .border(1.5.dp, color.copy(alpha = 0.6f), RoundedCornerShape(6.dp)),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = rankDisplay(card),
                color = color,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp
            )
            Text(
                text = suitSymbol(card),
                color = color,
                fontSize = 14.sp
            )
        }
    }
}

@Composable
fun EmptyCardSlot(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(width = 40.dp, height = 56.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(Color.White.copy(alpha = 0.1f))
            .border(1.dp, Color.White.copy(alpha = 0.2f), RoundedCornerShape(6.dp))
    )
}

@Composable
fun PokerTableCard(
    state: DetectedPokerState?,
    isLocked: Boolean,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = green800,
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Status indicator
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .clip(RoundedCornerShape(50))
                        .background(if (isLocked) Color(0xFF4CAF50) else Color(0xFFFFC107))
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    text = if (isLocked) "State Locked" else "Detecting...",
                    color = Color.White.copy(alpha = 0.85f),
                    fontSize = 12.sp
                )
            }

            Spacer(Modifier.height(16.dp))

            // Community cards row
            Text(
                text = "Community",
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 11.sp,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val community = state?.communityCards ?: emptyList()
                for (i in 0 until 5) {
                    if (i < community.size) {
                        PlayingCardChip(community[i])
                    } else {
                        EmptyCardSlot()
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // Hole cards row
            Text(
                text = "Your Hand",
                color = Color.White.copy(alpha = 0.6f),
                fontSize = 11.sp,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val hole = state?.holeCards ?: emptyList()
                for (i in 0 until 2) {
                    if (i < hole.size) {
                        PlayingCardChip(hole[i])
                    } else {
                        EmptyCardSlot()
                    }
                }
            }

            // Pot size
            state?.potSize?.let { pot ->
                if (pot > 0) {
                    Spacer(Modifier.height(12.dp))
                    Text(
                        text = "Pot: ${"%.0f".format(pot)} BB",
                        color = Color.White.copy(alpha = 0.75f),
                        fontSize = 13.sp
                    )
                }
            }
        }
    }
}
