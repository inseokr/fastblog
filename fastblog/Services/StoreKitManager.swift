//
//  StoreKitManager.swift
//  Capper
//
//  Handles StoreKit 2 product fetching, purchasing, and transaction observation.
//

import Combine
import Foundation
import StoreKit

/// Product ID constants — must match App Store Connect configuration.
enum ProductID {
    static let proMonthly = "com.bloggo.pro.monthly"
    static let proYearly = "com.bloggo.pro.yearly"
    /// Consumable: each purchase adds 1 lifetime blog slot.
    /// Consumable is used (rather than non-consumable) because non-consumables can only
    /// be purchased once per Apple ID, making it impossible to buy multiple slots.
    static let lifetimeBlog = "com.bloggo.lifetimeblog"

    static let allIDs: Set<String> = [proMonthly, proYearly, lifetimeBlog]
    static let proIDs: Set<String> = [proMonthly, proYearly]
}

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published var errorMessage: String?

    enum PurchaseState: Equatable {
        case idle
        case loading
        case purchasing
    }

    /// Sorted products: monthly, yearly, lifetime.
    var proMonthly: Product? { products.first { $0.id == ProductID.proMonthly } }
    var proYearly: Product? { products.first { $0.id == ProductID.proYearly } }
    var lifetimeBlog: Product? { products.first { $0.id == ProductID.lifetimeBlog } }

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await fetchProducts() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Fetch Products

    func fetchProducts() async {
        purchaseState = .loading
        errorMessage = nil
        do {
            let storeProducts = try await Product.products(for: ProductID.allIDs)
            // Sort: monthly first, yearly second, lifetime third.
            products = storeProducts.sorted { a, b in
                let order: [String: Int] = [
                    ProductID.proMonthly: 0,
                    ProductID.proYearly: 1,
                    ProductID.lifetimeBlog: 2
                ]
                return (order[a.id] ?? 99) < (order[b.id] ?? 99)
            }
            purchaseState = .idle
        } catch {
            errorMessage = "Unable to load products. Please try again."
            purchaseState = .idle
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        purchaseState = .purchasing
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await EntitlementManager.shared.handleTransaction(transaction, productID: product.id)
                await transaction.finish()
                purchaseState = .idle
                return true

            case .userCancelled:
                purchaseState = .idle
                return false

            case .pending:
                errorMessage = "Purchase is pending approval."
                purchaseState = .idle
                return false

            @unknown default:
                purchaseState = .idle
                return false
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            purchaseState = .idle
            return false
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        purchaseState = .loading
        errorMessage = nil
        EntitlementManager.shared.restoreResultMessage = nil

        // Sync forces StoreKit to check server for all past transactions.
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
            purchaseState = .idle
            return
        }

        let foundPro = await EntitlementManager.shared.refreshEntitlements()
        if foundPro {
            EntitlementManager.shared.restoreResultMessage = "Pro subscription restored."
        } else if EntitlementManager.shared.lifetimeBlogSlots > 0 {
            EntitlementManager.shared.restoreResultMessage = "Lifetime slots restored."
        } else {
            EntitlementManager.shared.restoreResultMessage = "No purchases found."
        }
        purchaseState = .idle
    }

    // MARK: - Transaction Listener

    /// Listens for transactions that occur outside the purchase flow
    /// (renewals, family sharing changes, revocations, pending approvals).
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.checkVerified(result)
                    await EntitlementManager.shared.handleTransaction(transaction, productID: transaction.productID)
                    await transaction.finish()
                } catch {
                    // Verification failed — ignore.
                }
            }
        }
    }

    // MARK: - Verification

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let item):
            return item
        }
    }
}
