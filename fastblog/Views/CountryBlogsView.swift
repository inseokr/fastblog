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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    var body: some View {
        List {
            ForEach(section.blogs) { blog in
                Button {
                    localSelectedBlog = blog
                } label: {
                    HStack(spacing: 14) {
                        TripCoverImage(theme: blog.coverImageName, coverAssetIdentifier: blog.coverAssetIdentifier)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(blog.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(Self.dateFormatter.string(from: blog.createdAt))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Text("\(blog.tripDurationDays) Day\(blog.tripDurationDays == 1 ? "" : "s") • \(blog.tripDateRangeText ?? "")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            if let editedAt = blog.lastEditedAt {
                                Text("Edited \(editedAt.timeAgoDisplay())")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
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
    }

    private func displayCountryName(_ name: String) -> String {
        name.isEmpty || name == "Unknown" ? "Other" : name
    }
}

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let fullString = formatter.localizedString(for: self, relativeTo: Date())
        return fullString
            .replacingOccurrences(of: " hours", with: " hrs")
            .replacingOccurrences(of: " hour", with: " hr")
            .replacingOccurrences(of: " minutes", with: " min")
            .replacingOccurrences(of: " minute", with: " min")
    }
}
