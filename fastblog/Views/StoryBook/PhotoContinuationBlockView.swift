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

        VStack(alignment: .leading, spacing: StoryPageLayout.placeBlockRowSpacing) {
            if showOverflowHeader {
                HStack(spacing: 4) {
                    let titleFontSize: CGFloat = 14
                    let titleColor = blogColor == .black ? Color.white : Color.black

                    if let url = StoryPlaceGoogleSearch.url(placeName: placeName, placeSubtitle: placeSubtitle) {
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
                PhotoContinuationHorizontalPhotoList(photos: photos, gap: gap, photoWidth: photoWidth, imageHeight: photoImageHeight)
            case .single:
                if let first = photos.first {
                    PhotoCardView(photo: first, width: photoWidth, imageHeight: photoImageHeight)
                }
            case .stackedSingles:
                PhotoContinuationVerticalPhotoList(photos: photos, gap: gap, photoWidth: photoWidth, imageHeight: photoImageHeight)
            }
        }
        .padding(.vertical, 4)
    }

}

/// Builds an `HStack` of `PhotoCardView`s without `ForEach` (avoids `Binding`-based `ForEach` overload resolution in this target).
private struct PhotoContinuationHorizontalPhotoList: View {
    let photos: [PhotoContent]
    let gap: CGFloat
    let photoWidth: CGFloat
    let imageHeight: CGFloat
    private let start: Int

    init(photos: [PhotoContent], gap: CGFloat, photoWidth: CGFloat, imageHeight: CGFloat, start: Int = 0) {
        self.photos = photos
        self.gap = gap
        self.photoWidth = photoWidth
        self.imageHeight = imageHeight
        self.start = start
    }

    var body: some View {
        if start >= photos.count {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: gap) {
                PhotoCardView(photo: photos[start], width: photoWidth, imageHeight: imageHeight)
                PhotoContinuationHorizontalPhotoList(photos: photos, gap: gap, photoWidth: photoWidth, imageHeight: imageHeight, start: start + 1)
            }
        }
    }
}

private struct PhotoContinuationVerticalPhotoList: View {
    let photos: [PhotoContent]
    let gap: CGFloat
    let photoWidth: CGFloat
    let imageHeight: CGFloat
    private let start: Int

    init(photos: [PhotoContent], gap: CGFloat, photoWidth: CGFloat, imageHeight: CGFloat, start: Int = 0) {
        self.photos = photos
        self.gap = gap
        self.photoWidth = photoWidth
        self.imageHeight = imageHeight
        self.start = start
    }

    var body: some View {
        if start >= photos.count {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: gap) {
                PhotoCardView(photo: photos[start], width: photoWidth, imageHeight: imageHeight)
                PhotoContinuationVerticalPhotoList(photos: photos, gap: gap, photoWidth: photoWidth, imageHeight: imageHeight, start: start + 1)
            }
        }
    }
}
