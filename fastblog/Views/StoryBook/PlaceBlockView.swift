// fastblog/Views/StoryBook/PlaceBlockView.swift
import SwiftUI
import UIKit

struct PlaceBlockView: View {
    let place: PlaceContent
    let photos: [PhotoContent]
    /// Image frame height for story-mode layout packing (shared by all photos in this block).
    let photoImageHeight: CGFloat
    let photoGridLayout: PhotoGridLayout
    let photoShapeOptions: PDFPhotoShapeOptions
    let blogColor: BlogColor
    let fontTheme: FontTheme
    let layoutMode: PDFLayoutMode

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
            switch place.markerType {
            case .start:
                return .green
            case .middle:
                return .blue
            case .end:
                return .orange
            }
        }()
        let markerSize: CGFloat = 20
        let markerNumberFontSize: CGFloat = 11

        VStack(alignment: .leading, spacing: StoryPageLayout.placeBlockRowSpacing) {
            // Title row
            HStack(alignment: .center, spacing: 4) {
                let titleFontSize: CGFloat = 14
                let titleColor = blogColor == .black ? Color.white : Color.black

                if let url = StoryPlaceGoogleSearch.url(placeName: place.title, placeSubtitle: place.subtitle) {
                    Link(destination: url) {
                        HStack(alignment: .center, spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(markerColor)
                                    .frame(width: markerSize, height: markerSize)
                                Text("\(place.markerNumber)")
                                    .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: markerNumberFontSize, weight: .bold)))
                                    .foregroundColor(Color.white)
                            }

                            HStack(alignment: .center, spacing: 5) {
                                Text(place.title)
                                    .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: titleFontSize, weight: .bold)))
                                    .foregroundColor(titleColor)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                StoryPlaceExternalLinkIcon(titleFontSize: titleFontSize, foregroundColor: titleColor)
                            }
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(markerColor)
                                .frame(width: markerSize, height: markerSize)
                            Text("\(place.markerNumber)")
                                .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: markerNumberFontSize, weight: .bold)))
                                .foregroundColor(Color.white)
                        }

                        Text(place.title)
                            .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: titleFontSize, weight: .bold)))
                            .foregroundColor(titleColor)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if let ts = place.timestamp {
                    Text(ts)
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 11)))
                        .foregroundColor(blogColor == .black ? Color.white : Color.black)
                }
            }

            if layoutMode == .normal, let caption = place.caption {
                captionSection(caption: caption, pageWidth: pageWidth)
            }

            // Photos
            if !photos.isEmpty {
                switch photoGridLayout {
                case .twoColumn:
                    PlaceBlockHorizontalPhotoList(photos: photos, gap: gap, photoWidth: photoWidth, imageHeight: photoImageHeight)
                case .single:
                    PhotoCardView(photo: photos[0], width: photoWidth, imageHeight: photoImageHeight)
                case .stackedSingles:
                    PlaceBlockVerticalPhotoList(photos: photos, gap: gap, photoWidth: photoWidth, imageHeight: photoImageHeight)
                }
            }

            if layoutMode == .story, let caption = place.caption {
                captionSection(caption: caption, pageWidth: pageWidth)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func captionSection(caption: String, pageWidth: CGFloat) -> some View {
        // Reserve the expected caption "slot height" so a 1-line caption
        // doesn't pull photos upward compared to captions that wrap.
        let hasPhotos = !photos.isEmpty
        let captionSlotH = place.captionIsLong
            ? StoryPageLayout.placeCaptionLong
            : StoryPageLayout.placeCaptionShort
        let gaps = StoryPageLayout.placeCaptionGaps(layoutMode: layoutMode, hasPhotosInSlot: hasPhotos)
        let minCaptionTextH = max(0, captionSlotH - gaps.top - gaps.bottom)

        let captionFont = StoryFontHelper.uiFont(for: fontTheme, size: 12)
        let estimatedCaptionTextH = Self.estimateTextHeight(caption, font: captionFont, width: pageWidth)
        let usedCaptionTextH = max(minCaptionTextH, estimatedCaptionTextH)

        Text(caption)
            .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 12)))
            .foregroundColor(blogColor == .black ? Color.white : Color.black)
            // Allow the caption to use the full reserved height.
            // Truncation here was causing the "..." ellipsis even when the layout
            // should have had more vertical room.
            .frame(height: usedCaptionTextH, alignment: .topLeading)
    }

    private static func estimateTextHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, width > 0 else { return 0 }
        let rect = trimmed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return max(0, rect.height)
    }
}

private struct PlaceBlockHorizontalPhotoList: View {
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
                PlaceBlockHorizontalPhotoList(photos: photos, gap: gap, photoWidth: photoWidth, imageHeight: imageHeight, start: start + 1)
            }
        }
    }
}

private struct PlaceBlockVerticalPhotoList: View {
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
                PlaceBlockVerticalPhotoList(photos: photos, gap: gap, photoWidth: photoWidth, imageHeight: imageHeight, start: start + 1)
            }
        }
    }
}

/// External-link affordance to the right of place titles (story book + blog day rows). Slightly smaller than the title cap height.
struct StoryPlaceExternalLinkIcon: View {
    let titleFontSize: CGFloat
    let foregroundColor: Color

    private var iconSide: CGFloat {
        max(11, titleFontSize * 0.82)
    }

    var body: some View {
        Image("PlaceOpenInNew")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: iconSide, height: iconSide)
            .foregroundColor(foregroundColor.opacity(0.92))
            .accessibilityHidden(true)
    }
}
