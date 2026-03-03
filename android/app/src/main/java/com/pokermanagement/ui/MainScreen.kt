package com.pokermanagement.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pokermanagement.viewmodel.MainUiState

private val bgColor = Color(0xFF0D0D1A)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    uiState: MainUiState,
    onStartMic: () -> Unit,
    onStopMic: () -> Unit,
    onResetState: () -> Unit,
    onSaveSetting: (String, String) -> Unit,
    onVideoInputChanged: (String) -> Unit
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    var showSettings by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = bgColor,
        topBar = {
            Column {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Connection status
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(
                                    if (uiState.isStreaming) Color(0xFF4CAF50) else Color(0xFF9E9E9E)
                                )
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(
                            text = uiState.connectionStatus,
                            color = Color.White.copy(alpha = 0.7f),
                            fontSize = 12.sp
                        )
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (!uiState.modelLoaded) {
                            Surface(
                                color = Color(0xFFF57F17).copy(alpha = 0.2f),
                                shape = RoundedCornerShape(8.dp)
                            ) {
                                Text(
                                    text = "Mock Mode",
                                    color = Color(0xFFFFC107),
                                    fontSize = 11.sp,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                                )
                            }
                        }
                        FilledTonalIconButton(
                            onClick = { showSettings = true },
                            colors = IconButtonDefaults.filledTonalIconButtonColors(
                                containerColor = Color.White.copy(alpha = 0.1f),
                                contentColor = Color.White
                            )
                        ) {
                            Icon(Icons.Default.Settings, contentDescription = "Settings")
                        }
                    }
                }

                TabRow(
                    selectedTabIndex = selectedTab,
                    containerColor = bgColor,
                    contentColor = Color.White,
                    indicator = { tabPositions ->
                        TabRowDefaults.SecondaryIndicator(
                            modifier = Modifier.tabIndicatorOffset(tabPositions[selectedTab]),
                            color = Color(0xFF7C83FD)
                        )
                    }
                ) {
                    listOf("Live", "History").forEachIndexed { idx, title ->
                        Tab(
                            selected = selectedTab == idx,
                            onClick = { selectedTab = idx },
                            text = {
                                Text(
                                    text = title,
                                    color = if (selectedTab == idx) Color.White else Color.White.copy(alpha = 0.5f),
                                    fontWeight = if (selectedTab == idx) FontWeight.SemiBold else FontWeight.Normal
                                )
                            }
                        )
                    }
                }
            }
        }
    ) { paddingValues ->
        when (selectedTab) {
            0 -> LiveTab(
                uiState = uiState,
                onStartMic = onStartMic,
                onStopMic = onStopMic,
                onResetState = onResetState,
                modifier = Modifier.padding(paddingValues)
            )
            1 -> HistoryScreen(
                hands = uiState.handHistory,
                modifier = Modifier.padding(paddingValues)
            )
        }

        if (showSettings) {
            SettingsSheet(
                useMockSolver = uiState.useMockSolver,
                solverEndpoint = uiState.solverEndpoint,
                solverApiKey = uiState.solverApiKey,
                selectedVideoInput = uiState.selectedVideoInput,
                onDismiss = { showSettings = false },
                onSaveSetting = onSaveSetting,
                onVideoInputChanged = { input ->
                    onVideoInputChanged(input)
                    showSettings = false
                }
            )
        }
    }
}

@Composable
fun LiveTab(
    uiState: MainUiState,
    onStartMic: () -> Unit,
    onStopMic: () -> Unit,
    onResetState: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // Poker table card
        PokerTableCard(
            state = uiState.currentPokerState,
            isLocked = uiState.isStateLocked
        )

        // GTO suggestion
        SuggestionCard(
            suggestion = uiState.latestSuggestion,
            isSolving = uiState.isSolving
        )

        // Voice input row
        Surface(
            color = Color(0xFF1E1E2E),
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(
                            text = "Voice Input",
                            color = Color.White,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium
                        )
                        if (uiState.transcribedText.isNotEmpty()) {
                            Text(
                                text = "\"${uiState.transcribedText}\"",
                                color = Color.White.copy(alpha = 0.6f),
                                fontSize = 12.sp
                            )
                        }
                        uiState.parsedPotSize?.let {
                            Text(
                                text = "Pot: ${"%.0f".format(it)} BB",
                                color = Color(0xFF66BB6A),
                                fontSize = 12.sp
                            )
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilledIconButton(
                            onClick = onResetState,
                            colors = IconButtonDefaults.filledIconButtonColors(
                                containerColor = Color.White.copy(alpha = 0.15f),
                                contentColor = Color.White
                            )
                        ) {
                            Icon(Icons.Default.Refresh, contentDescription = "Reset State")
                        }
                        FilledIconButton(
                            onClick = if (uiState.isListening) onStopMic else onStartMic,
                            colors = IconButtonDefaults.filledIconButtonColors(
                                containerColor = if (uiState.isListening) Color(0xFFEF5350) else Color(0xFF7C83FD),
                                contentColor = Color.White
                            )
                        ) {
                            Icon(
                                imageVector = if (uiState.isListening) Icons.Default.MicOff else Icons.Default.Mic,
                                contentDescription = if (uiState.isListening) "Stop Listening" else "Start Listening"
                            )
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(16.dp))
    }
}
