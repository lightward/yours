package fyi.yours.app

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// GET /native/state — everything the client needs to render itself.
// See PROTOCOL.md.
@Serializable
data class UniverseState(
    @SerialName("universe_day") val universeDay: Int,
    @SerialName("universe_time") var universeTime: String,
    val narrative: List<ChatMessage> = emptyList(),
    val textarea: String? = null,
    @SerialName("obfuscated_email") val obfuscatedEmail: String? = null,
    @SerialName("subscription_active") val subscriptionActive: Boolean = false,
    val subscription: SubscriptionDetails? = null
) {
    // The "1 day" / "day 2" pun, preserved (non-breaking space, like the
    // web's universe_day_with_units)
    val dayWithUnits: String get() = dayWithUnits(universeDay)

    companion object {
        fun dayWithUnits(day: Int): String =
            if (day == 1) "1 day" else "day $day"
    }
}

@Serializable
data class SubscriptionDetails(
    val status: String,
    @SerialName("cancel_at_period_end") val cancelAtPeriodEnd: Boolean = false,
    @SerialName("current_period_end") val currentPeriodEnd: String? = null,
    val amount: Int,
    val currency: String = "usd",
    val interval: String = "month"
)

// One entry in the narrative, in the Lightward AI chat_log shape:
// { role:, content: [{ type: "text", text: }] }
@Serializable
data class ChatMessage(
    val role: String,
    val content: List<ContentBlock>
) {
    @Serializable
    data class ContentBlock(val type: String = "text", val text: String)

    val text: String get() = content.joinToString("\n") { it.text }

    companion object {
        fun user(text: String) = ChatMessage("user", listOf(ContentBlock("text", text)))
    }
}

val YoursJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
}
