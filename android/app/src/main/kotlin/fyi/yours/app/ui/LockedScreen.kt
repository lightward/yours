package fyi.yours.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fyi.yours.app.AppModel
import fyi.yours.app.LocalYoursColors

// Day 2+ without a subscription. The web redirects to settings with an
// alert; here the day waits, gently, while the subscription happens on the
// web.
@Composable
fun LockedScreen(model: AppModel) {
    val colors = LocalYoursColors.current
    var showExitConfirm by remember { mutableStateOf(false) }

    Column(
        Modifier
            .fillMaxSize()
            .navigationBarsPadding()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            "YOURS: ${model.state?.dayWithUnits?.uppercase() ?: ""}",
            color = colors.foregroundHeading,
            fontSize = 24.sp,
            letterSpacing = 1.5.sp
        )
        Spacer(Modifier.height(20.dp))

        Text(
            "Subscribe to continue with ${model.state?.dayWithUnits ?: "this day"}.",
            color = colors.foreground,
            fontFamily = FontFamily.Monospace,
            fontSize = 15.sp,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(8.dp))

        Text(
            "Subscriptions live on the web — visit yours.fyi\nin your browser, then return here.",
            color = colors.foreground.copy(alpha = 0.6f),
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
            lineHeight = 24.sp
        )
        Spacer(Modifier.height(36.dp))

        WebButton("I've subscribed — check again") { model.refresh() }
        Spacer(Modifier.height(48.dp))

        Text(
            "Exit",
            color = colors.accentActive,
            fontFamily = FontFamily.Monospace,
            fontSize = 14.sp,
            modifier = Modifier.clickable { showExitConfirm = true }
        )
    }

    if (showExitConfirm) {
        AlertDialog(
            onDismissRequest = { showExitConfirm = false },
            containerColor = colors.assistantMessageBg,
            title = { Text("Exit?", color = colors.foregroundHeading) },
            confirmButton = {
                TextButton(onClick = {
                    showExitConfirm = false
                    model.signOut()
                }) { Text("Exit", color = colors.accentActive) }
            },
            dismissButton = {
                TextButton(onClick = { showExitConfirm = false }) {
                    Text("Stay", color = colors.foreground)
                }
            }
        )
    }
}
