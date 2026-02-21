//
//  ProfileManagementView.swift
//  Capper
//
//  Allows users to view their blogs and manage cloud upload status.
//

import SwiftUI

struct ProfileManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService

    @State private var selectedBlog: CreatedRecapBlog?
    @State private var showAuth = false
    @State private var uploadingBlogId: UUID?
    @State private var uploadProgress: (current: Int, total: Int) = (0, 0)
    @State private var showUploadError = false
    @State private var uploadErrorMessage = ""
    @State private var selectedCountryFilter: String? = nil

    // Remove-from-cloud confirmation
    @State private var showRemoveConfirmation = false
    @State private var blogPendingRemoval: CreatedRecapBlog? = nil

    // MARK: - Derived lists

    private var publishedBlogs: [CreatedRecapBlog] {
        createdRecapStore.recents
            .filter { createdRecapStore.isBlogInCloud(blogId: $0.sourceTripId) }
            .sorted { ($0.tripStartDate ?? .distantPast) > ($1.tripStartDate ?? .distantPast) }
    }

    /// Blogs that have a saved detail on disk but haven't been uploaded yet.
    private var readyToUploadBlogs: [CreatedRecapBlog] {
        createdRecapStore.recents
            .filter { !createdRecapStore.isBlogInCloud(blogId: $0.sourceTripId)
                   && !isBlogDraft($0) }
            .sorted { ($0.tripStartDate ?? .distantPast) > ($1.tripStartDate ?? .distantPast) }
    }

    /// Blogs that have NOT been saved yet (no RecapBlogDetail on disk). Upload is locked.
    private var draftBlogs: [CreatedRecapBlog] {
        createdRecapStore.recents
            .filter { isBlogDraft($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// A blog is a draft when no RecapBlogDetail has been saved for it yet.
    private func isBlogDraft(_ blog: CreatedRecapBlog) -> Bool {
        createdRecapStore.getBlogDetail(blogId: blog.sourceTripId) == nil
    }

    private var notUploadedCountries: [String] {
        let countries = readyToUploadBlogs.compactMap { $0.countryName }
        return Array(Set(countries)).sorted()
    }

    private var filteredNotUploadedBlogs: [CreatedRecapBlog] {
        guard let country = selectedCountryFilter else { return readyToUploadBlogs }
        return readyToUploadBlogs.filter { $0.countryName == country }
    }

    @State private var showDraftsSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(spacing: 24) {

                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                            .padding(.bottom, 4)

                        Text("Manage Your Blogs")
                            .font(.system(.title2, design: .serif).weight(.medium))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)

                        Text("Upload blogs to the cloud so they appear on your profile.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 8)

                    // MARK: - Published Section
                    if !publishedBlogs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.icloud.fill")
                                    .foregroundColor(.green)
                                Text("Published")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(publishedBlogs.count)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)

                            LazyVStack(spacing: 12) {
                                ForEach(publishedBlogs) { blog in
                                    Button {
                                        selectedBlog = blog
                                    } label: {
                                        ProfileManagementRow(
                                            blog: blog,
                                            isPublished: true,
                                            isUploading: false,
                                            uploadProgress: nil,
                                            onToggle: {
                                                blogPendingRemoval = blog
                                                showRemoveConfirmation = true
                                            }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // MARK: - Not Uploaded / Ready-to-Upload Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "icloud.and.arrow.up")
                                .foregroundColor(.blue)
                            Text("Not Uploaded")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(readyToUploadBlogs.count)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)

                        // Country filter pills
                        if notUploadedCountries.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    filterPill(label: "All", isSelected: selectedCountryFilter == nil) {
                                        selectedCountryFilter = nil
                                    }
                                    ForEach(notUploadedCountries, id: \.self) { country in
                                        filterPill(label: country, isSelected: selectedCountryFilter == country) {
                                            selectedCountryFilter = country
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        if filteredNotUploadedBlogs.isEmpty {
                            Text(readyToUploadBlogs.isEmpty ? "All uploaded or still in Draft." : "No blogs here.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredNotUploadedBlogs) { blog in
                                    Button { selectedBlog = blog } label: {
                                        ProfileManagementRow(
                                            blog: blog,
                                            isPublished: false,
                                            isDraft: false,
                                            isUploading: uploadingBlogId == blog.sourceTripId,
                                            uploadProgress: uploadingBlogId == blog.sourceTripId ? uploadProgress : nil,
                                            onToggle: { uploadBlog(blog) }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // MARK: - Drafts Section (not yet saved, upload locked)
                    if !draftBlogs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.orange)
                                Text("My Drafts")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(draftBlogs.count)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .id("drafts-section")

                            Text("Open a draft blog and save it before uploading to the cloud.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)

                            LazyVStack(spacing: 12) {
                                ForEach(draftBlogs) { blog in
                                    Button { selectedBlog = blog } label: {
                                        ProfileManagementRow(
                                            blog: blog,
                                            isPublished: false,
                                            isDraft: true,
                                            isUploading: false,
                                            uploadProgress: nil,
                                            onToggle: { selectedBlog = blog } // Opens blog to finish saving
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .onChange(of: showDraftsSheet) { _, show in
                    if show {
                        withAnimation { proxy.scrollTo("drafts-section", anchor: .top) }
                        showDraftsSheet = false
                    }
                }
            }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedBlog) { blog in
                RecapBlogPageView(
                    blogId: blog.sourceTripId,
                    initialTrip: createdRecapStore.tripDraft(for: blog.sourceTripId)
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .primaryAction) {
                    if !draftBlogs.isEmpty {
                        Button {
                            showDraftsSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                Text("My Drafts")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.orange)
                        }
                    }
                }
            }
            .alert("Upload Failed", isPresented: $showUploadError) {
                if uploadErrorMessage == "Please sign in to upload photos." {
                    Button("Sign In") {
                        showAuth = true
                    }
                    Button("Close", role: .cancel) { }
                } else {
                    Button("OK", role: .cancel) { }
                }
            } message: {
                Text(uploadErrorMessage)
            }
            .alert("Remove from Cloud?", isPresented: $showRemoveConfirmation, presenting: blogPendingRemoval) { blog in
                Button("Yes", role: .destructive) {
                    removeFromCloud(blog)
                }
                Button("No", role: .cancel) {
                    blogPendingRemoval = nil
                }
            } message: { blog in
                Text("Are you sure you want to remove this blog from the cloud?")
            }
            .fullScreenCover(isPresented: $showAuth) {
                AuthView(onAuthenticated: {
                    showAuth = false
                })
                .environmentObject(authService)
            }
        }
    }

    // MARK: - Filter Pill

    private func filterPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Remove from Cloud

    private func removeFromCloud(_ blog: CreatedRecapBlog) {
        createdRecapStore.removeFromCloud(blogId: blog.sourceTripId)
        blogPendingRemoval = nil
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    // MARK: - Upload

    private func uploadBlog(_ blog: CreatedRecapBlog) {
        guard !createdRecapStore.isBlogInCloud(blogId: blog.sourceTripId) else { return }
        guard uploadingBlogId == nil else { return }
        guard AuthService.shared.currentJwtToken != nil else {
            uploadErrorMessage = "Please sign in to upload photos."
            showUploadError = true
            return
        }

        guard var detail = createdRecapStore.getBlogDetail(blogId: blog.sourceTripId) else {
            uploadErrorMessage = "Blog has not been saved yet. Open the blog and save it first."
            showUploadError = true
            return
        }

        var photosToUpload: [(dayIdx: Int, stopIdx: Int, photoIdx: Int, assetId: String)] = []
        for (dIdx, day) in detail.days.enumerated() {
            for (sIdx, stop) in day.placeStops.enumerated() {
                for (pIdx, photo) in stop.photos.enumerated() {
                    if photo.isIncluded && photo.cloudURL == nil,
                       let assetId = photo.localIdentifier {
                        photosToUpload.append((dIdx, sIdx, pIdx, assetId))
                    }
                }
            }
        }

        guard !photosToUpload.isEmpty else { return }

        uploadingBlogId = blog.sourceTripId
        uploadProgress = (0, photosToUpload.count)

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        Task {
            var failCount = 0
            for item in photosToUpload {
                do {
                    let cloudURL = try await APIManager.shared.uploadPhoto(assetIdentifier: item.assetId)
                    detail.days[item.dayIdx].placeStops[item.stopIdx].photos[item.photoIdx].cloudURL = cloudURL
                } catch {
                    failCount += 1
                    print("🚨 Upload failed for asset \(item.assetId): \(error.localizedDescription)")
                }
                uploadProgress.current += 1
            }

            createdRecapStore.saveBlogDetail(detail)
            uploadingBlogId = nil

            if failCount == 0 {
                let snapshot = detail
                let sourceTripId = blog.sourceTripId
                Task {
                    if let blogKey = await APIManager.shared.publishBlog(detail: snapshot) {
                        await MainActor.run {
                            createdRecapStore.setBlogKey(blogId: sourceTripId, blogKey: blogKey)
                        }
                    }
                }
            }

            if failCount > 0 {
                uploadErrorMessage = "\(failCount) photo\(failCount == 1 ? "" : "s") failed to upload. Try again."
                showUploadError = true
            }
        }
    }
}

struct ProfileManagementRow: View {
    let blog: CreatedRecapBlog
    let isPublished: Bool
    var isDraft: Bool = false
    var isUploading: Bool = false
    var uploadProgress: (current: Int, total: Int)?
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail
            AssetPhotoView(
                assetIdentifier: blog.coverAssetIdentifier ?? blog.coverImageName,
                cornerRadius: 12,
                targetSize: CGSize(width: 180, height: 180)
            )
            .frame(width: 60, height: 60)
            .overlay(alignment: .topLeading) {
                if isDraft {
                    Text("DRAFT")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .offset(x: -4, y: -4)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(blog.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if isUploading, let progress = uploadProgress {
                    Text("Uploading \(progress.current)/\(progress.total)\u{2026}")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else if isDraft {
                    Text("Open blog and save to enable upload")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text(blog.tripDateRangeText ?? "Unknown Date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action Button
            Button(action: onToggle) {
                Group {
                    if isUploading {
                        ProgressView()
                            .tint(.blue)
                            .frame(width: 16, height: 16)
                    } else if isDraft {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.icloud")
                            Text("Draft")
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: isPublished ? "checkmark.icloud.fill" : "icloud.and.arrow.up")
                            Text(isPublished ? "Published" : "Upload")
                        }
                    }
                }
                .font(.system(.subheadline, weight: .medium))
                .foregroundColor(isDraft ? .orange : (isPublished ? .green : .blue))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isDraft ? Color.orange.opacity(0.1) : (isPublished ? Color.green.opacity(0.1) : Color.blue.opacity(0.1)))
                )
            }
            .buttonStyle(.plain)
            .disabled(isUploading || isDraft)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(isDraft ? 0.85 : 1.0)
    }
}

#Preview {
    ProfileManagementView()
        .environmentObject(CreatedRecapBlogStore.shared)
}
