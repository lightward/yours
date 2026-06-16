import AuthenticationServices
import CryptoKit
import Foundation

// Native sign-in rides the existing web Google flow: open /native/auth in a
// system browser sheet with a PKCE challenge, let the human sign in exactly
// as they would on the web, and catch the yours://auth?code=... redirect.
// No Google SDK, no separate OAuth client — one sign-in surface, two doors.
@MainActor
final class AuthFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?
    private var callbackContinuation: CheckedContinuation<URL, Error>?

    struct Cancelled: Error {}

    func signIn(api: YoursAPI) async throws -> (token: String, obfuscatedEmail: String?) {
        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)

        var components = URLComponents(
            url: YoursAPI.baseURL.appending(path: "native/auth"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "code_challenge", value: challenge)]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "yours"
            ) { [weak self] url, error in
                Task { @MainActor in
                    if let url {
                        self?.finish(callbackURL: url)
                    } else if let error = error as? ASWebAuthenticationSessionError,
                              error.code == .canceledLogin {
                        self?.finish(error: Cancelled())
                    } else {
                        self?.finish(error: error ?? Cancelled())
                    }
                }
            }
            session.presentationContextProvider = self
            // Ephemeral on purpose: do NOT share Safari's cookie jar. If we
            // inherited an existing yours.fyi session, this app could be handed
            // a token for whoever happened to be signed into the browser — a
            // confused-deputy account takeover. Each native sign-in is its own
            // deliberate Google auth. (The server also gates code issuance
            // behind an explicit confirmation tap; this is the matching half.)
            session.prefersEphemeralWebBrowserSession = true
            activeSession = session
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw APIError.badResponse }

        return try await api.exchangeToken(code: code, verifier: verifier)
    }

    func handleCallbackURL(_ url: URL) -> Bool {
        guard url.scheme == "yours", url.host == "auth" else { return false }

        finish(callbackURL: url)
        return true
    }

    private func finish(callbackURL url: URL) {
        guard let continuation = callbackContinuation else { return }

        callbackContinuation = nil
        activeSession = nil
        continuation.resume(returning: url)
    }

    private func finish(error: Error) {
        guard let continuation = callbackContinuation else { return }

        callbackContinuation = nil
        activeSession = nil
        continuation.resume(throwing: error)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }

    // MARK: - PKCE

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
