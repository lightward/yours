import SwiftUI

// Day 2+ without a subscription. The web redirects to settings with an
// alert; here the day waits, gently, while the subscription happens on the
// web.
struct LockedView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showExitConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Yours: \(model.state.map(\.dayWithUnits) ?? "")")
                .textCase(.uppercase)
                .font(.yoursHeading(24))
                .foregroundStyle(Theme.foregroundHeading)
                .padding(.bottom, 20)

            Text("Subscribe to continue with \(model.state.map(\.dayWithUnits) ?? "this day").")
                .font(.yoursMono(15))
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            Text("Subscriptions live on the web — visit yours.fyi\nin your browser, then return here.")
                .font(.yoursBody(15))
                .foregroundStyle(Theme.foreground.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.bottom, 36)

            Button("I've subscribed — check again") {
                Task { await model.refreshState() }
            }
            .buttonStyle(WebButtonStyle())

            Spacer()

            Button("Exit") { showExitConfirm = true }
                .font(.yoursMono(14))
                .foregroundStyle(Theme.accentActive)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
        .confirmationDialog("Exit?", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button("Exit", role: .destructive) { model.signOut() }
        }
    }
}
