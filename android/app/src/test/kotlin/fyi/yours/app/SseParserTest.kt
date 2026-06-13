package fyi.yours.app

import fyi.yours.app.net.SseEvent
import fyi.yours.app.net.SseLineParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

// The SSE framing this client must keep speaking — mirrors what
// ApplicationController#stream actually emits, including the quirk that the
// final "end" event arrives with no data line and no trailing blank line.
class SseParserTest {
    private fun parse(raw: String): List<SseEvent> {
        val parser = SseLineParser()
        val events = mutableListOf<SseEvent>()
        raw.split("\n").forEach { line ->
            parser.consume(line)?.let { events.add(it) }
        }
        parser.finish()?.let { events.add(it) }
        return events
    }

    @Test
    fun typicalStream() {
        val raw = """
            event: message_start
            data: {"type":"message_start"}

            event: content_block_delta
            data: {"delta":{"type":"text_delta","text":"Hello"}}

            event: universe_time
            data: {"universe_time":"1:2"}

            event: end
        """.trimIndent()

        val events = parse(raw)
        assertEquals(
            listOf("message_start", "content_block_delta", "universe_time", "end"),
            events.map { it.name }
        )
        assertEquals("Hello", events[1].textDelta)
        assertEquals("1:2", events[2].universeTime)
        assertNull(events[3].data)
    }

    @Test
    fun errorEvent() {
        val raw = "event: error\ndata: {\"error\":{\"message\":\"An error occurred\"}}\n\n"
        assertEquals("An error occurred", parse(raw).first().errorMessage)
    }

    @Test
    fun textDeltaIgnoresOtherDeltaTypes() {
        val raw = "event: content_block_delta\ndata: {\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{}\"}}\n\n"
        assertNull(parse(raw).first().textDelta)
    }

    @Test
    fun orphanDataGetsDefaultEventName() {
        val raw = "event: message_start\ndata: {}\n\ndata: {\"orphan\":true}\n\n"
        val events = parse(raw)
        assertEquals(2, events.size)
        assertEquals("message_start", events[0].name)
        assertEquals("message", events[1].name)
    }
}
