package com.pokermanagement.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pokermanagement.data.models.GTOSuggestion

private val foldColor = Color(0xFFEF5350)
private val callColor = Color(0xFF42A5F5)
private val raiseColor = Color(0xFF66BB6A)

@Composable
fun WeightBar(label: String, weight: Double, color: Color, modifier: Modifier = Modifier) {
    val animatedWidth by animateFloatAsState(
        targetValue = weight.toFloat().coerceIn(0f, 1f),
        animationSpec = tween(600),
        label = "weight_$label"
    )
    val pct = (weight * 100).toInt()

    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 12.sp,
            modifier = Modifier.width(40.dp)
        )
        Spacer(Modifier.width(8.dp))
        Box(
            modifier = Modifier
                .weight(1f)
                .height(10.dp)
                .clip(RoundedCornerShape(5.dp))
                .background(Color.White.copy(alpha = 0.1f))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(animatedWidth)
                    .height(10.dp)
                    .clip(RoundedCornerShape(5.dp))
                    .background(color)
            )
        }
        Spacer(Modifier.width(8.dp))
        Text(
            text = "$pct%",
            color = Color.White.copy(alpha = 0.85f),
            fontSize = 12.sp,
            modifier = Modifier.width(32.dp)
        )
    }
}

@Composable
fun SuggestionCard(
    suggestion: GTOSuggestion?,
    isSolving: Boolean,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = Color(0xFF1A237E),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            when {
                isSolving -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        CircularProgressIndicator(
                            color = Color.White,
                            modifier = Modifier.height(24.dp).width(24.dp),
                            strokeWidth = 2.dp
                        )
                        Spacer(Modifier.width(12.dp))
                        Text(
                            text = "Solving...",
                            color = Color.White.copy(alpha = 0.7f),
                            fontSize = 15.sp
                        )
                    }
                }
                suggestion == null -> {
                    Text(
                        text = "Lock a hand to get suggestions",
                        color = Color.White.copy(alpha = 0.5f),
                        fontSize = 14.sp
                    )
                }
                else -> {
                    // Action label
                    val actionColor = when (suggestion.action.lowercase()) {
                        "fold" -> foldColor
                        "call", "check" -> callColor
                        else -> raiseColor
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = suggestion.action.uppercase(),
                            color = actionColor,
                            fontWeight = FontWeight.ExtraBold,
                            fontSize = 28.sp
                        )
                        suggestion.raiseSize?.let { size ->
                            Spacer(Modifier.width(8.dp))
                            Text(
                                text = "${size}x",
                                color = actionColor.copy(alpha = 0.8f),
                                fontSize = 20.sp
                            )
                        }
                        Spacer(Modifier.weight(1f))
                        if (suggestion.ev != 0.0) {
                            Column(horizontalAlignment = Alignment.End) {
                                Text(
                                    text = "EV",
                                    color = Color.White.copy(alpha = 0.5f),
                                    fontSize = 10.sp
                                )
                                Text(
                                    text = "%.2f".format(suggestion.ev),
                                    color = Color.White,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }
                    }

                    Spacer(Modifier.height(16.dp))

                    // Weight bars
                    WeightBar("Fold", suggestion.foldWeight, foldColor)
                    Spacer(Modifier.height(6.dp))
                    WeightBar("Call", suggestion.callWeight, callColor)
                    Spacer(Modifier.height(6.dp))
                    WeightBar("Raise", suggestion.raiseWeight, raiseColor)

                    // Confidence
                    if (suggestion.confidence > 0) {
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = "Confidence: ${(suggestion.confidence * 100).toInt()}%",
                            color = Color.White.copy(alpha = 0.5f),
                            fontSize = 11.sp
                        )
                    }

                    // Reasoning
                    if (suggestion.reasoning.isNotEmpty()) {
                        Spacer(Modifier.height(12.dp))
                        Text(
                            text = suggestion.reasoning,
                            color = Color.White.copy(alpha = 0.75f),
                            fontSize = 13.sp,
                            lineHeight = 18.sp
                        )
                    }
                }
            }
        }
    }
}
