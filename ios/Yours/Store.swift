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

    func start(api: YoursAPI, onSyncedState: @escaping @MainActor (UniverseState) -> Void) {
        // Listen for transactions that arrive outside an explicit purchase
        // (renewals, Ask-to-Buy approvals, restores on another device)
        updatesTask?.cancel()
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(verification: update, api: api, onSyncedState: onSyncedState)
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
    func purchase(_ product: Product, accountToken: String?, api: YoursAPI) async -> UniverseState? {
        purchasing = true
        purchaseError = nil
        defer { purchasing = false }

        do {
            // Bind the purchase to this account so the server can verify the
            // transaction belongs to whoever bought it (cross-account replay
            // prevention). The token comes from /native/state.
            var options: Set<Product.PurchaseOption> = []
            if let accountToken, let uuid = UUID(uuidString: accountToken) {
                options.insert(.appAccountToken(uuid))
            }
            let result = try await product.purchase(options: options)
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
        } catch APIError.unauthenticated {
            purchaseError = "Sign in again before purchasing."
            return nil
        } catch APIError.subscriptionRequired(let message) {
            purchaseError = message.isEmpty
                ? "That App Store purchase belongs to a different Yours account."
                : message
            return nil
        } catch APIError.divergence {
            purchaseError = "That App Store subscription is already linked to another Yours account."
            return nil
        } catch APIError.http(502) {
            purchaseError = "The App Store purchase couldn't be verified just now. Tap Restore purchase to retry."
            return nil
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

        try? await AppStore.sync()

        if let state = await syncExistingEntitlement(api: api, reportErrors: true) {
            return state
        }

        if purchaseError != nil {
            return nil
        }

        purchaseError = "No active subscription found to restore."
        return nil
    }

    // Quietly re-link an existing App Store entitlement before showing a
    // purchase prompt. Unlike the explicit restore button, this does not set
    // loading/error UI: if nothing verifies, the normal subscription choices
    // are shown.
    func syncExistingEntitlement(api: YoursAPI, reportErrors: Bool = false) async -> UniverseState? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID)
            else { continue }

            do {
                let state = try await submit(result, api: api)
                return state
            } catch APIError.divergence {
                if reportErrors {
                    purchaseError = "That App Store subscription is already linked to another Yours account."
                }
                return nil
            } catch APIError.subscriptionRequired(let message) {
                if reportErrors {
                    purchaseError = message.isEmpty
                        ? "That App Store purchase belongs to a different Yours account."
                        : message
                    return nil
                }
            } catch APIError.unauthenticated {
                if reportErrors {
                    purchaseError = "Sign in again before restoring purchases."
                    return nil
                }
            } catch {
                if reportErrors {
                    purchaseError = "Couldn't verify the App Store purchase just now. Try Restore purchase again in a minute."
                    return nil
                }
                continue
            }
        }

        return nil
    }

    // Hand the JWS representation to the server, which is the authority on
    // whether it's genuine. We finish the transaction once the server has it.
    private func submit(_ verification: VerificationResult<Transaction>, api: YoursAPI) async throws -> UniverseState {
        let signed = verification.jwsRepresentation
        let state = try await api.verifySubscription(platform: "apple", signedTransaction: signed)
        if case .verified(let transaction) = verification {
            await transaction.finish()
        }
        return state
    }

    private func handle(
        verification: VerificationResult<Transaction>,
        api: YoursAPI,
        onSyncedState: @escaping @MainActor (UniverseState) -> Void
    ) async {
        guard case .verified(let transaction) = verification,
              Self.productIDs.contains(transaction.productID)
        else { return }

        do {
            let state = try await submit(verification, api: api)
            onSyncedState(state)
            purchaseError = nil
        } catch APIError.http(422) {
            // StoreKit verified the transaction, but the server found no
            // active entitlement for it. Finish so StoreKit does not redeliver
            // a terminally unusable transaction forever.
            await transaction.finish()
        } catch {
            purchaseError = "Couldn't sync the App Store purchase. Tap Restore purchase to retry."
        }
    }
}
