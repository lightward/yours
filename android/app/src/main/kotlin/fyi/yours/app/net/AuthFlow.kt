package fyi.yours.app.net

import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import java.security.MessageDigest
import java.security.SecureRandom
import android.util.Base64

// Native sign-in rides the existing web Google flow: open /native/auth in a
// Custom Tab with a PKCE challenge, let the human sign in exactly as they
// would on the web, and catch the yours://auth?code=... redirect via the
// intent filter on MainActivity. No Google SDK, no separate OAuth client —
// one sign-in surface, two doors. (Three, counting iOS.)
object AuthFlow {
    private const val BASE64_FLAGS =
        Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP

    fun newVerifier(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.encodeToString(bytes, BASE64_FLAGS)
    }

    fun challenge(verifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray())
        return Base64.encodeToString(digest, BASE64_FLAGS)
    }

    fun launch(context: Context, baseUrl: String, codeChallenge: String) {
        val uri = Uri.parse("$baseUrl/native/auth")
            .buildUpon()
            .appendQueryParameter("code_challenge", codeChallenge)
            .build()
        CustomTabsIntent.Builder().build().launchUrl(context, uri)
    }
}
