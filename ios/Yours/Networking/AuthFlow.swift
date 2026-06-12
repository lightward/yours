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
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "yours"
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: Cancelled())
                } else {
                    continuation.resume(throwing: error ?? Cancelled())
                }
            }
            session.presentationContextProvider = self
            // Share Safari's cookie jar: someone already signed in on the web
            // gets a one-tap entry
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            session.start()
        }
        activeSession = nil

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw APIError.badResponse }

        return try await api.exchangeToken(code: code, verifier: verifier)
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
