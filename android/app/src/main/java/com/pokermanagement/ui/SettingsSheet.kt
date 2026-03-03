package com.pokermanagement.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(
    useMockSolver: Boolean,
    solverEndpoint: String,
    solverApiKey: String,
    selectedVideoInput: String,
    onDismiss: () -> Unit,
    onSaveSetting: (String, String) -> Unit,
    onVideoInputChanged: (String) -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var endpointValue by remember { mutableStateOf(solverEndpoint) }
    var apiKeyValue by remember { mutableStateOf(solverApiKey) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF1E1E2E)
    ) {
        Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
            Text(
                text = "Settings",
                color = Color.White,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold
            )

            Spacer(Modifier.height(20.dp))

            // Video source picker
            Text(text = "Video Source", color = Color.White.copy(alpha = 0.7f), fontSize = 13.sp)
            Spacer(Modifier.height(8.dp))
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                listOf("camera" to "Camera", "webrtc" to "WebRTC").forEachIndexed { idx, (key, label) ->
                    SegmentedButton(
                        selected = selectedVideoInput == key,
                        onClick = { onVideoInputChanged(key) },
                        shape = SegmentedButtonDefaults.itemShape(idx, 2)
                    ) {
                        Text(label)
                    }
                }
            }

            Spacer(Modifier.height(20.dp))

            // Mock solver toggle
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(text = "Use Mock Solver", color = Color.White, fontSize = 15.sp)
                    Text(
                        text = "Returns hardcoded suggestions without backend",
                        color = Color.White.copy(alpha = 0.5f),
                        fontSize = 12.sp
                    )
                }
                Switch(
                    checked = useMockSolver,
                    onCheckedChange = { onSaveSetting("useMockSolver", it.toString()) }
                )
            }

            Spacer(Modifier.height(16.dp))

            // Endpoint field
            Text(text = "Solver Endpoint", color = Color.White.copy(alpha = 0.7f), fontSize = 13.sp)
            Spacer(Modifier.height(6.dp))
            OutlinedTextField(
                value = endpointValue,
                onValueChange = { endpointValue = it },
                modifier = Modifier.fillMaxWidth(),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White.copy(alpha = 0.8f),
                    focusedBorderColor = Color(0xFF7C83FD),
                    unfocusedBorderColor = Color.White.copy(alpha = 0.2f),
                    cursorColor = Color.White
                ),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(
                    onDone = { onSaveSetting("solverEndpoint", endpointValue) }
                ),
                singleLine = true,
                placeholder = { Text("http://0.0.0.0:8000", color = Color.White.copy(alpha = 0.3f)) }
            )

            Spacer(Modifier.height(12.dp))

            // API key field
            Text(text = "API Key", color = Color.White.copy(alpha = 0.7f), fontSize = 13.sp)
            Spacer(Modifier.height(6.dp))
            OutlinedTextField(
                value = apiKeyValue,
                onValueChange = { apiKeyValue = it },
                modifier = Modifier.fillMaxWidth(),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White.copy(alpha = 0.8f),
                    focusedBorderColor = Color(0xFF7C83FD),
                    unfocusedBorderColor = Color.White.copy(alpha = 0.2f),
                    cursorColor = Color.White
                ),
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(
                    onDone = { onSaveSetting("solverApiKey", apiKeyValue) }
                ),
                singleLine = true,
                placeholder = { Text("Bearer token", color = Color.White.copy(alpha = 0.3f)) }
            )

            Spacer(Modifier.height(32.dp))
        }
    }
}
