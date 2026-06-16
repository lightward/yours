package fyi.yours.app

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

// The web app's palette (app/assets/stylesheets/application.css). Dark is
// the default theme there and here.
data class YoursColors(
    val background: Color,
    val foreground: Color,
    val foregroundHeading: Color,
    val border: Color,
    val borderLight: Color,
    val accent: Color,
    val accentActive: Color,
    val success: Color,
    val warning: Color,
    val error: Color,
    val userMessageBg: Color,
    val assistantMessageBg: Color
)

val DarkColors = YoursColors(
    background = Color(0xFF0A0A0F),
    foreground = Color(0xFFB7B3AC),
    foregroundHeading = Color(0xFFCFCCC6),
    border = Color(0xFF1A1A2E),
    borderLight = Color(0xFF2A2A3E),
    accent = Color(0xFF00E5FF),
    accentActive = Color(0xFFFF66FF),
    success = Color(0xFF00FFA3),
    warning = Color(0xFFFFD700),
    error = Color(0xFFFF0080),
    userMessageBg = Color(0xFF1A1A3E),
    assistantMessageBg = Color(0xFF0F0F1F)
)

val LightColors = YoursColors(
    background = Color(0xFFF5F5F0),
    foreground = Color(0xFF3D3D3D),
    foregroundHeading = Color(0xFF1A1A1A),
    border = Color(0xFFE0E0D8),
    borderLight = Color(0xFFD0D0C8),
    accent = Color(0xFF0088AA),
    accentActive = Color(0xFFCC44CC),
    success = Color(0xFF00AA77),
    warning = Color(0xFFCC9900),
    error = Color(0xFFCC0066),
    userMessageBg = Color(0xFFE8E8E0),
    assistantMessageBg = Color(0xFFF0F0E8)
)

val LocalYoursColors = staticCompositionLocalOf { DarkColors }

// Mirrors the web's theme setting: dark default, light, or follow the system
enum class ThemePreference(val label: String) {
    DARK("Dark"), LIGHT("Light"), AUTO("Auto");

    @Composable
    fun colors(): YoursColors = when (this) {
        DARK -> DarkColors
        LIGHT -> LightColors
        AUTO -> if (isSystemInDarkTheme()) DarkColors else LightColors
    }

    companion object {
        fun from(raw: String?): ThemePreference =
            entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: DARK
    }
}
