//
//  ProfilePageView.swift
//  Capper
//
//  Premium editorial-style Profile page for BlogGo.
//  Minimal, calm, typography-driven.
//
import SwiftUI
import PhotosUI

/// Centralized design system constants for the Profile
struct ProfileTheme {
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let massive: CGFloat = 64
    }
    
    struct Typography {
        /// For the user's display name
        static let profileName = Font.system(.title, design: .serif).weight(.medium)
        /// For the bio
        static let bio = Font.system(.body, design: .default).weight(.regular)
        /// For blog titles in the list
        static let storyTitle = Font.system(.title2, design: .serif).weight(.semibold)
        /// For location & date metadata (small, uppercase, wide)
        static let metadata = Font.system(.caption).weight(.medium)
        /// For the 2-line excerpt
        static let excerpt = Font.system(.subheadline, design: .default)
    }
}

struct ProfilePageView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var authStateManager: AuthStateManager
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    
    @StateObject private var viewModel = MyBlogsProfileViewModel()
    @State private var selectedCountryID: String? = nil
    @State private var showMyMap = false
    @State private var showManagementSheet = false
    /// Local navigation state — avoids conflicting with the global selectedCreatedRecap binding
    @State private var selectedBlogToOpen: CreatedRecapBlog? = nil
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool
    
    /// Only cloud-published blogs appear on the profile (logged-in view).
    private var publishedBlogs: [CreatedRecapBlog] {
        createdRecapStore.cloudPublishedBlogs.sorted { ($0.tripStartDate ?? .distantPast) > ($1.tripStartDate ?? .distantPast) }
    }

    /// Local anonymous blogs visible when logged out.
    private var localBlogs: [CreatedRecapBlog] {
        createdRecapStore.anonymousDrafts.sorted { ($0.createdAt) > ($1.createdAt) }
    }

    private var uniqueCountries: [String] {
        let countries = publishedBlogs.compactMap { $0.countryName }
        let unique = Array(Set(countries))
        return unique.sorted()
    }

    private var filteredBlogs: [CreatedRecapBlog] {
        var result = publishedBlogs
        if let countryID = selectedCountryID {
            result = result.filter { $0.countryName == countryID }
        }
        
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { blog in
                (blog.title.lowercased().contains(query)) ||
                (blog.countryName?.lowercased().contains(query) == true)
            }
        }
        
        return result
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: ProfileTheme.Spacing.xxl) {
                
                // 1. Centered Hero Section
                ProfileHeroSection()
                    .environmentObject(authService)
                    .environmentObject(createdRecapStore)
                    .environmentObject(authStateManager)
                    .padding(.top, ProfileTheme.Spacing.xl)
                
                // 2. Stories Section — branches on auth state
                VStack(alignment: .leading, spacing: ProfileTheme.Spacing.xl) {
                    if authStateManager.isLoggedIn {
                        // --- LOGGED IN: Published cloud blogs ---
                        Text("Published Blogs")
                            .font(ProfileTheme.Typography.metadata)
                            .textCase(.uppercase)
                            .foregroundColor(.secondary)
                            .kerning(1.2)
                            .padding(.horizontal, ProfileTheme.Spacing.md)

                        if createdRecapStore.isLoading {
                            ProfileLoadingSkeleton()
                        } else if publishedBlogs.isEmpty {
                            ProfileEmptyState {
                                showManagementSheet = true
                            }
                        } else {
                            VStack(alignment: .leading, spacing: ProfileTheme.Spacing.md) {
                                countryFilterBar
                                StoryFeedSection(
                                    blogs: filteredBlogs,
                                    selectedBlog: $selectedBlogToOpen
                                )
                            }
                        }
                    } else {
                        // --- LOGGED OUT: Local anonymous drafts + cloud CTA ---
                        Text("Local Drafts")
                            .font(ProfileTheme.Typography.metadata)
                            .textCase(.uppercase)
                            .foregroundColor(.secondary)
                            .kerning(1.2)
                            .padding(.horizontal, ProfileTheme.Spacing.md)

                        if createdRecapStore.isLoading {
                            ProfileLoadingSkeleton()
                        } else if localBlogs.isEmpty {
                            LocalBlogsEmptyState()
                        } else {
                            StoryFeedSection(
                                blogs: localBlogs,
                                selectedBlog: $selectedBlogToOpen
                            )
                        }

                        // Cloud locked CTA
                        LockedCloudSection()
                            .padding(.horizontal, ProfileTheme.Spacing.md)
                    }
                }
            }
            .padding(.bottom, 140)
        }
        
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    showMyMap = true
                } label: {
                    Image(systemName: "map.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
            searchBar
        }
        .allowsHitTesting(true)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        Task {
                            await prepareShareContent()
                            showShare = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.primary)
                    }
                    
                    Button {
                        // TODO: Open notifications
                    } label: {
                        Image(systemName: "bell")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if !shareItems.isEmpty {
                ShareSheet(items: shareItems)
            }
        }
        .sheet(isPresented: $showManagementSheet) {
            ProfileManagementView()
                .environmentObject(createdRecapStore)
        }
        .onAppear {
            viewModel.loadUnsavedTrips()
        }
        .navigationDestination(isPresented: $showMyMap) {
            MyMapView(selectedCreatedRecap: $selectedCreatedRecap)
        }
        .navigationDestination(item: $selectedBlogToOpen) { recap in
            RecapBlogPageView(
                blogId: recap.sourceTripId,
                initialTrip: createdRecapStore.tripDraft(for: recap.sourceTripId)
            )
        }
    }

    @State private var showShare = false
    @State private var shareItems: [Any] = []

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search city or blog title", text: $viewModel.searchText)
                .foregroundColor(.primary)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onTapGesture {
                    isSearchActive = true
                }
            if isSearchActive {
                Button {
                    viewModel.searchText = ""
                    isSearchFocused = false
                    isSearchActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }


    private func prepareShareContent() async {
        // Simple share content for the profile
        var items: [Any] = []
        if let name = authService.currentUser?.displayName ?? authService.currentUser?.email {
            items.append("Check out \(name)'s travel blogs on BlogGo!")
        }
        
        // Include the profile photo if available
        if let data = UserDefaults.standard.data(forKey: "customProfileImageData"), let uiImage = UIImage(data: data) {
            items.append(uiImage)
        }
        
        shareItems = items
    }
    
    private var countryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: {
                    selectedCountryID = nil
                }) {
                    Text("All")
                        .font(.subheadline)
                        .fontWeight(selectedCountryID == nil ? .semibold : .regular)
                        .foregroundColor(selectedCountryID == nil ? Color(uiColor: .systemBackground) : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedCountryID == nil ? Color.primary : Color(uiColor: .secondarySystemBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                ForEach(uniqueCountries, id: \.self) { country in
                    Button(action: {
                        selectedCountryID = country
                    }) {
                        Text(country)
                            .font(.subheadline)
                            .fontWeight(selectedCountryID == country ? .semibold : .regular)
                            .foregroundColor(selectedCountryID == country ? Color(uiColor: .systemBackground) : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedCountryID == country ? Color.primary : Color(uiColor: .secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ProfileTheme.Spacing.md)
        }
    }
}

// MARK: - Hero Section
struct ProfileHeroSection: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @State private var showPhotoViewer = false
    @State private var showManagement = false
    @State private var showEditBio = false
    
    // For local persistence of the selected avatar
    @AppStorage("customProfileImageData") private var customProfileImageData: Data?
    
    // For local persistence of the user's bio
    @AppStorage("userBio") private var userBio: String = "Write your bio"
    
    var body: some View {
        VStack(spacing: ProfileTheme.Spacing.md) {
            // Profile Photo
            Button {
                showPhotoViewer = true
            } label: {
                if let data = customProfileImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.1, green: 0.3, blue: 0.8)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 88, height: 88)
                        
                        Text(authService.currentUser?.initials ?? "?")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Name & Bio
            VStack(spacing: ProfileTheme.Spacing.sm) {
                Text(authService.currentUser?.displayName ?? authService.currentUser?.email ?? "Traveler")
                    .font(ProfileTheme.Typography.profileName)
                    .foregroundColor(.primary)
                
                Text(userBio)
                    .font(ProfileTheme.Typography.bio)
                    .foregroundColor(.primary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, ProfileTheme.Spacing.xl)
            }
            
            // Subtle Stats Line
            ProfileStatsLine()
                .padding(.top, ProfileTheme.Spacing.xs)
            
            // Action Buttons
            HStack(spacing: ProfileTheme.Spacing.md) {
                // Edit Bio Button
                Button {
                    showEditBio = true
                } label: {
                    Text("Edit Bio")
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, ProfileTheme.Spacing.lg)
                        .padding(.vertical, ProfileTheme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                }
                
                // Manage Button
                Button {
                    showManagement = true
                } label: {
                    Text("Manage")
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, ProfileTheme.Spacing.lg)
                        .padding(.vertical, ProfileTheme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                }
            }
            .padding(.top, ProfileTheme.Spacing.sm)
        }
        .sheet(isPresented: $showPhotoViewer) {
            ProfilePhotoViewer(customProfileImageData: $customProfileImageData)
                .environmentObject(authService)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showManagement) {
            ProfileManagementView()
                .environmentObject(createdRecapStore)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditBio) {
            EditBioView(bio: $userBio)
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Edit Bio View
struct EditBioView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var bio: String
    
    @State private var draftBio: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("About You")) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $draftBio)
                            .frame(minHeight: 100)
                        if draftBio.isEmpty {
                            Text("Write a short bio to display on your profile. Keep it brief!")
                                .foregroundColor(Color(uiColor: .placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .navigationTitle("Edit Bio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        bio = draftBio
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                draftBio = bio
            }
        }
    }
}

// MARK: - Profile Photo Viewer
struct ProfilePhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @Binding var customProfileImageData: Data?
    
    @State private var selectedItem: PhotosPickerItem?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: ProfileTheme.Spacing.xl) {
                Spacer()
                
                if let data = customProfileImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 250, height: 250)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                } else {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 0.2, green: 0.5, blue: 1), Color(red: 0.1, green: 0.3, blue: 0.8)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 250, height: 250)
                            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                        
                        Text(authService.currentUser?.initials ?? "?")
                            .font(.system(size: 100, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                    Text("Change Photo")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
                .onChange(of: selectedItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            DispatchQueue.main.async {
                                self.customProfileImageData = data
                            }
                        }
                    }
                }
                
                if customProfileImageData != nil {
                    Button("Remove Photo", role: .destructive) {
                        customProfileImageData = nil
                    }
                    .padding(.top, 8)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Reusable BlogCard Component
struct BlogCard: View {
    let blog: CreatedRecapBlog

    /// Resolved username for share links (username → displayName → email fallback).
    static var resolvedUsername: String {
        let user = AuthService.shared.currentUser
        return user?.username ?? user?.displayName ?? user?.email ?? "user"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProfileTheme.Spacing.md) {

            // 16:9 Cover Image
            GeometryReader { proxy in
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let assetId = blog.coverAssetIdentifier, !assetId.isEmpty {
                            AssetPhotoView(
                                assetIdentifier: assetId,
                                cornerRadius: 0,
                                targetSize: CGSize(width: proxy.size.width * 2, height: proxy.size.width * 2 * (9/16))
                            )
                            .frame(width: proxy.size.width, height: proxy.size.width * (9/16))
                            .clipped()
                        } else if let uiImage = UIImage(named: blog.coverImageName) ?? UIImage(contentsOfFile: blog.coverImageName) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.width * (9/16))
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color(uiColor: .secondarySystemBackground))
                                .frame(width: proxy.size.width, height: proxy.size.width * (9/16))
                        }
                    }
                    
                    // Share Button overlay
                    if let key = blog.blogKey,
                       let safeUsername = BlogCard.resolvedUsername.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                       let url = URL(string: "https://ls-beta-84213e85e326.herokuapp.com/trip/\(safeUsername)/\(key)") {
                        ShareLink(
                            item: url,
                            subject: Text(blog.title),
                            message: Text("\(blog.title) – My Recap Blog")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .padding(ProfileTheme.Spacing.sm)
                    }
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            
            // Story Meta & Content
            VStack(alignment: .leading, spacing: ProfileTheme.Spacing.sm) {
                
                // Metadata (Location + Date)
                let location = blog.countryName ?? "Unknown"
                let date = blog.tripDateRangeText ?? ""
                
                Text("\(location) — \(date)".uppercased())
                    .font(ProfileTheme.Typography.metadata)
                    .foregroundColor(.secondary)
                    .kerning(0.5)
                
                // Bold Title
                Text(blog.title)
                    .font(ProfileTheme.Typography.storyTitle)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Excerpt
                let excerptText = "A \(blog.tripDurationDays)-day journey exploring \(blog.totalPlaceVisitCount) memorable places."
                Text(excerptText)
                    .font(ProfileTheme.Typography.excerpt)
                    .foregroundColor(.primary.opacity(0.7))
                    .lineLimit(2)
                    .lineSpacing(4)
                
                // Published Date
                Text("Published \(blog.createdAt.formatted(date: .numeric, time: .omitted))".uppercased())
                    .font(ProfileTheme.Typography.metadata)
                    .foregroundColor(.secondary)
                    .kerning(0.5)
                    .padding(.top, 2)
            }
            .padding(.horizontal, ProfileTheme.Spacing.md)
        }
    }
}

// MARK: - Feed Section
struct StoryFeedSection: View {
    let blogs: [CreatedRecapBlog]
    @Binding var selectedBlog: CreatedRecapBlog?
    
    var body: some View {
        VStack(spacing: ProfileTheme.Spacing.xxl) {
            ForEach(blogs) { blog in
                Button {
                    selectedBlog = blog
                } label: {
                    BlogCard(blog: blog)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Stats Line
struct ProfileStatsLine: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authStateManager: AuthStateManager

    var body: some View {
        if authStateManager.isLoggedIn {
            let published = createdRecapStore.cloudPublishedBlogs
            let countryCount = Set(published.compactMap { $0.countryName }).count
            let blogCount = published.count

            if blogCount > 0 {
                Text("\(countryCount) \(countryCount == 1 ? "Country" : "Countries") \u{2022} \(blogCount) \(blogCount == 1 ? "Blog" : "Blogs")")
                    .font(ProfileTheme.Typography.metadata)
                    .foregroundColor(.secondary)
            } else {
                Text("No published blogs yet")
                    .font(ProfileTheme.Typography.metadata)
                    .foregroundColor(.secondary)
            }
        } else {
            let draftCount = createdRecapStore.anonymousDrafts.count
            Text(draftCount == 0 ? "No local drafts" : "\(draftCount) local \(draftCount == 1 ? "draft" : "drafts")")
                .font(ProfileTheme.Typography.metadata)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Local Blogs Empty State (logged-out)
struct LocalBlogsEmptyState: View {
    var body: some View {
        VStack(spacing: ProfileTheme.Spacing.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text("No local drafts yet")
                .font(ProfileTheme.Typography.storyTitle)
                .foregroundColor(.primary)

            Text("Create a blog from the Trips tab and it will appear here as a local draft.")
                .font(ProfileTheme.Typography.bio)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ProfileTheme.Spacing.massive)
    }
}

// MARK: - Locked Cloud Section (logged-out CTA)
struct LockedCloudSection: View {
    @State private var showAuth = false

    var body: some View {
        VStack(spacing: ProfileTheme.Spacing.md) {
            // Divider line
            HStack {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
            .padding(.bottom, ProfileTheme.Spacing.xs)

            HStack(spacing: ProfileTheme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.12), Color.indigo.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: "lock.icloud")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloud publishing & sharing")
                        .font(.system(.subheadline).weight(.semibold))
                        .foregroundColor(.primary)
                    Text("Sign in to upload blogs, generate links, and access web editing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            Button {
                showAuth = true
            } label: {
                Text("Sign in to unlock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(ProfileTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Empty State View (logged-in)
struct ProfileEmptyState: View {
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(spacing: ProfileTheme.Spacing.md) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)

                Text("No published blogs yet")
                    .font(ProfileTheme.Typography.storyTitle)
                    .foregroundColor(.primary)

                Text("Upload a blog to the cloud and it will appear here on your profile.")
                    .font(ProfileTheme.Typography.bio)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)

                if onTap != nil {
                    Text("Tap to manage blogs")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.blue)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ProfileTheme.Spacing.massive)
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

// MARK: - Loading Skeleton
struct ProfileLoadingSkeleton: View {
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: ProfileTheme.Spacing.xxl) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: ProfileTheme.Spacing.md) {
                    // Image Skeleton
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .aspectRatio(16/9, contentMode: .fit)
                    
                    VStack(alignment: .leading, spacing: ProfileTheme.Spacing.sm) {
                        // Location Date Skeleton
                        Text("Location — Date")
                            .font(ProfileTheme.Typography.metadata)
                        
                        // Title Skeleton
                        Text("This is a placeholder for a two line title")
                            .font(ProfileTheme.Typography.storyTitle)
                        
                        // Excerpt Skeleton
                        Text("This is a placeholder excerpt spanning across two lines to show loading state.")
                            .font(ProfileTheme.Typography.excerpt)
                    }
                    .padding(.horizontal, ProfileTheme.Spacing.md)
                }
            }
        }
        .redacted(reason: .placeholder)
        .opacity(isPulsing ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear {
            isPulsing = true
        }
    }
}
