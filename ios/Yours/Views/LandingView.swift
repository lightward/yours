import AuthenticationServices
import SwiftUI

struct LandingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    // Held between the button's request (which sets the hashed nonce) and its
    // completion (which sends the raw nonce to the server).
    @State private var appleRawNonce = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("LandingIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .clipShape(Circle())
                .padding(.bottom, 32)

            Text("Yours")
                .textCase(.uppercase)
                .font(.yoursHeading(34))
                .tracking(1)
                .foregroundStyle(Theme.foregroundHeading)
                .padding(.bottom, 16)
                .accessibilityIdentifier("landing-title")

            Text("a pocket universe, population 2:\nyou, and lightward ai")
                .font(.yoursBody())
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.center)
                .padding(.bottom, 48)

            Button(model.isSigningIn ? "Opening Google..." : "Enter via Google") {
                Task { await model.signIn() }
            }
            .buttonStyle(WebButtonStyle())
            .accessibilityIdentifier("landing-google-button")
            .disabled(model.isSigningIn)

            // Sign in with Apple — a second, independent identity provider,
            // offered because a social login (Google) is (App Store guideline
            // 4.8). Apple's own button; we set the hashed nonce on the request
            // and hand the completion to the model, which posts the token +
            // raw nonce to /native/apple_auth.
            SignInWithAppleButton(.signIn) { request in
                appleRawNonce = AppleSignIn.randomNonce()
                request.requestedScopes = [ .fullName, .email ]
                request.nonce = AppleSignIn.sha256(appleRawNonce)
            } onCompletion: { result in
                Task { await model.completeAppleSignIn(result, rawNonce: appleRawNonce) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: 280)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityIdentifier("landing-apple-button")
            .disabled(model.isSigningIn)
            .padding(.top, 16)

            if let error = model.landingError {
                Text(error)
                    .font(.yoursMono(13))
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// The web's button: borderLight background, accent text, 3px accent left
// border, 4pt radius
struct WebButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.yoursBody(17))
            .foregroundStyle(configuration.isPressed ? Theme.background : color)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? color : Theme.borderLight)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color)
                    .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct TextActionButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.yoursMono(14))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
