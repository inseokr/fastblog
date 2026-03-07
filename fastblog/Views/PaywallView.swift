//
//  PaywallView.swift
//  fastblog
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoreKitManager.shared
    @ObservedObject private var entitlements = EntitlementManager.shared
    
    @State private var selectedPlanID: String = ProductID.proYearly
    @State private var isAnimatingCTA = false
    
    // Deep Navy theme
    private let backgroundColor = Color(red: 0.02, green: 0.05, blue: 0.12)
    private let cardBackgroundColor = Color(red: 0.08, green: 0.11, blue: 0.2)
    
    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundColor
                .ignoresSafeArea()
            
            // Subtle blurred background element
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: -100, y: -200)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    headerSection
                    pricingSection
                    featureSection
                    expirationSection
                    Spacer(minLength: 120) // Space for sticky button
                }
                .padding(.top, 40)
            }
            
            stickyCTASection
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.3))
                    .padding(20)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimatingCTA = true
            }
        }
    }
    
    // MARK: - Hero Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Make Every Trip\nCount")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
            
            Text("Create blogs faster than ever!")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 40)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Pricing Section
    private var pricingSection: some View {
        VStack(spacing: 16) {
            if let monthly = store.proMonthly {
                PricingCard(
                    id: ProductID.proMonthly,
                    title: "Monthly",
                    price: monthly.displayPrice,
                    subtext: "/ month",
                    isSelected: selectedPlanID == ProductID.proMonthly,
                    isBestValue: false,
                    onSelect: { selectedPlanID = ProductID.proMonthly }
                )
            }
            
            if let yearly = store.proYearly {
                PricingCard(
                    id: ProductID.proYearly,
                    title: "Yearly",
                    price: yearly.displayPrice,
                    subtext: "/ year",
                    isSelected: selectedPlanID == ProductID.proYearly,
                    isBestValue: true,
                    onSelect: { selectedPlanID = ProductID.proYearly }
                )
            }
            
            if let lifetime = store.lifetimeBlog {
                PricingCard(
                    id: ProductID.lifetimeBlog,
                    title: "Lifetime Blog",
                    price: lifetime.displayPrice,
                    subtext: "per blog",
                    isSelected: selectedPlanID == ProductID.lifetimeBlog,
                    isBestValue: false,
                    onSelect: { selectedPlanID = ProductID.lifetimeBlog }
                )
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Features Section
    private var featureSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pro Includes:")
                    .font(.headline)
                    .foregroundColor(.white)
                
                FeatureRow(text: "Unlimited cloud blogs", isPro: true)
                FeatureRow(text: "Unlimited sharing", isPro: true)
                FeatureRow(text: "Cloud editing", isPro: true)
                FeatureRow(text: "Personal blog website", isPro: true)
            }
            .padding(20)
            .background(cardBackgroundColor.opacity(0.5))
            .cornerRadius(16)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Free Plan:")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.6))
                
                FeatureRow(text: "500 MB cloud storage", isPro: false)
                FeatureRow(text: "Limited editing", isPro: false)
            }
            .padding(20)
            .background(cardBackgroundColor.opacity(0.3))
            .cornerRadius(16)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Expiration Section
    private var expirationSection: some View {
        VStack(spacing: 8) {
            Text("WHEN PRO EXPIRES")
                .font(.caption2.bold())
                .foregroundColor(.white.opacity(0.4))
                .kerning(1)
            
            HStack(spacing: 20) {
                ExpireItem(icon: "checkmark.circle.fill", text: "500 MB storage kept")
                ExpireItem(icon: "archivebox.fill", text: "Old blogs archived")
                ExpireItem(icon: "eye.fill", text: "Visible locally")
            }
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - Sticky CTA
    private var stickyCTASection: some View {
        VStack(spacing: 12) {
            Button {
                purchaseSelected()
            } label: {
                Text(selectedPlanID == ProductID.lifetimeBlog ? "Purchase Slot" : "Start Pro")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(colors: [Color.blue, Color.blue.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    )
                    .cornerRadius(28)
                    .shadow(color: Color.blue.opacity(0.4), radius: 10, y: 5)
                    .scaleEffect(isAnimatingCTA ? 1.02 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(store.purchaseState == .purchasing)
            
            HStack(spacing: 16) {
                Button("Cancel anytime") { }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                
                Text("•")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.2))
                
                Button("Restore purchases") {
                    Task { await store.restorePurchases() }
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
            }
            
            Text("Your memories deserve more than five blogs.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .background(
            backgroundColor
                .opacity(0.9)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
        )
    }
    
    private func purchaseSelected() {
        if selectedPlanID == ProductID.proYearly, let yearly = store.proYearly {
            Task { await store.purchase(yearly) }
        } else if selectedPlanID == ProductID.proMonthly, let monthly = store.proMonthly {
            Task { await store.purchase(monthly) }
        } else if selectedPlanID == ProductID.lifetimeBlog, let lifetime = store.lifetimeBlog {
            Task { await store.purchase(lifetime) }
        }
    }
}

// MARK: - Subcomponents

private struct PricingCard: View {
    let id: String
    let title: String
    let price: String
    let subtext: String
    let isSelected: Bool
    let isBestValue: Bool
    var onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    
                    HStack(alignment: .bottom, spacing: 2) {
                        Text(price)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text(subtext)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.bottom, 2)
                    }
                }
                
                Spacer()
                
                if isBestValue {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("SAVE 58%")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        
                        Text("BEST VALUE")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
                
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.white.opacity(0.2), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(red: 0.1, green: 0.14, blue: 0.25))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .shadow(color: isSelected ? Color.blue.opacity(0.2) : Color.clear, radius: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct FeatureRow: View {
    let text: String
    let isPro: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isPro ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isPro ? .blue : .white.opacity(0.3))
                .font(.system(size: 16, weight: .semibold))
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(isPro ? 0.9 : 0.6))
        }
    }
}

private struct ExpireItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
            Text(text)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(width: 80)
        }
    }
}

#Preview {
    PaywallView()
}
