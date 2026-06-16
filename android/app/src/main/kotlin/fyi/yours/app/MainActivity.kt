package fyi.yours.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import fyi.yours.app.ui.ChatScreen
import fyi.yours.app.ui.LandingScreen
import fyi.yours.app.ui.LockedScreen
import fyi.yours.app.ui.SleepScreen

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        model.configure(intent.extras)
        intent.data?.let { handleAuthCallback() }

        setContent {
            val colors = model.themePreference.colors()
            CompositionLocalProvider(LocalYoursColors provides colors) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(colors.background)
                ) {
                    RootScreen(model)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAuthCallback()
    }

    // yours://auth?code=... — the web sign-in flow handing the session back
    private fun handleAuthCallback() {
        val uri = intent.data ?: return
        if (uri.scheme == "yours" && uri.host == "auth") {
            uri.getQueryParameter("code")?.let { model.completeAuth(it) }
        }
    }
}

@Composable
fun RootScreen(model: AppModel) {
    val colors = LocalYoursColors.current
    when (model.phase) {
        AppModel.Phase.LOADING -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = colors.accent)
        }
        AppModel.Phase.LANDING -> LandingScreen(model)
        AppModel.Phase.CHAT -> ChatScreen(model)
        AppModel.Phase.LOCKED -> LockedScreen(model)
        AppModel.Phase.SLEEPING -> SleepScreen(model)
    }
}
