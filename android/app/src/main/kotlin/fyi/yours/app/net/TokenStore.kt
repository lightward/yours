package fyi.yours.app.net

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

// The one secret this app holds: the bearer token that carries the google_id
// (and with it, the ability to decrypt this resonance's data server-side).
// Encrypted at rest with the Android Keystore — the counterpart of the iOS
// keychain.
class TokenStore(context: Context) {
    private val prefs = run {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "yours-credentials",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    var token: String?
        get() = prefs.getString("native-token", null)
        set(value) {
            prefs.edit().apply {
                if (value == null) remove("native-token") else putString("native-token", value)
            }.apply()
        }
}
