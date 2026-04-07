// fastblog/Views/StoryBook/PlaceBlockView.swift
import SwiftUI
import UIKit

struct PlaceBlockView: View {
    let place: PlaceContent
    let photos: [PhotoContent]
    /// Image frame height for story-mode layout packing (shared by all photos in this block).
    let photoImageHeight: CGFloat
    let photoGridLayout: PhotoGridLayout
    /// When true, place story is laid out in two balanced columns (layout engine must agree).
    var storyUsesTwoColumns: Bool = false
    /// When false, only title + photos render (e.g. second single-photo slot after a long story).
    var showPlaceStory: Bool = true
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
        let titleFontSize: CGFloat = 14
        let titleColor = blogColor == .black ? Color.white : Color.black
        let googleURL = StoryPlaceGoogleSearch.url(placeName: place.title, placeSubtitle: place.subtitle)

        VStack(alignment: .leading, spacing: StoryPageLayout.placeBlockRowSpacing) {
            HStack(alignment: .center, spacing: 4) {
                if storyRasterizesForExport {
                    placeTitleCluster(
                        markerColor: markerColor,
                        markerSize: markerSize,
                        markerNumberFontSize: markerNumberFontSize,
                        titleFontSize: titleFontSize,
                        titleColor: titleColor,
                        showExternalIcon: googleURL != nil
                    )
                } else if let url = googleURL {
                    Link(destination: url) {
                        placeTitleCluster(
                            markerColor: markerColor,
                            markerSize: markerSize,
                            markerNumberFontSize: markerNumberFontSize,
                            titleFontSize: titleFontSize,
                            titleColor: titleColor,
                            showExternalIcon: true
                        )
                    }
                } else {
                    placeTitleCluster(
                        markerColor: markerColor,
                        markerSize: markerSize,
                        markerNumberFontSize: markerNumberFontSize,
                        titleFontSize: titleFontSize,
                        titleColor: titleColor,
                        showExternalIcon: false
                    )
                }

                Spacer()
                if let ts = place.timestamp {
                    Text(ts)
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 11)))
                        .foregroundColor(blogColor == .black ? Color.white : Color.black)
                }
            }

            if showPlaceStory, let caption = place.caption {
                captionSection(caption: caption, pageWidth: pageWidth)
            }

            // Photos
            if !photos.isEmpty {
                switch photoGridLayout {
                case .twoColumn:
                    PlaceBlockHorizontalPhotoList(
                        photos: photos,
                        gap: gap,
                        photoWidth: photoWidth,
                        imageHeight: photoImageHeight,
                        fontTheme: fontTheme,
                        blogColor: blogColor
                    )
                case .single:
                    PhotoCardView(
                        photo: photos[0],
                        width: photoWidth,
                        imageHeight: photoImageHeight,
                        fontTheme: fontTheme,
                        blogColor: blogColor
                    )
                case .stackedSingles:
                    PlaceBlockVerticalPhotoList(
                        photos: photos,
                        gap: gap,
                        photoWidth: photoWidth,
                        imageHeight: photoImageHeight,
                        fontTheme: fontTheme,
                        blogColor: blogColor
                    )
                }
            }

        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func placeTitleCluster(
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

                if showExternalIcon {
                    StoryPlaceExternalLinkIcon(titleFontSize: titleFontSize, foregroundColor: titleColor)
                }
            }
        }
    }

    @ViewBuilder
    private func captionSection(caption: String, pageWidth: CGFloat) -> some View {
        // Reserve the expected caption "slot height" so a 1-line caption
        // doesn't pull photos upward compared to captions that wrap.
        let hasPhotos = !photos.isEmpty
        let captionSlotH = place.captionIsLong
            ? StoryPageLayout.placeCaptionLong
            : StoryPageLayout.placeCaptionShort
        let gaps = StoryPageLayout.placeCaptionGaps(layoutMode: .normal, hasPhotosInSlot: hasPhotos)
        let minCaptionTextH = max(0, captionSlotH - gaps.top - gaps.bottom)

        let captionFont = StoryFontHelper.uiFont(for: fontTheme, size: StoryPageLayout.placeStoryBodyFontSize)
        let colGap: CGFloat = 10
        let usedCaptionTextH: CGFloat = {
            if storyUsesTwoColumns {
                let (left, right) = Self.splitBalancedForTwoColumns(caption)
                let colW = max(40, (pageWidth - colGap) / 2)
                let hl = Self.estimateTextHeight(left, font: captionFont, width: colW) + captionFont.lineHeight * 0.35
                let hr = right.isEmpty ? 0 : Self.estimateTextHeight(right, font: captionFont, width: colW) + captionFont.lineHeight * 0.35
                let est = max(hl, hr)
                return max(minCaptionTextH, est)
            }
            let estimatedCaptionTextH = Self.estimateTextHeight(caption, font: captionFont, width: pageWidth)
            let lh = max(1, captionFont.lineHeight)
            let conservativeEstimatedH = estimatedCaptionTextH + lh * 0.35
            return max(minCaptionTextH, conservativeEstimatedH)
        }()

        Group {
            if storyUsesTwoColumns {
                let (left, right) = Self.splitBalancedForTwoColumns(caption)
                let colW = max(40, (pageWidth - colGap) / 2)
                HStack(alignment: .top, spacing: colGap) {
                    Text(left)
                        .font(Font(captionFont))
                        .foregroundColor(blogColor == .black ? Color.white : Color.black)
                        .frame(width: colW, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !right.isEmpty {
                        Text(right)
                            .font(Font(captionFont))
                            .foregroundColor(blogColor == .black ? Color.white : Color.black)
                            .frame(width: colW, alignment: .topLeading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(caption)
                    .font(Font(captionFont))
                    .foregroundColor(blogColor == .black ? Color.white : Color.black)
            }
        }
        .frame(height: usedCaptionTextH, alignment: .topLeading)
    }

    private static func splitBalancedForTwoColumns(_ text: String) -> (String, String) {
        let words = text.split { $0.isWhitespace || $0.isNewline }.map(String.init).filter { !$0.isEmpty }
        guard words.count >= 2 else { return (text, "") }
        let mid = words.count / 2
        let left = words[..<mid].joined(separator: " ")
        let right = words[mid...].joined(separator: " ")
        return (left, right)
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
                PlaceBlockHorizontalPhotoList(
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

private struct PlaceBlockVerticalPhotoList: View {
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
                PlaceBlockVerticalPhotoList(
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

/// External-link affordance to the right of place titles (story book + blog day rows). Slightly smaller than the title cap height.
struct StoryPlaceExternalLinkIcon: View {
    let titleFontSize: CGFloat
    let foregroundColor: Color

    private var iconSide: CGFloat {
        max(11, titleFontSize * 0.82)
    }

    var body: some View {
        Image(systemName: "link")
            .font(.system(size: iconSide, weight: .semibold))
            .frame(width: iconSide, height: iconSide)
            .foregroundColor(foregroundColor.opacity(0.92))
            .accessibilityHidden(true)
    }
}
