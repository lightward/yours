package fyi.yours.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fyi.yours.app.LocalYoursColors
import fyi.yours.app.support.MarkdownLite

// The web's button: borderLight background, accent text, 3px accent left
// border, 4pt radius. Mirrors WebButtonStyle in the iOS client.
@Composable
fun WebButton(
    label: String,
    color: Color = LocalYoursColors.current.accent,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    val colors = LocalYoursColors.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()

    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(if (pressed) color else colors.borderLight)
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = enabled,
                onClick = onClick
            )
    ) {
        Text(
            label,
            color = if (pressed) colors.background else color,
            fontSize = 16.sp,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 9.dp)
        )
        Box(Modifier.matchParentSize(), contentAlignment = Alignment.CenterStart) {
            Box(
                Modifier
                    .width(3.dp)
                    .fillMaxHeight()
                    .background(color)
            )
        }
    }
}

// Builds styled text from MarkdownLite segments — dimmed indicators, real
// bold/italic. The mono face stands in for Lightward Favorit Mono.
@Composable
fun annotatedSegments(segments: List<MarkdownLite.Segment>): AnnotatedString {
    val colors = LocalYoursColors.current
    return buildAnnotatedString {
        for (segment in segments) {
            withStyle(
                SpanStyle(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = if (segment.bold) FontWeight.Bold else FontWeight.Light,
                    fontStyle = if (segment.italic) FontStyle.Italic else FontStyle.Normal,
                    color = if (segment.isIndicator) colors.foreground.copy(alpha = 0.7f) else Color.Unspecified
                )
            ) {
                append(segment.text)
            }
        }
    }
}
