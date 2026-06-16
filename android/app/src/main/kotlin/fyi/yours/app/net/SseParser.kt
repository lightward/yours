package fyi.yours.app.net

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// One server-sent event off the /stream wire. The server relays upstream
// event names and adds its own (universe_time, error, end). See PROTOCOL.md
// for framing details.
data class SseEvent(val name: String, val data: String?) {
    private val json: JsonObject? by lazy {
        data?.let { runCatching { Json.parseToJsonElement(it).jsonObject }.getOrNull() }
    }

    val textDelta: String?
        get() {
            if (name != "content_block_delta") return null
            val delta = json?.get("delta")?.jsonObject ?: return null
            if (delta["type"]?.jsonPrimitive?.content != "text_delta") return null
            return delta["text"]?.jsonPrimitive?.content
        }

    val universeTime: String?
        get() {
            if (name != "universe_time") return null
            return json?.get("universe_time")?.jsonPrimitive?.content
        }

    val errorMessage: String?
        get() {
            if (name != "error") return null
            return json?.get("error")?.jsonObject?.get("message")?.jsonPrimitive?.content
        }
}

// Line-by-line SSE parser. Dispatch-on-blank-line per the SSE spec, with one
// accommodation for this server: the final "end" event arrives without a
// trailing blank line, so finish() flushes whatever is pending at EOF.
class SseLineParser {
    private var pendingName: String? = null
    private var pendingData: String? = null

    fun consume(line: String): SseEvent? {
        if (line.isEmpty()) return flush()
        if (line.startsWith("event:")) {
            val flushed = if (pendingData != null) flush() else null
            pendingName = line.removePrefix("event:").trim()
            return flushed
        }
        if (line.startsWith("data:")) {
            val value = line.removePrefix("data:").trim()
            pendingData = pendingData?.let { "$it\n$value" } ?: value
            return null
        }
        return null
    }

    fun finish(): SseEvent? = flush()

    private fun flush(): SseEvent? {
        if (pendingName == null && pendingData == null) return null
        val event = SseEvent(pendingName ?: "message", pendingData)
        pendingName = null
        pendingData = null
        return event
    }
}
