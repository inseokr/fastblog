//
//  SubscriptionSettingsView.swift
//  fastblog
//
//  Subscription section for the Settings page. Displays current plan,
//  upgrade options, lifetime blog purchase, restore purchases,
//  and DEBUG-only mock entitlement toggles.
//

import Combine
import StoreKit
import SwiftUI

struct SubscriptionSettingsView: View {
    @ObservedObject private var entitlements = EntitlementManager.shared
    @ObservedObject private var store = StoreKitManager.shared
    @State private var showFreeTierSheet = false
    @State private var showPaywall = false

    var body: some View {
        // Main subscription section
        Section {
            currentPlanRow
            if !entitlements.isProActive {
                proTeaserButton
            }
            lifetimeBlogRow
            restoreRow
        } header: {
            Text("Subscription")
        } footer: {
            Text("When Pro expires, your blogs within 500 MB of storage remain in the cloud. All blogs are still stored locally.")
        }

        // DEBUG-only mock entitlements section
        #if DEBUG
        mockEntitlementSection
        #endif
    }

    // MARK: - Current Plan (tappable)

    private var currentPlanRow: some View {
        Button {
            showFreeTierSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Plan")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text(entitlements.currentPlanDisplayName)
                        .font(.headline)
                        .foregroundColor(.blue)
                    
                    if entitlements.isProActive, let expString = entitlements.expirationDisplayString {
                        Text("Renews \(expString)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                
                if entitlements.effectiveLifetimeSlots > 0 {
                    Text("\(entitlements.effectiveLifetimeSlots) Lifetime slot\(entitlements.effectiveLifetimeSlots == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 4)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .contentShape(Rectangle()) // Ensures the whole row is tappable
        }
        .buttonStyle(.plain) // Prevents the whole row from highlighting if not desired, or use .automatic
        .sheet(isPresented: $showFreeTierSheet) {
            FreeTierDetailSheet()
        }
    }

    @ViewBuilder
    private var proTeaserButton: some View {
        Button {
            showPaywall = true
        } label: {
            HStack {
                Label {
                    Text("Unlock Pro Features")
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.blue)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Lifetime Blog

    @ViewBuilder
    private var lifetimeBlogRow: some View {
        if let product = store.lifetimeBlog {
            Button {
                Task { await store.purchase(product) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Buy Lifetime Blog Slot")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(product.displayPrice) — keeps 1 extra blog active forever")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    upgradeChevron
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.purchaseState == .purchasing)
        }
    }

    // MARK: - Restore

    private var restoreRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await store.restorePurchases() }
            } label: {
                HStack {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    Spacer()
                    if store.purchaseState == .loading {
                        ProgressView()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.purchaseState != .idle)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    // Show last checked timestamp if available.
                    if let lastDate = entitlements.lastRestoreDate {
                        Text("Last checked \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    
                    // Show result message after a restore attempt.
                    if let message = entitlements.restoreResultMessage {
                        Text(message)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - DEBUG Mock Entitlements

    #if DEBUG
    private var mockEntitlementSection: some View {
        Section {
            Toggle("Mock Pro Access", isOn: $entitlements.mockProEnabled)

            if entitlements.mockProEnabled {
                Toggle("Mock Expired Pro", isOn: $entitlements.mockExpiredPro)
            }

            Stepper(value: $entitlements.mockLifetimeSlots, in: 0...50) {
                HStack {
                    Text("Mock Lifetime Blog Slots")
                    Spacer()
                    Text("\(entitlements.mockLifetimeSlots)")
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
        } header: {
            Text("Dev Only — Mock Subscriptions")
        } footer: {
            Text("These toggles simulate entitlements for testing. Real StoreKit purchases always override mocks. Not included in release builds.")
        }
    }
    #endif

    private var upgradeChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.secondary.opacity(0.5))
    }
}

// MARK: - Free Tier Detail Sheet

/// Sheet explaining what the Free tier includes and what happens when Pro expires.
private struct FreeTierDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var entitlements = EntitlementManager.shared

    var body: some View {
        NavigationStack {
            List {
                // Current status
                Section {
                    Label(entitlements.currentPlanDisplayName, systemImage: "crown.fill")
                        .font(.headline)
                    if entitlements.isProActive, let exp = entitlements.expirationDisplayString {
                        Label("Renews \(exp)", systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if entitlements.effectiveLifetimeSlots > 0 {
                        Label("\(entitlements.effectiveLifetimeSlots) Lifetime Blog slot\(entitlements.effectiveLifetimeSlots == 1 ? "" : "s")", systemImage: "infinity")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // What Free includes
                Section {
                    featureRow(icon: "doc.on.doc", text: "500 MB cloud storage")
                    featureRow(icon: "square.and.arrow.up", text: "Sharing enabled for all blogs")
                    featureRow(icon: "pencil.slash", text: "Cloud blog editing disabled")
                } header: {
                    Text("Free Tier Includes")
                }

                // What Pro unlocks
                Section {
                    featureRow(icon: "infinity", text: "Unlimited cloud blogs")
                    featureRow(icon: "square.and.arrow.up.fill", text: "Unlimited sharing")
                    featureRow(icon: "pencil", text: "Cloud blog editing enabled")
                    featureRow(icon: "globe", text: "Cloud website for your blogs")
                } header: {
                    Text("Pro Unlocks")
                }

                // What happens when Pro expires
                Section {
                    featureRow(icon: "clock.arrow.circlepath", text: "500 MB storage kept")
                    featureRow(icon: "eye", text: "All blogs still visible locally")
                    featureRow(icon: "arrow.up.circle", text: "Upgrade to Pro for more storage")
                } header: {
                    Text("When Pro Expires")
                }
            }
            .navigationTitle("Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
    }
}
