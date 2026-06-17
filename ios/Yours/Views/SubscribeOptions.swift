import StoreKit
import SwiftUI

// The native subscription picker, shared by the settings sheet and the
// subscribe wall. Same framing as the web's settings page — "how much does
// 'new' cost for you?" with the price tiers — but the purchase happens
// through StoreKit, and the verified result flows back through the server.
struct SubscribeOptions: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var store = Store.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How much does \"new\" cost for you?")
                .font(.yoursBody(16))
                .foregroundStyle(Theme.foreground)

            Text("Each monthly tier unlocks the same ongoing access. Choose what fits.")
                .font(.yoursBody(14))
                .foregroundStyle(Theme.foreground.opacity(0.7))

            if store.sortedProducts.isEmpty {
                Text("Loading subscription options…")
                    .font(.yoursMono(13))
                    .foregroundStyle(Theme.foreground.opacity(0.6))
            } else {
                ForEach(store.sortedProducts, id: \.id) { product in
                    Button {
                        Task { await model.subscribe(to: product) }
                    } label: {
                        HStack {
                            Text("\(product.displayPrice) / month")
                            Spacer()
                        }
                    }
                    .buttonStyle(WebButtonStyle())
                    .disabled(store.purchasing)
                }
            }

            Text("Your choice is visible only to you.")
                .font(.yoursBody(14))
                .foregroundStyle(Theme.foreground.opacity(0.6))

            Button("Restore purchase") {
                Task { await model.restorePurchases() }
            }
            .buttonStyle(TextActionButtonStyle(color: Theme.accent))
            .disabled(store.purchasing)

            if let error = store.purchaseError {
                Text(error)
                    .font(.yoursMono(13))
                    .foregroundStyle(Theme.warning)
            }

            // App Store 3.1.2 disclosure: auto-renew terms + Terms/Privacy links
            // near the purchase controls.
            VStack(alignment: .leading, spacing: 8) {
                Text("Auto-renewing monthly subscription. Your subscription renews each month until canceled; manage or cancel in Settings › Apple Account › Subscriptions, at least 24 hours before the period ends.")
                    .font(.yoursBody(12))
                    .foregroundStyle(Theme.foreground.opacity(0.6))
                HStack(spacing: 16) {
                    Link("Terms of Use", destination: URL(string: "https://yours.fyi/terms")!)
                    Link("Privacy Policy", destination: URL(string: "https://yours.fyi/privacy")!)
                }
                .font(.yoursMono(12))
                .foregroundStyle(Theme.accent)
            }
            .padding(.top, 4)
        }
    }
}
