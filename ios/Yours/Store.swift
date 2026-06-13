import StoreKit

// StoreKit 2 purchase flow for the native subscription. The storefront takes
// the money and hands us a signed transaction; we pass that to the server
// (POST /native/subscription), which verifies it with Apple's own API and
// records the entitlement. See PROTOCOL.md.
//
// The product IDs match config/initializers/native_iap.rb (APPLE_PRODUCT_IDS)
// and the local Yours.storekit configuration used for simulator testing.
@MainActor
final class Store: ObservableObject {
    // One store for the app; AppModel drives it, views observe it directly.
    static let shared = Store()

    static let productIDs = [
        "fyi.yours.subscription.tier_1",
        "fyi.yours.subscription.tier_10",
        "fyi.yours.subscription.tier_100",
        "fyi.yours.subscription.tier_1000"
    ]

    @Published var products: [Product] = []
    @Published var purchasing = false
    @Published var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    // The price tiers, ordered low to high — mirrors the web's $1/$10/$100/$1000
    var sortedProducts: [Product] {
        products.sorted { $0.price < $1.price }
    }

    func start() {
        // Listen for transactions that arrive outside an explicit purchase
        // (renewals, Ask-to-Buy approvals, restores on another device)
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(verification: update)
            }
        }
        Task { await loadProducts() }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
        } catch {
            purchaseError = "Couldn't load subscription options."
        }
    }

    // Returns the verified server state on success, nil if the person cancelled.
    func purchase(_ product: Product, api: YoursAPI) async -> UniverseState? {
        purchasing = true
        purchaseError = nil
        defer { purchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                return try await submit(verification, api: api)
            case .userCancelled:
                return nil
            case .pending:
                purchaseError = "This purchase is pending approval."
                return nil
            @unknown default:
                return nil
            }
        } catch {
            purchaseError = "Purchase didn't complete. Try again?"
            return nil
        }
    }

    // "Restore purchases" — re-sync the current entitlement to this account.
    func restore(api: YoursAPI) async -> UniverseState? {
        purchasing = true
        purchaseError = nil
        defer { purchasing = false }

        for await result in Transaction.currentEntitlements {
            if let state = try? await submit(result, api: api) {
                return state
            }
        }
        purchaseError = "No active subscription found to restore."
        return nil
    }

    // Hand the JWS representation to the server, which is the authority on
    // whether it's genuine. We finish the transaction once the server has it.
    private func submit(_ verification: VerificationResult<Transaction>, api: YoursAPI) async throws -> UniverseState? {
        let signed = verification.jwsRepresentation
        let state = try await api.verifySubscription(platform: "apple", signedTransaction: signed)
        if case .verified(let transaction) = verification {
            await transaction.finish()
        }
        return state
    }

    private func handle(verification: VerificationResult<Transaction>) async {
        // Background updates: finish so StoreKit stops re-delivering. The next
        // /native/state reflects entitlement; we don't have an api handle here.
        if case .verified(let transaction) = verification {
            await transaction.finish()
        }
    }
}
