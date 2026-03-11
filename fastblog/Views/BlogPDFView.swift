import SwiftUI

struct BlogPDFView: View {
    let draft: RecapBlogDetail
    let mapSnapshots: [UUID: UIImage] // Key: Day ID
    let preloadedImages: [UUID: UIImage] // Key: Photo ID (or cover photo asset ID)
    
    // US Letter size in points (72 points per inch)
    // 8.5 x 11 inches = 612 x 792 points
    let contentWidth: CGFloat = 540 // 612 - 72 (1 inch margins total)
    
    var body: some View {
        VStack(spacing: 0) {
            // Cover Page content
            coverPage
            
            // Days
            ForEach(draft.days) { day in
                daySection(day: day)
            }
        }
        .frame(width: contentWidth)
        .padding(36) // Margin for the entire block
        .background(Color.white) // Force white background for PDF
        // Apply global text colors for light mode since paper is white
        .environment(\.colorScheme, .light)
    }
    
    // Sentinel UUID used by PDFExportService to store the cover photo
    private static let coverPhotoUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    @ViewBuilder
    private var coverPage: some View {
        VStack(spacing: 24) {
            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: contentWidth, height: contentWidth * 1.2)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: contentWidth, height: contentWidth * 1.2)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            
            VStack(spacing: 8) {
                Text(draft.title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                
                Text(tripDurationText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 40)
        }
    }
    
    @ViewBuilder
    private func daySection(day: RecapBlogDay) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Day Header
            VStack(alignment: .leading, spacing: 4) {
                Text(day.shortDateText)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                if let caption = day.dayCaption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(caption)
                        .font(.body)
                        .foregroundColor(.black.opacity(0.8))
                }
            }
            .padding(.top, 40) // Space before each day
            
            // Map Snapshot
            if let mapImage = mapSnapshots[day.id] {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: contentWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Moments (Unrolled horizontally scrolled stops into a vertical list)
            ForEach(Array(day.placeStops.enumerated()), id: \.element.id) { index, stop in
                placeStopSection(stop: stop, index: index + 1)
            }
        }
    }
    
    @ViewBuilder
    private func placeStopSection(stop: PlaceStop, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Place Header
            HStack(spacing: 8) {
                Text("\(index)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.blue))
                
                Text(stop.placeTitle)
                    .font(.headline)
                    .foregroundColor(.black)
                    
                Spacer()
            }
            
            if let story = stop.overallStory, !story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(story)
                    .font(.body)
                    .foregroundColor(.black.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Photos
            ForEach(stop.photos.filter(\.isIncluded)) { photo in
                VStack(alignment: .leading, spacing: 12) {
                    if let img = preloadedImages[photo.id] {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit() // Maintain aspect ratio for PDF
                            .frame(maxWidth: contentWidth)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    if let caption = photo.caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(caption)
                            .font(.subheadline)
                            .foregroundColor(.black.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 24)
    }
    
    private var tripDurationText: String {
        guard let firstDate = draft.days.first?.date,
              let lastDate = draft.days.last?.date else {
            return ""
        }
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
    
    /// Resolves the cover photo from preloaded images.
    /// PDFExportService stores it under a sentinel UUID, and also maps it
    /// to any matching RecapPhoto id.
    private var coverImage: UIImage? {
        // 1. Try sentinel UUID (always set by PDFExportService)
        if let img = preloadedImages[Self.coverPhotoUUID] {
            return img
        }
        // 2. Try matching a RecapPhoto whose localIdentifier == cover id
        if let coverId = draft.selectedCoverPhotoIdentifier {
            let allPhotos = draft.days.flatMap(\.placeStops).flatMap(\.photos)
            if let match = allPhotos.first(where: { $0.localIdentifier == coverId }) {
                return preloadedImages[match.id]
            }
        }
        // 3. Fallback: first included photo
        let firstIncluded = draft.days.flatMap(\.placeStops).flatMap(\.photos).first(where: \.isIncluded)
        if let first = firstIncluded {
            return preloadedImages[first.id]
        }
        return nil
    }
}
