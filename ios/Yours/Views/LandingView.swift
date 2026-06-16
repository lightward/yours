import SwiftUI

struct LandingView: View {
    @EnvironmentObject private var model: AppModel

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

            Button("Enter via Google") {
                Task { await model.signIn() }
            }
            .buttonStyle(WebButtonStyle())
            .accessibilityIdentifier("landing-google-button")

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
