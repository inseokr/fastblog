import SwiftUI

struct PlaceVisitedDetailView: View {
    let place: VisitedPlaceSummary

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoGrid

                header

                captionsSection

                if !place.relatedBlogs.isEmpty {
                    relatedBlogsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .navigationTitle(place.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var photoGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(place.photos) { photo in
                RecapPhotoThumbnail(photo: photo, cornerRadius: 14, showIcon: false, targetSize: CGSize(width: 500, height: 500))
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(place.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Text(place.country)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Last visited \(place.latestVisitDate.formatted(date: .long, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if place.displayName == "Unknown Place" {
                Button("Add name") {
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var captionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Captions")
                .font(.headline)

            let placeCaption = place.placeCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !placeCaption.isEmpty {
                Text(placeCaption)
                    .font(.body)
            } else if place.photoCaptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No captions yet")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Add a caption to remember what made this place special.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Add caption") {
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
            }

            if !place.photoCaptions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Media notes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(place.photoCaptions, id: \.self) { cap in
                        Text(cap)
                            .font(.body)
                    }
                }
            }
        }
    }

    private var relatedBlogsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Related Blogs")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(place.relatedBlogs) { blog in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(blog.blogTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(blog.blogDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                }
            }
        }
    }
}
