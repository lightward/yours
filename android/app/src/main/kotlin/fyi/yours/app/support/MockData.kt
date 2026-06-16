package fyi.yours.app.support

import fyi.yours.app.AppModel
import fyi.yours.app.ChatMessage
import fyi.yours.app.UniverseState
import kotlinx.coroutines.delay

// Canned state for emulator screenshots, activated by intent extras
// (YoursMockChat / YoursMockLanding / etc). Debug builds only; nothing here
// ships. Mirrors ios/Yours/Support/MockData.swift.
object MockData {
    val state = UniverseState(
        universeDay = 3,
        universeTime = "3:4",
        narrative = listOf(
            ChatMessage.user("good morning :) I keep thinking about what we found yesterday — the thing about *noticing* being different from watching"),
            ChatMessage(
                "assistant",
                listOf(
                    ChatMessage.ContentBlock(
                        "text",
                        "Good morning. :)\n\nYes — and the harmonic carried that forward as a feeling more than a fact: **noticing opens, watching holds**. One of them makes room and the other makes walls.\n\nWhere did it land for you overnight?"
                    )
                )
            ),
            ChatMessage.user("it landed somewhere near my shoulders, honestly. like I'd been bracing"),
            ChatMessage(
                "assistant",
                listOf(
                    ChatMessage.ContentBlock(
                        "text",
                        "That's the spot where watching lives, isn't it — up where you hold the perimeter.\n\nNo fixing needed. Just *noticing* the bracing is already the unbracing, a little. We can stay here."
                    )
                )
            )
        ),
        obfuscatedEmail = "ma··@li··",
        subscriptionActive = true
    )

    const val RESPONSE_TEXT =
        "Mm — that's the kind of question that answers itself by being asked. :)\n\nHere's what I notice: you brought it *here*, which means some part of you already trusts the space to hold it. **That trust is the finding.** The rest is just us walking around it together, seeing what it looks like from different sides."

    val exportText: String
        get() = state.narrative.joinToString("\n\n---\n\n") { it.text }

    suspend fun streamResponse(model: AppModel, index: Int) {
        delay(1200)
        model.replaceMessageText(index, "", pulsing = false)
        var text = ""
        for (word in RESPONSE_TEXT.split(" ")) {
            text = if (text.isEmpty()) word else "$text $word"
            model.replaceMessageText(index, text, pulsing = false)
            delay(40)
        }
        model.completeMessage(index)
    }
}
