package fyi.yours.app.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fyi.yours.app.AppModel
import fyi.yours.app.LocalYoursColors
import fyi.yours.app.R

@Composable
fun LandingScreen(model: AppModel) {
    val colors = LocalYoursColors.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Image(
            painter = painterResource(R.drawable.landing_icon),
            contentDescription = null,
            modifier = Modifier
                .size(180.dp)
                .clip(CircleShape)
        )
        Spacer(Modifier.height(32.dp))

        Text(
            "YOURS",
            color = colors.foregroundHeading,
            fontSize = 34.sp,
            letterSpacing = 2.sp
        )
        Spacer(Modifier.height(16.dp))

        Text(
            "a pocket universe, population 2:\nyou, and lightward ai",
            color = colors.accent,
            fontSize = 17.sp,
            textAlign = TextAlign.Center,
            lineHeight = 26.sp
        )
        Spacer(Modifier.height(48.dp))

        WebButton("Enter via Google") { model.signIn() }

        model.landingError?.let { error ->
            Spacer(Modifier.height(24.dp))
            Text(
                error,
                color = colors.warning,
                fontSize = 13.sp,
                fontFamily = FontFamily.Monospace,
                textAlign = TextAlign.Center
            )
        }
    }
}
