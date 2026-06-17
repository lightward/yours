import SwiftUI

// Day 2+ without a subscription. The web redirects to settings with an
// alert; here the day waits, gently, until a subscription opens the way
// forward — purchased right here through StoreKit.
struct LockedView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showExitConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Yours: \(model.state.map(\.dayWithUnits) ?? "")")
                    .textCase(.uppercase)
                    .font(.yoursHeading(24))
                    .foregroundStyle(Theme.foregroundHeading)
                    .padding(.bottom, 20)

                Text("Subscribe to continue with \(model.state.map(\.dayWithUnits) ?? "this day").")
                    .font(.yoursMono(15))
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 28)

                SubscribeOptions()
                    .padding(.bottom, 20)

                Button("Exit") { showExitConfirm = true }
                    .buttonStyle(TextActionButtonStyle(color: Theme.accentActive))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 48)
        }
        .background(Theme.background)
        .confirmationDialog("Exit?", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button("Exit", role: .destructive) { model.signOut() }
        }
    }
}
