//
//  CountryBlogsView.swift
//  Capper
//
//  Blogs for a single country: list/grid. Shown when user taps a Country Card.
//

import SwiftUI

struct CountryBlogsView: View {
    let section: CountrySection
    @Binding var selectedBlog: CreatedRecapBlog?
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @State private var localSelectedBlog: CreatedRecapBlog?
    @State private var showMap = false
    @State private var showRemoveCloudPopup = false
    @State private var blogToRemove: CreatedRecapBlog?
    
    // Year filter support
    @State private var selectedYear: Int? = nil

    private var availableYears: [Int] {
        let years = section.blogs.compactMap { blog -> Int? in
            guard let date = blog.tripStartDate ?? blog.tripEndDate else { return nil }
            return Calendar.current.component(.year, from: date)
        }
        return Array(Set(years)).sorted(by: >)
    }
    
    private var filteredAndSortedBlogs: [CreatedRecapBlog] {
        let sorted = section.blogs.sorted {
            ($0.tripStartDate ?? $0.createdAt) > ($1.tripStartDate ?? $1.createdAt)
        }
        
        guard let year = selectedYear else { return sorted }
        return sorted.filter { blog in
            guard let date = blog.tripStartDate ?? blog.tripEndDate else { return false }
            return Calendar.current.component(.year, from: date) == year
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Year Filter Header
                if availableYears.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterPill(label: "All", isSelected: selectedYear == nil) {
                                selectedYear = nil
                            }
                            ForEach(availableYears, id: \.self) { year in
                                filterPill(label: String(year), isSelected: selectedYear == year) {
                                    selectedYear = year
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .background(Color(uiColor: .systemBackground))
                    
                    Divider()
                }

                LazyVStack(spacing: 24) {
                    ForEach(filteredAndSortedBlogs) { blog in
                    Button {
                        localSelectedBlog = blog
                    } label: {
                        CountryBlogRowView(
                            blog: blog,
                            isBlogInCloud: createdRecapStore.isBlogInCloud(blogId: blog.sourceTripId),
                            isDraft: createdRecapStore.getBlogDetail(blogId: blog.sourceTripId) == nil,
                            onRemoveFromCloud: {
                                blogToRemove = blog
                                showRemoveCloudPopup = true
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        }
        .navigationTitle(displayCountryName(section.countryName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMap = true
                } label: {
                    Image(systemName: "map")
                }
            }
        }
        .navigationDestination(isPresented: $showMap) {
            CountryMapView(
                countryName: section.countryName,
                blogs: filteredAndSortedBlogs,
                selectedCreatedRecap: $localSelectedBlog
            )
            .environmentObject(createdRecapStore)
        }
        .navigationDestination(item: $localSelectedBlog) { recap in
            RecapBlogPageView(
                blogId: recap.sourceTripId,
                initialTrip: createdRecapStore.tripDraft(for: recap.sourceTripId)
            )
        }
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
    }

    private func displayCountryName(_ name: String) -> String {
        name.isEmpty || name == "Unknown" ? "Other" : name
    }
    
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
}

struct CountryBlogRowView: View {
    let blog: CreatedRecapBlog
    let isBlogInCloud: Bool
    let isDraft: Bool
    let onRemoveFromCloud: () -> Void
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TripCoverImage(theme: blog.coverImageName, coverAssetIdentifier: blog.coverAssetIdentifier)
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if !isDraft {
                        if isBlogInCloud {
                            Image(systemName: "checkmark.icloud.fill")
                                .font(.body)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(Color.green))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                                .padding(12)
                                .onTapGesture(perform: onRemoveFromCloud)
                        } else {
                            Image(systemName: "icloud.and.arrow.up")
                                .font(.body)
                                .foregroundColor(.orange)
                                .padding(8)
                                .background(Circle().fill(Color.white))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                                .padding(12)
                        }
                    }
                }
                .overlay(alignment: .center) {
                    if isDraft {
                        ZStack {
                            // Semi-transparent dim over the whole cover
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.45))
                            // Centered "DRAFT" badge
                            VStack(spacing: 6) {
                                Image(systemName: "pencil.line")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("DRAFT")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundColor(.white)
                                    .tracking(2)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                        }
                    }
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(blog.tripDateRangeText ?? "")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Text(blog.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Text("\(blog.totalPlaceVisitCount) Place\(blog.totalPlaceVisitCount == 1 ? "" : "s") • \(blog.tripDurationDays) Day\(blog.tripDurationDays == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Edited \(Self.dateFormatter.string(from: blog.lastEditedAt ?? blog.createdAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
    }
}
