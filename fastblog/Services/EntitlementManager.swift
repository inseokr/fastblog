//
//  EntitlementManager.swift
//  Capper
//
//  Single source of truth for user entitlements (Pro subscription + Lifetime Blog slots).
//  Persists state to UserDefaults for quick access; refreshes from StoreKit on launch/foreground.
//
//  In DEBUG builds, mock toggles can override real entitlements for testing.
//  Real StoreKit entitlements always take priority if a real Pro subscription is found.
//

import Combine
import Foundation
import StoreKit

@MainActor
final class EntitlementManager: ObservableObject {
    static let shared = EntitlementManager()

    // MARK: - Published State (real StoreKit values)

    /// Whether a real Pro subscription is active according to StoreKit.
    @Published private(set) var realProActive: Bool = false
    @Published private(set) var proExpirationDate: Date?
    /// Which Pro plan is active: "monthly", "yearly", or nil.
    @Published private(set) var proPlanType: String?
    /// Total lifetime blog slots purchased (persisted locally because consumables
    /// are not tracked by StoreKit after finish()).
    @Published private(set) var lifetimeBlogSlots: Int = 0
    /// Blog IDs that have a lifetime slot allocated to them.
    @Published private(set) var lifetimeAllocatedBlogIDs: Set<UUID> = []
    /// Timestamp of the last restore/refresh attempt.
    @Published private(set) var lastRestoreDate: Date?
    /// Result message from the most recent restore attempt.
    @Published var restoreResultMessage: String?

    // MARK: - Mock State (DEBUG only)

    #if DEBUG
    @Published var mockProEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(mockProEnabled, forKey: MockKeys.mockProEnabled)
            // Use Task to defer enforcement. This breaks the circular dependency
            // that causes a deadlock if this is triggered during EntitlementManager.init.
            Task { @MainActor in
                CreatedRecapBlogStore.shared.enforceArchiveRules()
            }
        }
    }
    @Published var mockExpiredPro: Bool = false {
        didSet {
            UserDefaults.standard.set(mockExpiredPro, forKey: MockKeys.mockExpiredPro)
            Task { @MainActor in
                CreatedRecapBlogStore.shared.enforceArchiveRules()
            }
        }
    }
    @Published var mockLifetimeSlots: Int = 0 {
        didSet {
            UserDefaults.standard.set(mockLifetimeSlots, forKey: MockKeys.mockLifetimeSlots)
            Task { @MainActor in
                CreatedRecapBlogStore.shared.enforceArchiveRules()
            }
        }
    }

    private enum MockKeys {
        static let mockProEnabled = "bloggo.debug.mockProEnabled"
        static let mockExpiredPro = "bloggo.debug.mockExpiredPro"
        static let mockLifetimeSlots = "bloggo.debug.mockLifetimeSlots"
    }

    private func loadMockDefaults() {
        let defaults = UserDefaults.standard
        mockProEnabled = defaults.bool(forKey: MockKeys.mockProEnabled)
        mockExpiredPro = defaults.bool(forKey: MockKeys.mockExpiredPro)
        mockLifetimeSlots = defaults.integer(forKey: MockKeys.mockLifetimeSlots)
    }
    #endif

    // MARK: - Effective Entitlements (merges real + mock)

    /// Effective Pro status: real StoreKit always wins; mock only applies when no real Pro.
    var isProActive: Bool {
        if realProActive { return true }
        #if DEBUG
        if mockProEnabled && !mockExpiredPro { return true }
        #endif
        return false
    }

    /// Free tier allows 5 active public cloud blogs.
    static let freeTierLimit = 5

    var isFreeTier: Bool { !isProActive }

    /// Effective lifetime slots: real purchases + mock slots in DEBUG.
    var effectiveLifetimeSlots: Int {
        var slots = lifetimeBlogSlots
        #if DEBUG
        slots += mockLifetimeSlots
        #endif
        return slots
    }

    /// Total allowed active blogs: Pro = unlimited, Free = 5 + lifetime slots.
    var activeCloudBlogLimit: Int? {
        if isProActive { return nil } // unlimited
        return Self.freeTierLimit + effectiveLifetimeSlots
    }

    /// Human-readable plan name for Settings display.
    var currentPlanDisplayName: String {
        if realProActive {
            switch proPlanType {
            case "monthly": return "Pro Monthly"
            case "yearly": return "Pro Yearly"
            default: return "Pro"
            }
        }
        #if DEBUG
        if mockProEnabled && !mockExpiredPro { return "Pro (Mock)" }
        if mockProEnabled && mockExpiredPro { return "Free (Mock Expired)" }
        #endif
        return "Free"
    }

    /// Formatted expiration date string, or nil.
    var expirationDisplayString: String? {
        guard let date = proExpirationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: - Persistence Keys

    private enum Keys {
        static let realProActive = "bloggo.entitlement.isProActive"
        static let proExpirationDate = "bloggo.entitlement.proExpirationDate"
        static let proPlanType = "bloggo.entitlement.proPlanType"
        static let lifetimeBlogSlots = "bloggo.entitlement.lifetimeBlogSlots"
        static let lifetimeAllocatedBlogIDs = "bloggo.entitlement.lifetimeAllocatedBlogIDs"
        static let lastRestoreDate = "bloggo.entitlement.lastRestoreDate"
    }

    // MARK: - Init

    private init() {
        loadFromDefaults()
        #if DEBUG
        loadMockDefaults()
        #endif
    }

    // MARK: - Load / Save

    private func loadFromDefaults() {
        let defaults = UserDefaults.standard
        realProActive = defaults.bool(forKey: Keys.realProActive)
        proExpirationDate = defaults.object(forKey: Keys.proExpirationDate) as? Date
        proPlanType = defaults.string(forKey: Keys.proPlanType)
        lifetimeBlogSlots = defaults.integer(forKey: Keys.lifetimeBlogSlots)
        lastRestoreDate = defaults.object(forKey: Keys.lastRestoreDate) as? Date

        if let data = defaults.data(forKey: Keys.lifetimeAllocatedBlogIDs),
           let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            lifetimeAllocatedBlogIDs = ids
        }
    }

    private func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(realProActive, forKey: Keys.realProActive)
        defaults.set(proExpirationDate, forKey: Keys.proExpirationDate)
        defaults.set(proPlanType, forKey: Keys.proPlanType)
        defaults.set(lifetimeBlogSlots, forKey: Keys.lifetimeBlogSlots)
        defaults.set(lastRestoreDate, forKey: Keys.lastRestoreDate)

        if let data = try? JSONEncoder().encode(lifetimeAllocatedBlogIDs) {
            defaults.set(data, forKey: Keys.lifetimeAllocatedBlogIDs)
        }
    }

    // MARK: - Handle Transactions

    /// Called after a successful purchase or from the transaction listener.
    func handleTransaction(_ transaction: Transaction, productID: String) async {
        if ProductID.proIDs.contains(productID) {
            realProActive = true
            proExpirationDate = transaction.expirationDate
            proPlanType = productID == ProductID.proMonthly ? "monthly" : "yearly"
            saveToDefaults()
            CreatedRecapBlogStore.shared.enforceArchiveRules()
        } else if productID == ProductID.lifetimeBlog {
            lifetimeBlogSlots += 1
            saveToDefaults()
            CreatedRecapBlogStore.shared.enforceArchiveRules()
        }
    }

    // MARK: - Refresh from StoreKit

    /// Re-check all current entitlements from StoreKit (called on launch, foreground, restore).
    /// Returns true if any Pro entitlement was found.
    @discardableResult
    func refreshEntitlements() async -> Bool {
        var foundPro = false
        var expDate: Date?
        var planType: String?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if ProductID.proIDs.contains(transaction.productID) {
                if transaction.revocationDate == nil {
                    foundPro = true
                    expDate = transaction.expirationDate
                    planType = transaction.productID == ProductID.proMonthly ? "monthly" : "yearly"
                }
            }
        }

        let wasProActive = isProActive
        realProActive = foundPro
        proExpirationDate = expDate
        proPlanType = foundPro ? planType : nil

        if !foundPro {
            proExpirationDate = nil
            proPlanType = nil
        }

        lastRestoreDate = Date()
        saveToDefaults()

        if wasProActive != isProActive {
            CreatedRecapBlogStore.shared.enforceArchiveRules()
        }

        return foundPro
    }

    // MARK: - Lifetime Slot Allocation

    /// Allocate a lifetime slot to a specific blog. Returns true if successful.
    @discardableResult
    func allocateLifetimeSlot(toBlogID blogID: UUID) -> Bool {
        guard !lifetimeAllocatedBlogIDs.contains(blogID) else { return true }
        let usedSlots = lifetimeAllocatedBlogIDs.count
        guard usedSlots < effectiveLifetimeSlots else { return false }
        lifetimeAllocatedBlogIDs.insert(blogID)
        saveToDefaults()
        return true
    }

    /// Deallocate a lifetime slot from a blog (e.g., blog deleted).
    func deallocateLifetimeSlot(fromBlogID blogID: UUID) {
        lifetimeAllocatedBlogIDs.remove(blogID)
        saveToDefaults()
    }

    /// Check if a specific blog has entitlement (Pro active, or within free limit, or has lifetime slot).
    func blogHasEntitlement(blogID: UUID, blogIndex: Int) -> Bool {
        if isProActive { return true }
        if lifetimeAllocatedBlogIDs.contains(blogID) { return true }
        if blogIndex < Self.freeTierLimit { return true }
        return false
    }

    /// Whether sharing is allowed for a given blog.
    func canShareBlog(blogID: UUID, isActive: Bool, blogIndex: Int) -> Bool {
        guard isActive else { return false }
        return blogHasEntitlement(blogID: blogID, blogIndex: blogIndex)
    }

    /// Whether cloud blog editing is allowed (Pro only).
    var canEditCloudBlogs: Bool {
        true
    }
}
