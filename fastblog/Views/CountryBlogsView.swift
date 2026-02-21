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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(section.blogs) { blog in
                    Button {
                        localSelectedBlog = blog
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            TripCoverImage(theme: blog.coverImageName, coverAssetIdentifier: blog.coverAssetIdentifier)
                                .frame(height: 250)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    if createdRecapStore.isBlogInCloud(blogId: blog.sourceTripId) {
                                        Image(systemName: "icloud.and.arrow.up")
                                            .font(.body)
                                            .foregroundColor(.green)
                                            .padding(8)
                                            .background(Circle().fill(Color.white))
                                            .clipShape(Circle())
                                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                                            .padding(12)
                                            .onTapGesture {
                                                blogToRemove = blog
                                                showRemoveCloudPopup = true
                                            }
                                    }
                                }
                                .overlay(alignment: .bottomLeading) {
                                    if blog.lastEditedAt == nil {
                                        Text("Draft")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(6)
                                            .padding(12)
                                    }
                                }
                            
                            VStack(alignment: .leading, spacing: 4) {
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
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 24)
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
}
