import AuthenticationServices
import CryptoKit
import Foundation

// Helpers for the native Sign in with Apple flow. We use SwiftUI's
// SignInWithAppleButton (Apple's blessed control) and drive the nonce
// ourselves: the button's request closure sets `request.nonce` to the *hashed*
// nonce, Apple echoes that hash in the identity token's `nonce` claim, and the
// server re-checks it against sha256(raw nonce) — replay protection. So the
// raw nonce must be kept between the request and the server exchange, and sent
// alongside the token. See PROTOCOL.md and AppModel.completeAppleSignIn.
enum AppleSignIn {
    // A fresh random nonce (URL-safe alphabet; only randomness matters).
    static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // Pulls the identity token (a JWS string) out of a completed authorization.
    static func identityToken(from authorization: ASAuthorization) -> String? {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let data = credential.identityToken
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
