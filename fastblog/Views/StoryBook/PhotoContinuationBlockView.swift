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

    @Environment(\.storyRasterizesForExport) private var storyRasterizesForExport

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
        let overflowTitleFontSize: CGFloat = 14
        let overflowTitleColor = blogColor == .black ? Color.white : Color.black
        let overflowGoogleURL = StoryPlaceGoogleSearch.url(placeName: placeName, placeSubtitle: placeSubtitle)

        VStack(alignment: .leading, spacing: StoryPageLayout.placeBlockRowSpacing) {
            if showOverflowHeader {
                HStack(spacing: 4) {
                    if storyRasterizesForExport {
                        overflowTitleCluster(
                            markerColor: markerColor,
                            markerSize: markerSize,
                            markerNumberFontSize: markerNumberFontSize,
                            titleFontSize: overflowTitleFontSize,
                            titleColor: overflowTitleColor,
                            showExternalIcon: overflowGoogleURL != nil
                        )
                    } else if let url = overflowGoogleURL {
                        Link(destination: url) {
                            overflowTitleCluster(
                                markerColor: markerColor,
                                markerSize: markerSize,
                                markerNumberFontSize: markerNumberFontSize,
                                titleFontSize: overflowTitleFontSize,
                                titleColor: overflowTitleColor,
                                showExternalIcon: true
                            )
                        }
                    } else {
                        overflowTitleCluster(
                            markerColor: markerColor,
                            markerSize: markerSize,
                            markerNumberFontSize: markerNumberFontSize,
                            titleFontSize: overflowTitleFontSize,
                            titleColor: overflowTitleColor,
                            showExternalIcon: false
                        )
                    }
                    Text("More Photos")
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 12, weight: .medium)))
                        .foregroundColor(blogColor == .black ? Color.white : Color.black)
                        .italic()
                }
            }

            switch photoGridLayout {
            case .twoColumn:
                PhotoContinuationHorizontalPhotoList(
                    photos: photos,
                    gap: gap,
                    photoWidth: photoWidth,
                    imageHeight: photoImageHeight,
                    fontTheme: fontTheme,
                    blogColor: blogColor
                )
            case .single:
                if let first = photos.first {
                    PhotoCardView(
                        photo: first,
                        width: photoWidth,
                        imageHeight: photoImageHeight,
                        fontTheme: fontTheme,
                        blogColor: blogColor
                    )
                }
            case .stackedSingles:
                PhotoContinuationVerticalPhotoList(
                    photos: photos,
                    gap: gap,
                    photoWidth: photoWidth,
                    imageHeight: photoImageHeight,
                    fontTheme: fontTheme,
                    blogColor: blogColor
                )
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func overflowTitleCluster(
        markerColor: Color,
        markerSize: CGFloat,
        markerNumberFontSize: CGFloat,
        titleFontSize: CGFloat,
        titleColor: Color,
        showExternalIcon: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 4) {
            ZStack {
                Circle()
                    .fill(markerColor)
                    .frame(width: markerSize, height: markerSize)
                Text("\(placeMarkerNumber)")
                    .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: markerNumberFontSize, weight: .bold)))
                    .foregroundColor(Color.white)
            }
            HStack(alignment: .center, spacing: 5) {
                Text(placeName)
                    .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: titleFontSize, weight: .bold)))
                    .foregroundColor(titleColor)
                if showExternalIcon {
                    StoryPlaceExternalLinkIcon(titleFontSize: titleFontSize, foregroundColor: titleColor)
                }
            }
        }
    }

}

/// Builds an `HStack` of `PhotoCardView`s without `ForEach` (avoids `Binding`-based `ForEach` overload resolution in this target).
private struct PhotoContinuationHorizontalPhotoList: View {
    let photos: [PhotoContent]
    let gap: CGFloat
    let photoWidth: CGFloat
    let imageHeight: CGFloat
    let fontTheme: FontTheme
    let blogColor: BlogColor
    private let start: Int

    init(
        photos: [PhotoContent],
        gap: CGFloat,
        photoWidth: CGFloat,
        imageHeight: CGFloat,
        fontTheme: FontTheme,
        blogColor: BlogColor,
        start: Int = 0
    ) {
        self.photos = photos
        self.gap = gap
        self.photoWidth = photoWidth
        self.imageHeight = imageHeight
        self.fontTheme = fontTheme
        self.blogColor = blogColor
        self.start = start
    }

    var body: some View {
        if start >= photos.count {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: gap) {
                PhotoCardView(
                    photo: photos[start],
                    width: photoWidth,
                    imageHeight: imageHeight,
                    fontTheme: fontTheme,
                    blogColor: blogColor
                )
                PhotoContinuationHorizontalPhotoList(
                    photos: photos,
                    gap: gap,
                    photoWidth: photoWidth,
                    imageHeight: imageHeight,
                    fontTheme: fontTheme,
                    blogColor: blogColor,
                    start: start + 1
                )
            }
        }
    }
}

private struct PhotoContinuationVerticalPhotoList: View {
    let photos: [PhotoContent]
    let gap: CGFloat
    let photoWidth: CGFloat
    let imageHeight: CGFloat
    let fontTheme: FontTheme
    let blogColor: BlogColor
    private let start: Int

    init(
        photos: [PhotoContent],
        gap: CGFloat,
        photoWidth: CGFloat,
        imageHeight: CGFloat,
        fontTheme: FontTheme,
        blogColor: BlogColor,
        start: Int = 0
    ) {
        self.photos = photos
        self.gap = gap
        self.photoWidth = photoWidth
        self.imageHeight = imageHeight
        self.fontTheme = fontTheme
        self.blogColor = blogColor
        self.start = start
    }

    var body: some View {
        if start >= photos.count {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: gap) {
                PhotoCardView(
                    photo: photos[start],
                    width: photoWidth,
                    imageHeight: imageHeight,
                    fontTheme: fontTheme,
                    blogColor: blogColor
                )
                PhotoContinuationVerticalPhotoList(
                    photos: photos,
                    gap: gap,
                    photoWidth: photoWidth,
                    imageHeight: imageHeight,
                    fontTheme: fontTheme,
                    blogColor: blogColor,
                    start: start + 1
                )
            }
        }
    }
}
