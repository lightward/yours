import StoreKit
import SwiftUI

// The client-side mirror of one resonance's state, and the verbs that move
// it. All persistence is server-side (see PROTOCOL.md); this object holds the
// bearer token, the loaded state, and the transient streaming UI state.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case landing
        case chat
        case locked     // day 2+ without subscription — web sends you to settings
        case sleeping
    }

    struct DisplayMessage: Identifiable, Equatable {
        let id = UUID()
        var role: String
        var text: String
        var isPulsing = false
        var isComplete = true
        var isError = false
    }

    // The gentle full-width notices: continuity divergence, expired session
    struct Notice: Equatable {
        var message: String
        var actionLabel: String
        var action: NoticeAction
    }

    enum NoticeAction: Equatable {
        case refresh
        case signIn
    }

    @Published var phase: Phase = .loading
    @Published var state: UniverseState?
    @Published var messages: [DisplayMessage] = []
    @Published var composerText = ""
    @Published var isWaiting = false
    @Published var notice: Notice?
    @Published var landingError: String?
    @Published var sleepStartingTime: String?
    @Published var settingsSubscription: SubscriptionDetails?
    @Published var themePreference: ThemePreference {
        didSet { UserDefaults.standard.set(themePreference.rawValue, forKey: "yours-theme") }
    }

    let api: YoursAPI
    private let authFlow = AuthFlow()
    private var draftSaveTask: Task<Void, Never>?
    private var checkedExistingAppleEntitlement = false

    #if DEBUG
    // Simulator screenshot / preview support: -YoursMockChat, -YoursMockLanding
    var mock: MockMode?
    enum MockMode { case chat, landing }
    #endif

    let store = Store.shared

    init() {
        themePreference = ThemePreference(
            rawValue: UserDefaults.standard.string(forKey: "yours-theme") ?? "dark"
        ) ?? .dark
        #if DEBUG
        // Local-dev entry without the Google handshake: mint a token with
        // `bin/rails runner` and pass it as `-YoursToken <token>`
        if let injected = UserDefaults.standard.string(forKey: "YoursToken") {
            Keychain.token = injected
        }
        #endif
        api = YoursAPI(token: Keychain.token)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-YoursMockChat") { mock = .chat }
        if ProcessInfo.processInfo.arguments.contains("-YoursMockLanding") { mock = .landing }
        #endif
        store.start()
    }

    // MARK: - Subscription (StoreKit)

    func subscribe(to product: Product) async {
        let accountToken = state?.iapAccountToken
        guard let newState = await store.purchase(product, accountToken: accountToken, api: api) else { return }
        apply(state: newState)
    }

    func restorePurchases() async {
        guard let state = await store.restore(api: api) else { return }
        apply(state: state)
    }

    // Permanent account deletion (App Store 5.1.1v). Destroys the resonance
    // server-side, then returns to the landing screen.
    func deleteAccount() async {
        #if DEBUG
        if mock != nil { signOut(); return }
        #endif
        do {
            try await api.deleteAccount()
            signOut()
        } catch {
            notice = Notice(message: "Couldn't delete the account just now.", actionLabel: "Try again", action: .refresh)
        }
    }

    // MARK: - Lifecycle

    func start() async {
        #if DEBUG
        switch mock {
        case .chat:
            apply(state: MockData.state)
            if ProcessInfo.processInfo.arguments.contains("-YoursMockAutoSend") {
                try? await Task.sleep(for: .seconds(1.5))
                composerText = "what does it look like from the other side?"
                send()
            }
            if ProcessInfo.processInfo.arguments.contains("-YoursMockSleep") {
                await beginSleep()
            }
            return
        case .landing:
            phase = .landing
            return
        case nil:
            break
        }
        #endif

        guard api.token != nil else {
            phase = .landing
            return
        }
        await refreshState()
    }

    func refreshState() async {
        #if DEBUG
        if mock != nil { return }
        #endif
        do {
            let state = try await api.state()
            let syncedState = await stateAfterSyncingExistingEntitlementIfNeeded(state)
            apply(state: syncedState)
        } catch APIError.unauthenticated {
            signOut(message: "Your session has expired. Sign in to continue.")
        } catch {
            if phase == .loading || phase == .landing {
                phase = .landing
                landingError = "Couldn't reach Yours just now."
            } else {
                notice = Notice(
                    message: "Couldn't reach Yours just now.",
                    actionLabel: "Try again",
                    action: .refresh
                )
            }
        }
    }

    private func stateAfterSyncingExistingEntitlementIfNeeded(_ state: UniverseState) async -> UniverseState {
        guard state.universeDay > 1,
              !state.subscriptionActive,
              !checkedExistingAppleEntitlement
        else { return state }

        checkedExistingAppleEntitlement = true
        if let restored = await store.syncExistingEntitlement(api: api) {
            return restored
        }
        return state
    }

    private func apply(state: UniverseState) {
        self.state = state
        messages = state.narrative.map { DisplayMessage(role: $0.role, text: $0.text) }
        notice = nil
        sleepStartingTime = nil
        isWaiting = false
        landingError = nil
        // Day 1 is free; day 2+ wants the subscription (policy is physics)
        phase = (state.universeDay > 1 && !state.subscriptionActive) ? .locked : .chat
        loadDraft()
    }

    // MARK: - Auth

    func signIn() async {
        do {
            let result = try await authFlow.signIn(api: api)
            Keychain.token = result.token
            api.token = result.token
            landingError = nil
            await refreshState()
        } catch is AuthFlow.Cancelled {
            // The human closed the sheet; nothing to say
        } catch {
            landingError = "Sign-in didn't complete. Try again?"
        }
    }

    func handleOpenURL(_ url: URL) {
        _ = authFlow.handleCallbackURL(url)
    }

    func signOut(message: String? = nil) {
        Keychain.token = nil
        api.token = nil
        checkedExistingAppleEntitlement = false
        state = nil
        messages = []
        composerText = ""
        phase = .landing
        landingError = message
    }

    // MARK: - Chat

    func send() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWaiting, let universeTime = state?.universeTime else { return }

        notice = nil
        messages.append(DisplayMessage(role: "user", text: text))
        composerText = ""
        isWaiting = true
        clearDraft()

        // Track the streaming message by its stable id, never by index: a
        // concurrent apply(state:) (from a refresh, a purchase, a mid-stream
        // universe_time) can replace the whole array, and the error paths below
        // remove messages — any captured index would go stale and misroute or
        // trap. updateStreaming(_:) looks the message up by id each time and
        // no-ops if it's gone.
        let placeholder = DisplayMessage(role: "assistant", text: ".", isPulsing: true, isComplete: false)
        let streamingID = placeholder.id
        messages.append(placeholder)

        Task {
            #if DEBUG
            if mock != nil {
                await MockData.streamResponse(into: self, id: streamingID)
                isWaiting = false
                return
            }
            #endif
            do {
                let events = try await api.stream(message: .user(text), universeTime: universeTime)
                for try await event in events {
                    handle(event, id: streamingID)
                }
                updateStreaming(streamingID) { $0.isPulsing = false; $0.isComplete = true }
            } catch APIError.divergence(let message) {
                removeMessage(streamingID)
                notice = Notice(
                    message: message.isEmpty
                        ? "This space moved forward elsewhere. Refresh to join where it is now."
                        : message,
                    actionLabel: "Refresh to continue",
                    action: .refresh
                )
            } catch APIError.unauthenticated {
                removeMessage(streamingID)
                notice = Notice(
                    message: "Your session has expired. Sign in to continue.",
                    actionLabel: "Sign in",
                    action: .signIn
                )
            } catch APIError.subscriptionRequired {
                removeMessage(streamingID)
                await refreshState()
            } catch {
                updateStreaming(streamingID) {
                    $0.isPulsing = false
                    $0.isComplete = true
                    $0.isError = true
                    $0.text = "⚠️ Error: the stream broke. Your message wasn't lost on the web side — refresh to see where things stand."
                }
            }
            isWaiting = false
        }
    }

    // Mutate the in-flight streaming message by id; no-op if it's no longer in
    // the array (e.g. an apply(state:) replaced it). This is the guard that
    // makes streaming safe against concurrent state replacement.
    func updateStreaming(_ id: UUID, _ mutate: (inout DisplayMessage) -> Void) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[i])
    }

    private func removeMessage(_ id: UUID) {
        messages.removeAll { $0.id == id }
    }

    private func handle(_ event: SSEEvent, id: UUID) {
        switch event.name {
        case "message_start":
            updateStreaming(id) { $0.isPulsing = false; $0.text = "" }
        case "content_block_delta":
            if let delta = event.textDelta {
                updateStreaming(id) {
                    if $0.isPulsing { $0.isPulsing = false; $0.text = "" }
                    $0.text += delta
                }
            }
        case "message_stop":
            updateStreaming(id) { $0.isComplete = true }
        case "universe_time":
            if let time = event.universeTime {
                state?.universeTime = time
            }
        case "error":
            updateStreaming(id) {
                $0.isPulsing = false
                $0.isComplete = true
                $0.isError = true
                $0.text = "⚠️ \(event.errorMessage ?? "An error occurred")"
            }
        case "end":
            updateStreaming(id) { $0.isPulsing = false }
        default:
            break
        }
    }

    func noticeAction() {
        guard let notice else { return }
        switch notice.action {
        case .refresh:
            Task { await refreshState() }
        case .signIn:
            signOut()
        }
    }

    // MARK: - Draft (mirrors the web's localStorage + debounced server save)

    private var draftKey: String {
        "yours-input-\(state?.universeTime ?? "current")"
    }

    private func loadDraft() {
        let serverSaved = state?.textarea ?? ""
        let localSaved = UserDefaults.standard.string(forKey: draftKey) ?? ""
        // Whichever is longer is assumed more recent — same heuristic as the web
        let saved = serverSaved.count >= localSaved.count ? serverSaved : localSaved
        if !saved.isEmpty {
            composerText = saved
        }
    }

    func composerChanged() {
        UserDefaults.standard.set(composerText, forKey: draftKey)

        draftSaveTask?.cancel()
        let text = composerText
        let key = draftKey
        guard let universeTime = state?.universeTime else { return }
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            #if DEBUG
            if self.mock != nil { return }
            #endif
            do {
                try await self.api.saveTextarea(text, universeTime: universeTime)
                UserDefaults.standard.removeObject(forKey: key)
            } catch APIError.divergence(let message) {
                self.notice = Notice(
                    message: message.isEmpty
                        ? "This space moved forward elsewhere. Refresh to join where it is now."
                        : message,
                    actionLabel: "Refresh to continue",
                    action: .refresh
                )
            } catch {
                // Fail silently — the draft is still in UserDefaults
            }
        }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
        draftSaveTask?.cancel()
        guard let universeTime = state?.universeTime else { return }
        #if DEBUG
        if mock != nil { return }
        #endif
        Task { try? await api.saveTextarea("", universeTime: universeTime) }
    }

    // MARK: - Sleep

    func beginSleep() async {
        #if DEBUG
        if mock != nil {
            sleepStartingTime = state?.universeTime
            phase = .sleeping
            return
        }
        #endif
        do {
            sleepStartingTime = try await api.beginSleep()
            phase = .sleeping
        } catch APIError.subscriptionRequired {
            await refreshState()
        } catch {
            notice = Notice(
                message: "Couldn't begin the night just now.",
                actionLabel: "Try again",
                action: .refresh
            )
        }
    }

    // Polled by SleepView once per second; true when integration completed
    func sleepIntegrationFinished() async -> Bool {
        #if DEBUG
        if mock != nil { return true }
        #endif
        guard let starting = sleepStartingTime else { return true }
        guard let current = try? await api.state() else { return false }
        return current.universeTime != starting
    }

    // MARK: - Settings

    func loadSettingsSubscription() async {
        #if DEBUG
        if mock != nil { return }
        #endif
        settingsSubscription = try? await api.state(includeSubscription: true).subscription
    }

    func startOver() async {
        #if DEBUG
        if mock != nil { return }
        #endif
        do {
            try await api.reset()
            await refreshState()
        } catch {
            notice = Notice(message: "Couldn't start over just now.", actionLabel: "Try again", action: .refresh)
        }
    }

    func exportNarrative() async throws -> (text: String, filename: String) {
        let filename = "yours-\(state?.universeTime.replacingOccurrences(of: ":", with: "-") ?? "current").txt"
        #if DEBUG
        if mock != nil { return (MockData.exportText, filename) }
        #endif
        return (try await api.exportText(), filename)
    }
}
