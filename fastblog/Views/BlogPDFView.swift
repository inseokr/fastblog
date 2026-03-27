import SwiftUI

struct BlogPDFView: View {
    let draft: RecapBlogDetail
    let mapSnapshots: [UUID: UIImage] // Key: Day ID
    let preloadedImages: [UUID: UIImage] // Key: Photo ID (or cover photo asset ID)

    // US Letter size in points (72 points per inch)
    // 8.5 x 11 inches = 612 x 792 points
    let contentWidth: CGFloat = 540 // 612 - 72 (1 inch margins total)
    private let accentColor = Color(red: 0.18, green: 0.38, blue: 0.88)
    private let cardBackground = Color(red: 0.96, green: 0.97, blue: 0.99)

    var body: some View {
        VStack(spacing: 0) {
            // Cover Page (Option A: full-bleed hero + gradient overlay)
            coverPage

            // Days
            ForEach(Array(draft.days.enumerated()), id: \.element.id) { index, day in
                daySection(day: day, dayIndex: index + 1)
            }
        }
        .frame(width: contentWidth)
        .padding(36)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // Sentinel UUID used by PDFExportService to store the cover photo
    private static let coverPhotoUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    // MARK: - Cover Page

    @ViewBuilder
    private var coverPage: some View {
        let pageWidth = contentWidth + 72 // negate 36pt padding on each side
        let pageHeight = pageWidth * 1.3

        ZStack(alignment: .bottom) {
            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: pageWidth, height: pageHeight)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: pageWidth, height: pageHeight)
            }

            // Gradient scrim
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: pageWidth, height: pageHeight * 0.55)

            // Overlaid title
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.title)
                    .font(Font.custom("Georgia-Bold", size: 44))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(tripDurationText)
                    .font(Font.custom("Georgia", size: 15))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(width: pageWidth, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.bottom, 48)
        }
        .padding(.horizontal, -36) // bleed beyond margin
    }

    // MARK: - Day Section

    @ViewBuilder
    private func daySection(day: RecapBlogDay, dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Full-width accent rule
            Rectangle()
                .fill(accentColor)
                .frame(height: 3)
                .padding(.top, 48)

            // Day header with watermark number (Option C)
            ZStack(alignment: .leading) {
                Text("\(dayIndex)")
                    .font(.system(size: 110, weight: .heavy))
                    .foregroundColor(accentColor.opacity(0.07))
                    .offset(x: -8, y: -8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DAY \(dayIndex)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accentColor)
                        .tracking(2.5)

                    Text(day.shortDateText)
                        .font(Font.custom("Georgia-Bold", size: 26))
                        .foregroundColor(.black)
                }
            }
            .frame(height: 56)

            if let caption = day.dayCaption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(caption)
                    .font(Font.custom("Georgia-Italic", size: 15))
                    .foregroundColor(.black.opacity(0.75))
                    .lineSpacing(7)
            }

            // Map Snapshot
            if let mapImage = mapSnapshots[day.id] {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: contentWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Place stops
            ForEach(Array(day.placeStops.enumerated()), id: \.element.id) { index, stop in
                placeStopSection(stop: stop, index: index + 1)
            }
        }
    }

    // MARK: - Place Stop Section (Option D: sidebar for 1 photo, strip for many)

    @ViewBuilder
    private func placeStopSection(stop: PlaceStop, index: Int) -> some View {
        let includedPhotos = stop.photos.filter(\.isIncluded)
        let story = stop.overallStory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasStory = !story.isEmpty
        let cardPadding: CGFloat = 14

        VStack(alignment: .leading, spacing: 0) {
            // Place badge + title
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(accentColor)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Text("\(index)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    )

                Text(stop.placeTitle)
                    .font(Font.custom("Georgia-Bold", size: 17))
                    .foregroundColor(.black)

                Spacer()
            }
            .padding(.horizontal, cardPadding)
            .padding(.top, cardPadding)
            .padding(.bottom, 10)
            .background(cardBackground)

            if includedPhotos.count == 1 {
                // Photo-left, text-right sidebar
                let photoWidth = contentWidth * 0.42

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let img = preloadedImages[includedPhotos[0].id] {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: photoWidth, height: photoWidth * 0.85)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .clipped()
                        }
                        if let caption = includedPhotos[0].caption,
                           !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(caption)
                                .font(Font.custom("Georgia-Italic", size: 10))
                                .foregroundColor(.gray)
                                .frame(width: photoWidth)
                        }
                    }

                    if hasStory {
                        Text(story)
                            .font(Font.custom("Georgia", size: 15))
                            .foregroundColor(.black.opacity(0.88))
                            .lineSpacing(7)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, cardPadding)
                .padding(.bottom, cardPadding)
                .background(cardBackground)
            } else {
                // Multiple photos: story first, then each photo with matching background
                if hasStory {
                    Text(story)
                        .font(Font.custom("Georgia", size: 15))
                        .foregroundColor(.black.opacity(0.88))
                        .lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, cardPadding)
                        .padding(.bottom, 10)
                        .background(cardBackground)
                }

                ForEach(Array(includedPhotos.enumerated()), id: \.element.id) { photoIndex, photo in
                    let isLast = photoIndex == includedPhotos.count - 1
                    VStack(alignment: .leading, spacing: 6) {
                        if let img = preloadedImages[photo.id] {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: contentWidth - cardPadding * 2)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        if let caption = photo.caption,
                           !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(caption)
                                .font(Font.custom("Georgia-Italic", size: 11))
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, cardPadding)
                    .padding(.bottom, isLast ? cardPadding : 10)
                    .background(cardBackground)
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 20)
    }

    // MARK: - Helpers

    private var tripDurationText: String {
        guard let firstDate = draft.days.first?.date,
              let lastDate = draft.days.last?.date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dayCount = draft.days.count
        if Calendar.current.isDate(firstDate, equalTo: lastDate, toGranularity: .year) {
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "yyyy"
            return "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate)), \(yearFormatter.string(from: lastDate)) · \(dayCount) day\(dayCount == 1 ? "" : "s")"
        }
        formatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: firstDate)) – \(formatter.string(from: lastDate)) · \(dayCount) day\(dayCount == 1 ? "" : "s")"
    }

    private var coverImage: UIImage? {
        if let img = preloadedImages[Self.coverPhotoUUID] { return img }
        if let coverId = draft.selectedCoverPhotoIdentifier {
            let allPhotos = draft.days.flatMap(\.placeStops).flatMap(\.photos)
            if let match = allPhotos.first(where: { $0.localIdentifier == coverId }) {
                return preloadedImages[match.id]
            }
        }
        let firstIncluded = draft.days.flatMap(\.placeStops).flatMap(\.photos).first(where: \.isIncluded)
        if let first = firstIncluded { return preloadedImages[first.id] }
        return nil
    }
}
