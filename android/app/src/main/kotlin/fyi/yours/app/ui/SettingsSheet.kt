package fyi.yours.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fyi.yours.app.AppModel
import fyi.yours.app.LocalYoursColors
import fyi.yours.app.ThemePreference
import fyi.yours.app.UniverseState
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(model: AppModel, onDismiss: () -> Unit) {
    val colors = LocalYoursColors.current
    var showStartOverConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { model.loadSettingsSubscription() }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.background
    ) {
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 48.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp)
        ) {
            Text(
                "SETTINGS",
                color = colors.foregroundHeading,
                fontSize = 26.sp,
                letterSpacing = 1.5.sp
            )

            Section("DISPLAY") {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ThemePreference.entries.forEach { preference ->
                        WebButton(
                            preference.label,
                            color = if (model.themePreference == preference) colors.accentActive else colors.accent
                        ) { model.setTheme(preference) }
                    }
                }
            }

            Section("SUBSCRIPTION") {
                val subscription = model.settingsSubscription
                when {
                    subscription != null -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        DetailRow(
                            "Status:",
                            subscription.status.replaceFirstChar { it.uppercase() } +
                                if (subscription.cancelAtPeriodEnd) " (canceling at period end)" else ""
                        )
                        DetailRow("Amount:", "$${subscription.amount / 100} / ${subscription.interval}")
                        subscription.currentPeriodEnd?.let { end ->
                            DetailRow(
                                if (subscription.cancelAtPeriodEnd) "Access ends:" else "Next billing date:",
                                formatDate(end)
                            )
                        }
                        Text(
                            "Manage your subscription on the web, where it lives.",
                            color = colors.foreground.copy(alpha = 0.6f),
                            fontSize = 15.sp
                        )
                    }

                    model.state?.subscriptionActive == true -> Text(
                        "Active. Manage your subscription on the web, where it lives.",
                        color = colors.foreground,
                        fontSize = 15.sp
                    )

                    else -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(
                            "How much does \"new\" cost for you?",
                            color = colors.foreground,
                            fontSize = 16.sp
                        )
                        Text(
                            "Subscriptions live on the web — visit yours.fyi in your browser, then come back and pick up where you left off.",
                            color = colors.foreground.copy(alpha = 0.6f),
                            fontSize = 15.sp
                        )
                        WebButton("I've subscribed — check again") {
                            model.refresh()
                            onDismiss()
                        }
                    }
                }
            }

            Section("START OVER") {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        "Begin at the beginning, at the dawn of ${UniverseState.dayWithUnits(1)}, with no trace of what was.",
                        color = colors.foreground,
                        fontSize = 16.sp
                    )
                    if (model.state?.subscriptionActive == true) {
                        Text(
                            "Start over",
                            color = colors.accentActive,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 14.sp,
                            modifier = Modifier.clickable { showStartOverConfirm = true }
                        )
                        Text("There is no undo.", color = colors.warning, fontSize = 14.sp)
                    } else {
                        Text("This unlocks for subscribers.", color = colors.warning, fontSize = 14.sp)
                    }
                }
            }
        }
    }

    if (showStartOverConfirm) {
        AlertDialog(
            onDismissRequest = { showStartOverConfirm = false },
            containerColor = colors.assistantMessageBg,
            title = { Text("Start over?", color = colors.foregroundHeading) },
            text = {
                Text(
                    "There is no undo. This does not affect your subscription.",
                    color = colors.foreground
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showStartOverConfirm = false
                    model.startOver()
                    onDismiss()
                }) { Text("Start over", color = colors.error) }
            },
            dismissButton = {
                TextButton(onClick = { showStartOverConfirm = false }) {
                    Text("Keep going", color = colors.foreground)
                }
            }
        )
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    val colors = LocalYoursColors.current
    Column(verticalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.fillMaxWidth()) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(colors.border)
        )
        Spacer(Modifier.height(6.dp))
        Text(
            title,
            color = colors.foregroundHeading,
            fontSize = 18.sp,
            letterSpacing = 1.sp
        )
        content()
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    val colors = LocalYoursColors.current
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(label, color = colors.foreground.copy(alpha = 0.6f), fontSize = 15.sp)
        Text(value, color = colors.foreground, fontSize = 15.sp)
    }
}

private fun formatDate(iso: String): String = runCatching {
    OffsetDateTime.parse(iso).format(DateTimeFormatter.ofPattern("MMMM d, yyyy"))
}.getOrDefault(iso)
