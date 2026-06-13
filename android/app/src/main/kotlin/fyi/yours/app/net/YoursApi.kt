package fyi.yours.app.net

import fyi.yours.app.BuildConfig
import fyi.yours.app.ChatMessage
import fyi.yours.app.UniverseState
import fyi.yours.app.YoursJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.encodeToString
import okhttp3.CookieJar
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.util.concurrent.TimeUnit

sealed class ApiException(message: String) : Exception(message) {
    class Unauthenticated : ApiException("unauthenticated")
    class SubscriptionRequired(val serverMessage: String) : ApiException("subscription_required")
    class Divergence(val serverMessage: String) : ApiException("continuity_divergence")
    class Http(val code: Int) : ApiException("http $code")
}

// The client side of PROTOCOL.md. Stateless except for the bearer token;
// cookies are deliberately disabled — the token is the whole identity story.
class YoursApi(@Volatile var token: String? = null, baseUrlOverride: String? = null) {
    // Debug default expects `adb reverse tcp:3000 tcp:3000` (bin/android run
    // sets this up), so the emulator's localhost reaches the host's Rails and
    // its HOST=localhost check stays satisfied
    val baseUrl: String = baseUrlOverride
        ?: if (BuildConfig.DEBUG) "http://localhost:3000" else "https://yours.fyi"

    private val jsonMedia = "application/json".toMediaType()

    private val client = OkHttpClient.Builder()
        .cookieJar(CookieJar.NO_COOKIES)
        .readTimeout(90, TimeUnit.SECONDS)
        .addInterceptor { chain ->
            val builder = chain.request().newBuilder()
                .header("User-Agent", "Yours-Android/${BuildConfig.VERSION_NAME}")
            token?.let { builder.header("Authorization", "Bearer $it") }
            chain.proceed(builder.build())
        }
        .build()

    // MARK: endpoints

    suspend fun exchangeToken(code: String, verifier: String): Pair<String, String?> =
        withContext(Dispatchers.IO) {
            val body = buildJsonObject {
                put("code", code)
                put("code_verifier", verifier)
            }
            val response = execute(post("native/token", body))
            response.use {
                val obj = parseObject(it)
                Pair(
                    obj["token"]?.jsonPrimitive?.content ?: throw ApiException.Http(500),
                    obj["obfuscated_email"]?.jsonPrimitive?.content
                )
            }
        }

    suspend fun state(includeSubscription: Boolean = false): UniverseState =
        withContext(Dispatchers.IO) {
            val path = if (includeSubscription) "native/state?include=subscription" else "native/state"
            execute(get(path)).use { response ->
                YoursJson.decodeFromString<UniverseState>(response.body!!.string())
            }
        }

    suspend fun saveTextarea(text: String, universeTime: String): Unit =
        withContext(Dispatchers.IO) {
            val body = buildJsonObject { put("textarea", text) }
            execute(
                Request.Builder()
                    .url("$baseUrl/textarea")
                    .put(YoursJson.encodeToString(body).toRequestBody(jsonMedia))
                    .header("Assert-Yours-Universe-Time", universeTime)
                    .build()
            ).close()
        }

    // POST /stream — opens the SSE stream and hands each event to onEvent.
    // Runs to stream end; throws ApiException for structured denials.
    suspend fun stream(
        message: ChatMessage,
        universeTime: String,
        onEvent: suspend (SseEvent) -> Unit
    ): Unit = withContext(Dispatchers.IO) {
        val body = buildJsonObject {
            put("message", YoursJson.encodeToJsonElement(ChatMessage.serializer(), message))
        }
        val request = Request.Builder()
            .url("$baseUrl/stream")
            .post(YoursJson.encodeToString(body).toRequestBody(jsonMedia))
            .header("Assert-Yours-Universe-Time", universeTime)
            .build()

        execute(request).use { response ->
            val source = response.body!!.source()
            val parser = SseLineParser()
            while (true) {
                val line = source.readUtf8Line() ?: break
                parser.consume(line)?.let { onEvent(it) }
            }
            parser.finish()?.let { onEvent(it) }
        }
    }

    suspend fun beginSleep(): String = withContext(Dispatchers.IO) {
        execute(post("sleep", buildJsonObject {})).use { response ->
            parseObject(response)["starting_universe_time"]?.jsonPrimitive?.content
                ?: throw ApiException.Http(500)
        }
    }

    suspend fun reset(): Unit = withContext(Dispatchers.IO) {
        execute(post("reset", buildJsonObject {})).close()
    }

    // GET /save — the narrative as plain text, for the share sheet
    suspend fun exportText(): String = withContext(Dispatchers.IO) {
        execute(get("save")).use { it.body!!.string() }
    }

    // MARK: plumbing

    private fun get(path: String) =
        Request.Builder().url("$baseUrl/$path").get().build()

    private fun post(path: String, body: JsonObject) =
        Request.Builder()
            .url("$baseUrl/$path")
            .post(YoursJson.encodeToString(body).toRequestBody(jsonMedia))
            .build()

    private fun execute(request: Request): Response {
        val response = client.newCall(request).execute()
        if (response.isSuccessful) return response

        val raw = response.body?.string().orEmpty()
        response.close()
        val message = runCatching {
            Json.parseToJsonElement(raw).jsonObject["message"]?.jsonPrimitive?.content
        }.getOrNull().orEmpty()

        throw when (response.code) {
            401 -> ApiException.Unauthenticated()
            403 -> ApiException.SubscriptionRequired(message)
            409 -> ApiException.Divergence(message)
            else -> ApiException.Http(response.code)
        }
    }

    private fun parseObject(response: Response): JsonObject =
        Json.parseToJsonElement(response.body!!.string()).jsonObject
}
