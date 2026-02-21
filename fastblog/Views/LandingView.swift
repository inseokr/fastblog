//
//  LandingView.swift
//  Capper
//

import Combine
import SwiftUI

struct LandingView: View {
    @Binding var showTrips: Bool
    @Binding var showProfile: Bool
    @Binding var showSeeAll: Bool
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @ObservedObject var tripsViewModel: TripsViewModel
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService

    @State private var showSettings = false
    @State private var showAuth = false
    /// CTA text cycles every 5 seconds: "Tap to Scan" ↔ "Create A Blog Today"
    @State private var ctaIsAlternate = false
    @State private var ctaOpacity: Double = 1
    
    // For local persistence of the selected avatar
    @AppStorage("customProfileImageData") private var customProfileImageData: Data?

    private let landingBackground = Color(red: 5/255, green: 10/255, blue: 48/255)
    private let ctaInterval: TimeInterval = 5

    var body: some View {
        ZStack {
            landingBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("BlogGo")
                        .font(.system(size: 34))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        if authService.isSignedIn {
                            showProfile = true
                        } else {
                            showAuth = true
                        }
                    } label: {
                        if let user = authService.currentUser {
                            // Signed-in avatar
                            if let data = customProfileImageData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(
                                            colors: [Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.1, green: 0.3, blue: 0.8)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ))
                                        .frame(width: 32, height: 32)
                                    Text(user.initials)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        } else {
                            Image(systemName: "person.crop.circle")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                Spacer(minLength: 40)
                scanCTA
                Spacer(minLength: 32)
                recentRecapsSection
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(Timer.publish(every: ctaInterval, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.5)) { ctaOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                ctaIsAlternate.toggle()
                withAnimation(.easeInOut(duration: 0.5)) { ctaOpacity = 1 }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(authService)
        }
        .fullScreenCover(isPresented: $showAuth) {
            AuthView(onAuthenticated: {
                showProfile = true
            })
            .environmentObject(authService)
        }
    }

    /// Success notification card: icon, title, "Tap to view", optional dismiss. Auto-dismisses after 6s; tap opens latest blog.
    private var recapCreatedBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.7, blue: 1), Color(red: 0.3, green: 0.5, blue: 1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Your recap blog is ready!")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("Available in your Profile")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                createdRecapStore.dismissRecapCreatedBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .onTapGesture {
            if let latest = createdRecapStore.recents.first {
                selectedCreatedRecap = latest
            }
            createdRecapStore.dismissRecapCreatedBanner()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                createdRecapStore.dismissRecapCreatedBanner()
            }
        }
    }

    private var scanCTA: some View {
        Button {
            if tripsViewModel.tripDrafts.isEmpty {
                tripsViewModel.startDefaultScan()
            }
            showTrips = true
        } label: {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 220, height: 220)
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        .frame(width: 220, height: 220)
                    ScanningAnimationView(ringCount: 4, ringSpacing: 28, pulseDuration: 1.8)
                        .frame(width: 200, height: 200)
                }
                // Both lines in same spot so they stay centered when cross-fading
                ZStack {
                    Text("Tap to Scan")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity(ctaIsAlternate ? 0 : ctaOpacity)
                    Text("Create A Blog Today")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .opacity(ctaIsAlternate ? ctaOpacity : 0)
                }
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.5), value: ctaIsAlternate)
                .animation(.easeInOut(duration: 0.5), value: ctaOpacity)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var recentRecapsSection: some View {
        if !createdRecapStore.displayRecents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    showSeeAll = true
                } label: {
                    HStack {
                        Text("Recent Blogs")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text("See all")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(createdRecapStore.displayRecents) { recap in
                            CreatedRecapCard(recap: recap)
                                .onTapGesture {
                                    selectedCreatedRecap = recap
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                .frame(height: 120)
            }
            .padding(.top, 16)
            .padding(.bottom, 28)
            .background(Color.black.opacity(0.3))
        }
    }
}

private struct CreatedRecapCard: View {
    let recap: CreatedRecapBlog
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    private static let lastEditedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.doesRelativeDateFormatting = true
        return f
    }()

    @State private var showRemoveCloudPopup = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                TripCoverImage(theme: recap.coverImageName, coverAssetIdentifier: recap.coverAssetIdentifier)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if recap.lastEditedAt == nil {
                    Text("Draft")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(4)
                } else if createdRecapStore.isBlogInCloud(blogId: recap.sourceTripId) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .padding(4)
                        .background(Circle().fill(Color.white))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showRemoveCloudPopup = true
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recap.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                if let range = recap.tripDateRangeText, !range.isEmpty {
                    Text(range)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                Text(lastEditedText)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 220)
        .padding(10)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
        .alert("Remove from Cloud?", isPresented: $showRemoveCloudPopup) {
            Button("Yes", role: .destructive) {
                createdRecapStore.removeFromCloud(blogId: recap.sourceTripId)
            }
            Button("No", role: .cancel) { }
        } message: {
            Text("Are you sure you want to remove this blog from the cloud?")
        }
    }

    private var lastEditedText: String {
        let date = recap.lastEditedAt ?? recap.createdAt
        return "Edited \(Self.lastEditedFormatter.string(from: date))"
    }
}

/// Settings sheet from the home page (gear icon). Includes neighborhood selection.
private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @State private var showNeighborhoodSheet = false
    @State private var showAuth = false
    #if DEBUG
    @AppStorage("capper.tripClustering.debugLogging") private var tripClusteringDebug = false
    #endif

    // For local persistence of the selected avatar
    @AppStorage("customProfileImageData") private var customProfileImageData: Data?

    var body: some View {
        NavigationStack {
            List {
                // Account
                Section {
                    if let user = authService.currentUser {
                        // Signed-in row
                        HStack(spacing: 14) {
                            if let data = customProfileImageData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(
                                            colors: [Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.1, green: 0.3, blue: 0.8)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ))
                                        .frame(width: 40, height: 40)
                                    Text(user.initials)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                if let name = user.displayName, !name.isEmpty {
                                    Text(name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                Text(user.email ?? user.provider.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button(role: .destructive) {
                            authService.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        Button {
                            showAuth = true
                        } label: {
                            HStack {
                                Label("Sign In / Create Account", systemImage: "person.badge.plus")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    if authService.isSignedIn {
                        Text("Your recaps sync to the cloud and can be edited on web.")
                    } else {
                        Text("Sign in to back up your recaps, access them on web, and restore Pro.")
                    }
                }

                Section {
                    Button {
                        showNeighborhoodSheet = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Neighborhood", systemImage: "mappin.circle.fill")
                                if let name = NeighborhoodStore.getDisplayName() {
                                    Text(name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Trip preferences")
                } footer: {
                    Text("Used to exclude nearby photos from trip results. Change this to update which area counts as \"home.\"")
                }

                #if DEBUG
                Section {
                    Toggle("Trip clustering debug logging", isOn: $tripClusteringDebug)
                } header: {
                    Text("Debug")
                } footer: {
                    Text("When on, scan logs why each day merged or split (neighborhood_pass, country_fallback_pass, etc.).")
                }
                #endif

                // Legal at bottom of Settings
                Section {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                    NavigationLink {
                        TermsOfServiceView()
                    } label: {
                        Label("Terms of Service", systemImage: "doc.text.fill")
                    }
                } header: {
                    Text("Legal")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showNeighborhoodSheet) {
                NeighborhoodIntroView(onDismiss: {
                    showNeighborhoodSheet = false
                })
            }
            .fullScreenCover(isPresented: $showAuth) {
                AuthView()
                    .environmentObject(authService)
            }
        }
    }
}

struct AllRecentsSheet: View {
    @ObservedObject var createdRecapStore: CreatedRecapBlogStore
    @Binding var selectedRecap: CreatedRecapBlog?
    @Environment(\.dismiss) private var dismiss
    
    @State private var showRemoveCloudPopup = false
    @State private var blogToRemove: CreatedRecapBlog?

    var body: some View {
        NavigationStack {
            List {
                ForEach(createdRecapStore.recents) { recap in
                    Button {
                        selectedRecap = recap
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            ZStack(alignment: .bottomLeading) {
                                TripCoverImage(theme: recap.coverImageName, coverAssetIdentifier: recap.coverAssetIdentifier)
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                if recap.lastEditedAt == nil {
                                    Text("Draft")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(4)
                                        .padding(3)
                                } else if createdRecapStore.isBlogInCloud(blogId: recap.sourceTripId) {
                                    Image(systemName: "icloud.and.arrow.up")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                        .padding(4)
                                        .background(Circle().fill(Color.white))
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            blogToRemove = recap
                                            showRemoveCloudPopup = true
                                        }
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recap.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(recap.createdAt, style: .date)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Recent Recaps")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Remove from Cloud?", isPresented: $showRemoveCloudPopup, presenting: blogToRemove) { blog in
                Button("Yes", role: .destructive) {
                    createdRecapStore.removeFromCloud(blogId: blog.sourceTripId)
                }
                Button("No", role: .cancel) {
                    blogToRemove = nil
                }
            } message: { blog in
                Text("Are you sure you want to remove this blog from the cloud?")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LandingView(
            showTrips: .constant(false),
            showProfile: .constant(false),
            showSeeAll: .constant(false),
            selectedCreatedRecap: .constant(nil),
            tripsViewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared)
        )
        .environmentObject(CreatedRecapBlogStore.shared)
        .environmentObject(AuthService.shared)
    }
}
