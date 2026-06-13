package fyi.yours.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.foundation.clickable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fyi.yours.app.AppModel
import fyi.yours.app.LocalYoursColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

// The night: a native cousin of the web's WebGL aura — drifting cyan/magenta
// light while the integration harmonic is derived server-side. Polls until
// universe_time moves, holds the same minimum five seconds as the web, then
// offers Continue. Mirrors ios/Yours/Views/SleepView.swift.
@Composable
fun SleepScreen(model: AppModel) {
    val colors = LocalYoursColors.current
    val scope = rememberCoroutineScope()

    var dots by remember { mutableStateOf("") }
    var finished by remember { mutableStateOf(false) }
    var auraVisible by remember { mutableStateOf(true) }
    val auraAlpha by animateFloatAsState(
        targetValue = if (auraVisible) 1f else 0f,
        animationSpec = tween(1000),
        label = "auraFade"
    )

    LaunchedEffect(Unit) {
        val states = listOf("", ".", "..", "...")
        var index = 0
        while (!finished) {
            dots = states[index]
            index = (index + 1) % states.size
            delay(500)
        }
    }

    LaunchedEffect(Unit) {
        val start = System.currentTimeMillis()
        while (true) {
            if (model.sleepIntegrationFinished()) break
            delay(1000)
        }
        // Match the web's minimum display: the night deserves its moment
        val elapsed = System.currentTimeMillis() - start
        if (elapsed < 5000) delay(5000 - elapsed)
        auraVisible = false
        delay(1000)
        finished = true
    }

    Box(Modifier.fillMaxSize()) {
        Aura(Modifier.fillMaxSize().alpha(auraAlpha))

        if (finished) {
            Text(
                "Continue",
                color = colors.accent,
                fontFamily = FontFamily.Monospace,
                fontSize = 14.sp,
                modifier = Modifier
                    .align(Alignment.Center)
                    .clickable { scope.launch { model.refreshState() } }
            )
        } else {
            Text(
                "Integrating ${model.state?.dayWithUnits ?: "the day"}$dots",
                color = colors.accentActive,
                fontFamily = FontFamily.Monospace,
                fontSize = 14.sp,
                modifier = Modifier.align(Alignment.Center)
            )
        }
    }
}

// Two soft fields of light, one cyan, one magenta, drifting slowly past each
// other.
@Composable
private fun Aura(modifier: Modifier = Modifier) {
    var t by remember { mutableDoubleStateOf(0.0) }

    LaunchedEffect(Unit) {
        val startNanos = withFrameNanos { it }
        while (true) {
            withFrameNanos { now ->
                t = (now - startNanos) / 1_000_000_000.0
            }
        }
    }

    Canvas(modifier.blur(70.dp)) {
        val minSide = min(size.width, size.height)

        fun blob(color: Color, speed: Double, phase: Double, radius: Float) {
            val cx = size.width * (0.5f + 0.28f * sin(t * speed + phase).toFloat())
            val cy = size.height * (0.45f + 0.22f * cos(t * speed * 1.3 + phase).toFloat())
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(color.copy(alpha = 0.55f), color.copy(alpha = 0f)),
                    center = Offset(cx, cy),
                    radius = radius
                ),
                radius = radius,
                center = Offset(cx, cy)
            )
        }

        blob(Color(0xFF00E5FF), 0.11, 0.0, minSide * 0.55f)
        blob(Color(0xFFFF66FF), 0.07, 2.4, minSide * 0.5f)
    }
}
