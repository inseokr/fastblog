//
//  StoreKitManager.swift
//  fastblog
//
//  Stub implementation — IAP disabled for initial release.
//  StoreKit is intentionally not imported so the framework is not linked.
//

import Foundation
import Combine

/// Placeholder product for future IAP implementation.
struct IAPProduct {
    let id: String
    let displayPrice: String
}

/// Product ID constants — reserved for future IAP implementation.
enum ProductID {
    static let proMonthly  = "com.bloggo.pro.monthly"
    static let proYearly   = "com.bloggo.pro.yearly"
    static let lifetimeBlog = "com.bloggo.lifetimeblog"
}

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    @Published private(set) var products: [IAPProduct] = []
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published var errorMessage: String?

    enum PurchaseState: Equatable {
        case idle
        case loading
        case purchasing
    }

    // Always nil — no products available until IAP is re-enabled.
    var proMonthly:  IAPProduct? { nil }
    var proYearly:   IAPProduct? { nil }
    var lifetimeBlog: IAPProduct? { nil }

    private init() {}

    func fetchProducts() async {}

    func purchase(_ product: IAPProduct) async -> Bool { return false }

    func restorePurchases() async {
        EntitlementManager.shared.restoreResultMessage = "No purchases found."
    }
}
