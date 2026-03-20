// fastblog/Views/StoryBook/PhotoContinuationBlockView.swift
import SwiftUI
import Foundation
import UIKit

struct PhotoContinuationBlockView: View {
    let placeName: String
    let placeSubtitle: String?
    let placeMarkerNumber: Int
    let placeMarkerType: PlaceMarkerType
    let photos: [PhotoContent]
    /// Image frame height for story-mode layout packing (shared by all photos in this block).
    let photoImageHeight: CGFloat
    let photoGridLayout: PhotoGridLayout
    let showOverflowHeader: Bool
    let photoShapeOptions: PDFPhotoShapeOptions
    let blogColor: BlogColor
    let fontTheme: FontTheme

    var body: some View {
        let horizontalPadding: CGFloat = 32 // matches DayContentPageView's .padding(.horizontal, 16) × 2
        let pageWidth = max(0, StoryRenderMetrics.clampedScreenWidth - horizontalPadding)
        let gap: CGFloat = 8
        let photoWidth: CGFloat = {
            switch photoGridLayout {
            case .twoColumn:
                return (pageWidth - gap) / 2
            case .single, .stackedSingles:
                return pageWidth
            }
        }()

        let markerColor: Color = {
            switch placeMarkerType {
            case .start:
                return .green
            case .middle:
                return .blue
            case .end:
                return .orange
            }
        }()
        let markerSize: CGFloat = 16
        let markerNumberFontSize: CGFloat = 10
        let markerView = ZStack {
            Circle()
                .fill(markerColor)
                .frame(width: markerSize, height: markerSize)
            Text("\(placeMarkerNumber)")
                .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: markerNumberFontSize, weight: .bold)))
                .foregroundColor(Color.white)
        }

        VStack(alignment: .leading, spacing: 6) {
            if showOverflowHeader {
                HStack(spacing: 4) {
                    let titleFontSize: CGFloat = 14
                    let titleColor = blogColor == .black ? Color.white : Color.black

                    if let url = Self.googleSearchURL(placeName: placeName, placeSubtitle: placeSubtitle) {
                        Link(destination: url) {
                            HStack(alignment: .center, spacing: 4) {
                                markerView
                                HStack(alignment: .center, spacing: 5) {
                                    Text(placeName)
                                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: titleFontSize, weight: .bold)))
                                        .foregroundColor(titleColor)
                                    StoryPlaceExternalLinkIcon(titleFontSize: titleFontSize, foregroundColor: titleColor)
                                }
                            }
                        }
                    } else {
                        HStack(alignment: .center, spacing: 4) {
                            markerView
                            Text(placeName)
                                .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: titleFontSize, weight: .bold)))
                                .foregroundColor(titleColor)
                        }
                    }
                    Text("More Photos")
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 12, weight: .medium)))
                        .foregroundColor(blogColor == .black ? Color.white : Color.black)
                        .italic()
                }
            }

            switch photoGridLayout {
            case .twoColumn:
                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<photos.count, id: \.self) { i in
                        let shape: PhotoShape = (i % 2 == 0) ? photoShapeOptions.leftShape : photoShapeOptions.rightShape
                        PhotoCardView(
                            photo: photos[i],
                            photoShape: shape,
                            blogColor: blogColor,
                            fontTheme: fontTheme,
                            width: photoWidth,
                            imageHeight: photoImageHeight
                        )
                    }
                }
            case .single:
                if let first = photos.first {
                    PhotoCardView(
                        photo: first,
                        photoShape: photoShapeOptions.singleShape,
                        blogColor: blogColor,
                        fontTheme: fontTheme,
                        width: photoWidth,
                        imageHeight: photoImageHeight
                    )
                }
            case .stackedSingles:
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<photos.count, id: \.self) { i in
                        PhotoCardView(
                            photo: photos[i],
                            photoShape: photoShapeOptions.singleShape,
                            blogColor: blogColor,
                            fontTheme: fontTheme,
                            width: photoWidth,
                            imageHeight: photoImageHeight
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private static func googleSearchURL(placeName: String, placeSubtitle: String?) -> URL? {
        let trimmedPlaceName = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubtitle = placeSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !trimmedPlaceName.isEmpty { parts.append(trimmedPlaceName) }
        if let trimmedSubtitle, !trimmedSubtitle.isEmpty { parts.append(trimmedSubtitle) }

        let query = parts.joined(separator: ", ")
        guard !query.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}
