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

            if store.sortedProducts.isEmpty {
                Text("Loading subscription options…")
                    .font(.yoursMono(13))
                    .foregroundStyle(Theme.foreground.opacity(0.6))
            } else {
                ForEach(model.store.sortedProducts, id: \.id) { product in
                    Button {
                        Task { await model.subscribe(to: product) }
                    } label: {
                        HStack {
                            Text("\(product.displayPrice) / month")
                            Spacer()
                        }
                    }
                    .buttonStyle(WebButtonStyle())
                    .disabled(model.store.purchasing)
                }
            }

            Text("Your choice is visible only to you.")
                .font(.yoursBody(14))
                .foregroundStyle(Theme.foreground.opacity(0.6))

            Button("Restore purchase") {
                Task { await model.restorePurchases() }
            }
            .font(.yoursMono(13))
            .foregroundStyle(Theme.accent)
            .disabled(model.store.purchasing)

            if let error = model.store.purchaseError {
                Text(error)
                    .font(.yoursMono(13))
                    .foregroundStyle(Theme.warning)
            }
        }
    }
}
