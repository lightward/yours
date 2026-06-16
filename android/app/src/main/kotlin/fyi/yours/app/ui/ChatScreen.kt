package fyi.yours.app.ui

import android.content.Intent
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fyi.yours.app.AppModel
import fyi.yours.app.LocalYoursColors
import fyi.yours.app.UniverseState
import fyi.yours.app.support.MarkdownLite
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun ChatScreen(model: AppModel) {
    val colors = LocalYoursColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()

    var showSettings by remember { mutableStateOf(false) }
    var showExitConfirm by remember { mutableStateOf(false) }
    var showSleepConfirm by remember { mutableStateOf(false) }

    val nextDay = (model.state?.universeDay ?: 1) + 1

    // Ride the bottom edge as content grows (streaming) — mirrors the web's
    // scrollIntoView and the iOS bottom anchor
    LaunchedEffect(scrollState.maxValue) {
        scrollState.scrollTo(scrollState.maxValue)
    }

    Column(
        Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .imePadding()
    ) {
        // Header
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "Yours: ${model.state?.dayWithUnits ?: ""}",
                color = colors.accent,
                fontFamily = FontFamily.Monospace,
                fontSize = 14.sp
            )
            Spacer(Modifier.weight(1f))
            model.state?.obfuscatedEmail?.let { email ->
                Text(
                    email,
                    color = colors.accent,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 14.sp,
                    modifier = Modifier.clickable { showSettings = true }
                )
            }
            Text(
                "Exit",
                color = colors.accentActive,
                fontFamily = FontFamily.Monospace,
                fontSize = 14.sp,
                modifier = Modifier.clickable { showExitConfirm = true }
            )
        }
        Box(
            Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(colors.border)
        )

        // Narrative
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(scrollState)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            model.messages.forEach { message ->
                MessageView(message)
            }
            model.notice?.let { notice ->
                NoticeView(notice) { model.noticeAction() }
            }
        }

        // Composer
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            var focused by remember { mutableStateOf(false) }
            Box(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(colors.userMessageBg)
                    .alpha(if (model.isWaiting) 0.5f else 1f)
            ) {
                BasicTextField(
                    value = model.composerText,
                    onValueChange = {
                        model.composerText = it
                        model.composerChanged()
                    },
                    enabled = !model.isWaiting,
                    textStyle = TextStyle(
                        color = colors.foreground,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 16.sp
                    ),
                    cursorBrush = SolidColor(colors.accentActive),
                    maxLines = 8,
                    decorationBox = { inner ->
                        Box(Modifier.padding(12.dp)) {
                            if (model.composerText.isEmpty()) {
                                Text(
                                    "Type your message...",
                                    color = colors.foreground.copy(alpha = 0.4f),
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = 16.sp
                                )
                            }
                            inner()
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .onFocusChanged { focused = it.isFocused }
                )
                if (focused) {
                    Box(Modifier.matchParentSize(), contentAlignment = Alignment.CenterStart) {
                        Box(
                            Modifier
                                .width(3.dp)
                                .fillMaxHeight()
                                .background(colors.accentActive)
                        )
                    }
                }
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(20.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .alpha(if (model.isWaiting) 0.5f else 1f)
            ) {
                WebButton(
                    "Send",
                    enabled = !model.isWaiting && model.composerText.isNotBlank()
                ) { model.send() }

                if (model.state?.subscriptionActive == true) {
                    Text(
                        "Move to ${UniverseState.dayWithUnits(nextDay)}",
                        color = colors.accentActive,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 13.sp,
                        modifier = Modifier.clickable(enabled = !model.isWaiting) { showSleepConfirm = true }
                    )
                } else {
                    Text(
                        "Subscribe for ${UniverseState.dayWithUnits(nextDay)}",
                        color = colors.accent,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 13.sp,
                        modifier = Modifier.clickable(enabled = !model.isWaiting) { showSettings = true }
                    )
                }

                Spacer(Modifier.weight(1f))

                Text(
                    "Save",
                    color = colors.foreground.copy(alpha = 0.6f),
                    fontFamily = FontFamily.Monospace,
                    fontSize = 13.sp,
                    modifier = Modifier.clickable(enabled = !model.isWaiting) {
                        scope.launch {
                            runCatching {
                                val (text, filename) = model.exportNarrative()
                                val send = Intent(Intent.ACTION_SEND).apply {
                                    type = "text/plain"
                                    putExtra(Intent.EXTRA_TEXT, text)
                                    putExtra(Intent.EXTRA_TITLE, filename)
                                }
                                context.startActivity(Intent.createChooser(send, filename))
                            }
                        }
                    }
                )
            }
        }
    }

    if (showSettings) {
        SettingsSheet(model) { showSettings = false }
    }

    if (showExitConfirm) {
        AlertDialog(
            onDismissRequest = { showExitConfirm = false },
            containerColor = colors.assistantMessageBg,
            title = { Text("Exit?", color = colors.foregroundHeading) },
            text = {
                Text(
                    "Your universe stays right where it is — sign back in any time.",
                    color = colors.foreground
                )
            },
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

    if (showSleepConfirm) {
        AlertDialog(
            onDismissRequest = { showSleepConfirm = false },
            containerColor = colors.assistantMessageBg,
            title = {
                Text(
                    "Ready to move to ${UniverseState.dayWithUnits(nextDay)}?",
                    color = colors.foregroundHeading
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showSleepConfirm = false
                    model.beginSleepAsync()
                }) { Text("Move to ${UniverseState.dayWithUnits(nextDay)}", color = colors.accentActive) }
            },
            dismissButton = {
                TextButton(onClick = { showSleepConfirm = false }) {
                    Text("Not yet", color = colors.foreground)
                }
            }
        )
    }
}

@Composable
fun MessageView(message: AppModel.DisplayMessage) {
    val colors = LocalYoursColors.current
    val isUser = message.role == "user"

    Box(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(if (isUser) colors.userMessageBg else colors.assistantMessageBg)
    ) {
        if (message.isPulsing) {
            var dotCount by remember { mutableIntStateOf(1) }
            LaunchedEffect(Unit) {
                while (true) {
                    delay(500)
                    dotCount = (dotCount % 3) + 1
                }
            }
            val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(
                initialValue = 0.4f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    tween(750, easing = LinearEasing),
                    RepeatMode.Reverse
                ),
                label = "pulseAlpha"
            )
            Text(
                ".".repeat(dotCount),
                color = colors.foreground,
                fontFamily = FontFamily.Monospace,
                fontSize = 16.sp,
                fontWeight = FontWeight.Light,
                modifier = Modifier
                    .padding(16.dp)
                    .alpha(pulse)
            )
        } else {
            val segments = if (message.isComplete) {
                MarkdownLite.finalSegments(message.text)
            } else {
                MarkdownLite.streamingSegments(message.text)
            }
            Text(
                annotatedSegments(segments),
                color = colors.foreground,
                fontSize = 16.sp,
                lineHeight = 26.sp,
                modifier = Modifier.padding(16.dp)
            )
        }

        if (isUser) {
            Box(Modifier.matchParentSize(), contentAlignment = Alignment.CenterStart) {
                Box(
                    Modifier
                        .width(3.dp)
                        .fillMaxHeight()
                        .background(colors.accent)
                )
            }
        }
    }
}

@Composable
fun NoticeView(notice: AppModel.Notice, onAction: () -> Unit) {
    val colors = LocalYoursColors.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(colors.assistantMessageBg)
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            notice.message,
            color = colors.foreground,
            fontFamily = FontFamily.Monospace,
            fontSize = 14.sp
        )
        WebButton(notice.actionLabel, onClick = onAction)
    }
}
