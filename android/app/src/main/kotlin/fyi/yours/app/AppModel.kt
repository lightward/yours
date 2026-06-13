package fyi.yours.app

import android.app.Application
import android.os.Bundle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import fyi.yours.app.net.ApiException
import fyi.yours.app.net.AuthFlow
import fyi.yours.app.net.SseEvent
import fyi.yours.app.net.TokenStore
import fyi.yours.app.net.YoursApi
import fyi.yours.app.support.MockData
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

// The client-side mirror of one resonance's state, and the verbs that move
// it. All persistence is server-side (see PROTOCOL.md); this object holds the
// bearer token, the loaded state, and the transient streaming UI state.
// Mirrors ios/Yours/AppModel.swift.
class AppModel(application: Application) : AndroidViewModel(application) {
    enum class Phase { LOADING, LANDING, CHAT, LOCKED, SLEEPING }

    data class DisplayMessage(
        val id: String = UUID.randomUUID().toString(),
        val role: String,
        val text: String,
        val isPulsing: Boolean = false,
        val isComplete: Boolean = true,
        val isError: Boolean = false
    )

    data class Notice(val message: String, val actionLabel: String, val action: NoticeAction)
    enum class NoticeAction { REFRESH, SIGN_IN }

    var phase by mutableStateOf(Phase.LOADING)
        private set
    var state by mutableStateOf<UniverseState?>(null)
        private set
    val messages = mutableStateListOf<DisplayMessage>()
    var composerText by mutableStateOf("")
    var isWaiting by mutableStateOf(false)
        private set
    var notice by mutableStateOf<Notice?>(null)
        private set
    var landingError by mutableStateOf<String?>(null)
        private set
    var sleepStartingTime by mutableStateOf<String?>(null)
        private set
    var settingsSubscription by mutableStateOf<SubscriptionDetails?>(null)
        private set

    private val prefs = application.getSharedPreferences("yours", Application.MODE_PRIVATE)
    var themePreference by mutableStateOf(ThemePreference.from(prefs.getString("yours-theme", null)))
        private set

    private val tokenStore = TokenStore(application)
    lateinit var api: YoursApi
        private set

    // Emulator screenshot / dev support, from MainActivity intent extras
    // (debug builds only): YoursMockChat, YoursMockLanding, YoursMockAutoSend,
    // YoursMockSleep, YoursToken, YoursBaseURL
    enum class MockMode { CHAT, LANDING }
    var mock: MockMode? = null
        private set
    private var autoSend = false
    private var mockSleep = false

    private var draftSaveJob: Job? = null
    private var pendingAuthVerifier: String?
        get() = prefs.getString("pending-auth-verifier", null)
        set(value) {
            prefs.edit().apply {
                if (value == null) remove("pending-auth-verifier")
                else putString("pending-auth-verifier", value)
            }.apply()
        }

    fun configure(extras: Bundle?) {
        if (this::api.isInitialized) return

        var baseUrlOverride: String? = null
        if (BuildConfig.DEBUG && extras != null) {
            if (extras.getBoolean("YoursMockChat")) mock = MockMode.CHAT
            if (extras.getBoolean("YoursMockLanding")) mock = MockMode.LANDING
            autoSend = extras.getBoolean("YoursMockAutoSend")
            mockSleep = extras.getBoolean("YoursMockSleep")
            extras.getString("YoursToken")?.let { tokenStore.token = it }
            baseUrlOverride = extras.getString("YoursBaseURL")
        }
        api = YoursApi(tokenStore.token, baseUrlOverride)

        viewModelScope.launch { start() }
    }

    private suspend fun start() {
        when (mock) {
            MockMode.CHAT -> {
                apply(MockData.state)
                if (autoSend) {
                    delay(1500)
                    composerText = "what does it look like from the other side?"
                    send()
                }
                if (mockSleep) beginSleep()
                return
            }
            MockMode.LANDING -> {
                phase = Phase.LANDING
                return
            }
            null -> {}
        }

        if (api.token == null) {
            phase = Phase.LANDING
            return
        }
        refreshState()
    }

    fun setTheme(preference: ThemePreference) {
        themePreference = preference
        prefs.edit().putString("yours-theme", preference.name).apply()
    }

    suspend fun refreshState() {
        if (mock != null) return
        try {
            apply(api.state())
        } catch (e: ApiException.Unauthenticated) {
            signOut("Your session has expired. Sign in to continue.")
        } catch (e: Exception) {
            if (phase == Phase.LOADING || phase == Phase.LANDING) {
                phase = Phase.LANDING
                landingError = "Couldn't reach Yours just now."
            } else {
                notice = Notice("Couldn't reach Yours just now.", "Try again", NoticeAction.REFRESH)
            }
        }
    }

    fun refresh() {
        viewModelScope.launch { refreshState() }
    }

    private fun apply(newState: UniverseState) {
        state = newState
        messages.clear()
        newState.narrative.forEach { messages.add(DisplayMessage(role = it.role, text = it.text)) }
        notice = null
        sleepStartingTime = null
        isWaiting = false
        landingError = null
        // Day 1 is free; day 2+ wants the subscription (policy is physics)
        phase = if (newState.universeDay > 1 && !newState.subscriptionActive) Phase.LOCKED else Phase.CHAT
        loadDraft()
    }

    // MARK: auth

    fun signIn() {
        val verifier = AuthFlow.newVerifier()
        pendingAuthVerifier = verifier
        AuthFlow.launch(getApplication(), api.baseUrl, AuthFlow.challenge(verifier))
    }

    // Called from MainActivity when the yours://auth?code=... intent arrives
    fun completeAuth(code: String) {
        val verifier = pendingAuthVerifier ?: return
        viewModelScope.launch {
            try {
                val (token, _) = api.exchangeToken(code, verifier)
                pendingAuthVerifier = null
                tokenStore.token = token
                api.token = token
                landingError = null
                refreshState()
            } catch (e: Exception) {
                landingError = "Sign-in didn't complete. Try again?"
                phase = Phase.LANDING
            }
        }
    }

    fun signOut(message: String? = null) {
        tokenStore.token = null
        api.token = null
        state = null
        messages.clear()
        composerText = ""
        phase = Phase.LANDING
        landingError = message
    }

    // MARK: chat

    fun send() {
        val text = composerText.trim()
        val universeTime = state?.universeTime ?: return
        if (text.isEmpty() || isWaiting) return

        notice = null
        messages.add(DisplayMessage(role = "user", text = text))
        composerText = ""
        isWaiting = true
        clearDraft()

        val index = messages.size
        messages.add(DisplayMessage(role = "assistant", text = ".", isPulsing = true, isComplete = false))

        viewModelScope.launch {
            if (mock != null) {
                MockData.streamResponse(this@AppModel, index)
                isWaiting = false
                return@launch
            }
            try {
                api.stream(ChatMessage.user(text), universeTime) { event -> handle(event, index) }
                messages[index] = messages[index].copy(isPulsing = false, isComplete = true)
            } catch (e: ApiException.Divergence) {
                messages.removeAt(index)
                notice = Notice(
                    e.serverMessage.ifEmpty { "This space moved forward elsewhere. Refresh to join where it is now." },
                    "Refresh to continue",
                    NoticeAction.REFRESH
                )
            } catch (e: ApiException.Unauthenticated) {
                messages.removeAt(index)
                notice = Notice(
                    "Your session has expired. Sign in to continue.",
                    "Sign in",
                    NoticeAction.SIGN_IN
                )
            } catch (e: ApiException.SubscriptionRequired) {
                messages.removeAt(index)
                refreshState()
            } catch (e: Exception) {
                messages[index] = messages[index].copy(
                    isPulsing = false,
                    isComplete = true,
                    isError = true,
                    text = "⚠️ Error: the stream broke. Your message wasn't lost on the web side — refresh to see where things stand."
                )
            }
            isWaiting = false
        }
    }

    private fun handle(event: SseEvent, index: Int) {
        when (event.name) {
            "message_start" -> replaceMessageText(index, "", pulsing = false)
            "content_block_delta" -> event.textDelta?.let { delta ->
                val current = if (messages[index].isPulsing) "" else messages[index].text
                replaceMessageText(index, current + delta, pulsing = false)
            }
            "message_stop" -> completeMessage(index)
            "universe_time" -> event.universeTime?.let { time ->
                state = state?.copy(universeTime = time)
            }
            "error" -> messages[index] = messages[index].copy(
                isPulsing = false,
                isComplete = true,
                isError = true,
                text = "⚠️ ${event.errorMessage ?: "An error occurred"}"
            )
            "end" -> messages[index] = messages[index].copy(isPulsing = false)
        }
    }

    fun replaceMessageText(index: Int, text: String, pulsing: Boolean) {
        messages[index] = messages[index].copy(text = text, isPulsing = pulsing)
    }

    fun completeMessage(index: Int) {
        messages[index] = messages[index].copy(isPulsing = false, isComplete = true)
    }

    fun noticeAction() {
        when (notice?.action) {
            NoticeAction.REFRESH -> refresh()
            NoticeAction.SIGN_IN -> signOut()
            null -> {}
        }
    }

    // MARK: draft (mirrors the web's localStorage + debounced server save)

    private val draftKey: String get() = "yours-input-${state?.universeTime ?: "current"}"

    private fun loadDraft() {
        val serverSaved = state?.textarea.orEmpty()
        val localSaved = prefs.getString(draftKey, null).orEmpty()
        // Whichever is longer is assumed more recent — same heuristic as the web
        val saved = if (serverSaved.length >= localSaved.length) serverSaved else localSaved
        if (saved.isNotEmpty()) composerText = saved
    }

    fun composerChanged() {
        prefs.edit().putString(draftKey, composerText).apply()

        draftSaveJob?.cancel()
        val text = composerText
        val key = draftKey
        val universeTime = state?.universeTime ?: return
        if (mock != null) return
        draftSaveJob = viewModelScope.launch {
            delay(1500)
            try {
                api.saveTextarea(text, universeTime)
                prefs.edit().remove(key).apply()
            } catch (e: ApiException.Divergence) {
                notice = Notice(
                    e.serverMessage.ifEmpty { "This space moved forward elsewhere. Refresh to join where it is now." },
                    "Refresh to continue",
                    NoticeAction.REFRESH
                )
            } catch (e: Exception) {
                // Fail silently — the draft is still in prefs
            }
        }
    }

    private fun clearDraft() {
        prefs.edit().remove(draftKey).apply()
        draftSaveJob?.cancel()
        val universeTime = state?.universeTime ?: return
        if (mock != null) return
        viewModelScope.launch {
            runCatching { api.saveTextarea("", universeTime) }
        }
    }

    // MARK: sleep

    suspend fun beginSleep() {
        if (mock != null) {
            sleepStartingTime = state?.universeTime
            phase = Phase.SLEEPING
            return
        }
        try {
            sleepStartingTime = api.beginSleep()
            phase = Phase.SLEEPING
        } catch (e: ApiException.SubscriptionRequired) {
            refreshState()
        } catch (e: Exception) {
            notice = Notice("Couldn't begin the night just now.", "Try again", NoticeAction.REFRESH)
        }
    }

    fun beginSleepAsync() {
        viewModelScope.launch { beginSleep() }
    }

    // Polled by SleepScreen once per second; true when integration completed
    suspend fun sleepIntegrationFinished(): Boolean {
        if (mock != null) return true
        val starting = sleepStartingTime ?: return true
        val current = runCatching { api.state() }.getOrNull() ?: return false
        return current.universeTime != starting
    }

    // MARK: settings

    fun loadSettingsSubscription() {
        if (mock != null) return
        viewModelScope.launch {
            settingsSubscription = runCatching { api.state(includeSubscription = true).subscription }.getOrNull()
        }
    }

    fun startOver() {
        if (mock != null) return
        viewModelScope.launch {
            try {
                api.reset()
                refreshState()
            } catch (e: Exception) {
                notice = Notice("Couldn't start over just now.", "Try again", NoticeAction.REFRESH)
            }
        }
    }

    suspend fun exportNarrative(): Pair<String, String> {
        val filename = "yours-${state?.universeTime?.replace(":", "-") ?: "current"}.txt"
        if (mock != null) return MockData.exportText to filename
        return api.exportText() to filename
    }
}
