// fastblog/Views/StoryBook/DayContentPageView.swift
import SwiftUI

struct DayContentPageView: View {
    let page: DayContentPage
    @Environment(\.storyFontTheme) private var fontTheme
    @Environment(\.storyBlogColor) private var blogColor
    @Environment(\.storyRecapTopContentInset) private var recapTopContentInset
    private var primaryColor: Color { blogColor == .black ? .white : .black }
    private var bgColor: Color { blogColor == .black ? .black : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Day header: "Day #" + date/Continue sit tight together; Spacer keeps the icon on the trailing edge.
            HStack(alignment: .center, spacing: 0) {
                // Center-align so date vs italic "Continue" share the same vertical slot (firstTextBaseline + italic mismatch).
                HStack(alignment: .center, spacing: 8) {
                    Text("Day \(page.day.dayNumber)")
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 22, weight: .bold)))
                        .foregroundColor(primaryColor)
                        .monospacedDigit()

                    Group {
                        if page.isFirstPage {
                            Text(page.shortDateText)
                                .foregroundColor(primaryColor.opacity(0.55))
                        } else {
                            Text("Continue")
                                .foregroundColor(primaryColor)
                                .italic()
                        }
                    }
                    .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 14)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(height: 22, alignment: .center)
                }

                Spacer(minLength: 12)

                Image("PDFLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(appChromeBaseRadius: 8, style: .continuous))
            }
            .frame(height: 44, alignment: .center)
            Divider()

            // Slots
            ForEach(0..<page.slots.count, id: \.self) { i in
                slotView(page.slots[i])
            }
        }
        .padding(.horizontal, 16)
        // Default `recapTopContentInset` is 0 (standalone); Recap story mode passes a few pt — not full safe area (see `StoryRenderMetrics`).
        .padding(.top, (recapTopContentInset > 0 ? 0 : 2) + recapTopContentInset)
        .padding(.bottom, StoryPageLayout.storyChromeBottomOverlayHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(bgColor.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            // "The End" sits inside the chrome-reserve zone (above the Cancel/Share bar),
            // so it doesn't consume any photo space on non-final pages.
            if page.isLastPageOfTrip {
                HStack {
                    Spacer()
                    Text("The End")
                        .italic()
                        .font(Font(StoryFontHelper.uiItalicFont(for: fontTheme, size: 12)))
                        .foregroundColor(primaryColor)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, StoryPageLayout.storyChromeBottomOverlayHeight - 12)
            }
        }
    }

    @ViewBuilder
    private func slotView(_ slot: ContentSlot) -> some View {
        switch slot {
        case .dayCaption(let text):
            StoryDayCaptionCallout(text: text, fontTheme: fontTheme)

        case .placeBlock(let place, let photoSlice, let photoImageHeight, let photoGridLayout, let storyUsesTwoColumns, let showPlaceStory):
            let photos: [PhotoContent] = place.photos.isEmpty ? [] : {
                let lo = photoSlice.lowerBound
                let hi = min(photoSlice.upperBound, place.photos.count - 1)
                guard lo <= hi else { return [] }
                return Array(place.photos[lo...hi])
            }()
            PlaceBlockView(
                place: place,
                photos: photos,
                photoImageHeight: photoImageHeight,
                photoGridLayout: photoGridLayout,
                storyUsesTwoColumns: false,
                showPlaceStory: showPlaceStory,
                photoShapeOptions: PDFPhotoShapeOptions(),
                blogColor: blogColor,
                fontTheme: fontTheme
            )

        case .photoOverflowContinuation(let name, let place, let photoSlice, let photoImageHeight, let photoGridLayout, let showOverflowHeader):
            let photos: [PhotoContent] = {
                let lo = photoSlice.lowerBound
                let hi = min(photoSlice.upperBound, place.photos.count - 1)
                guard lo <= hi else { return [] }
                return Array(place.photos[lo...hi])
            }()
            PhotoContinuationBlockView(
                placeName: name,
                placeSubtitle: place.subtitle,
                placeMarkerNumber: place.markerNumber,
                placeMarkerType: place.markerType,
                photos: photos,
                photoImageHeight: photoImageHeight,
                photoGridLayout: photoGridLayout,
                showOverflowHeader: showOverflowHeader,
                photoShapeOptions: PDFPhotoShapeOptions(),
                blogColor: blogColor,
                fontTheme: fontTheme
            )

        case .photoCaptionContinuation(let text, let fullCaption, let availableCaptionHeight, let captionWidth):
            PhotoCaptionContinuationView(
                text: text,
                fullCaption: fullCaption,
                availableCaptionHeight: availableCaptionHeight,
                captionWidth: captionWidth,
                fontTheme: fontTheme,
                blogColor: blogColor
            )

        case .placeStoryContinuation(let text):
            PlaceStoryContinuationView(text: text, fontTheme: fontTheme, blogColor: blogColor)
        }
    }
}

private extension DayContentPage {
    var shortDateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"   // "Wed, March 12"
        return f.string(from: day.date)
    }
}

/// Follow-up page(s) for place story text split by `StoryPageLayout.expandPlaceStoryPagination`.
private struct PlaceStoryContinuationView: View {
    let text: String
    let fontTheme: FontTheme
    let blogColor: BlogColor

    private var secondary: Color {
        blogColor == .black ? Color.white.opacity(0.55) : Color.black.opacity(0.45)
    }

    private var bodyColor: Color {
        blogColor == .black ? Color.white.opacity(0.82) : Color.black.opacity(0.78)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continued")
                .font(Font(StoryFontHelper.uiItalicFont(for: fontTheme, size: 10)))
                .foregroundColor(secondary)

            Text(text)
                .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: StoryPageLayout.placeStoryBodyFontSize)))
                .foregroundColor(bodyColor)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

/// Follow-up page(s) for a photo caption that was split by `StoryPageLayout.expandPaginatedPhotoCaptions`.
///
/// Two-pass overflow check: the layout engine (pass 1) splits conservatively using size-11 estimates.
/// In `init` (pass 2) we re-measure the full original caption at the actual render font (size 13) against
/// the per-slot available height. If the full caption fits, the split was spurious and we suppress
/// the "Continued" label so the reader isn't confused by an unnecessary continuation notice.
private struct PhotoCaptionContinuationView: View {
    let text: String
    let fullCaption: String
    let availableCaptionHeight: CGFloat
    let captionWidth: CGFloat
    let fontTheme: FontTheme
    let blogColor: BlogColor

    /// True when the full caption would have fit on the photo page — the split was an estimation artefact.
    private let isSplitSpurious: Bool

    init(
        text: String,
        fullCaption: String,
        availableCaptionHeight: CGFloat,
        captionWidth: CGFloat,
        fontTheme: FontTheme,
        blogColor: BlogColor
    ) {
        self.text = text
        self.fullCaption = fullCaption
        self.availableCaptionHeight = availableCaptionHeight
        self.captionWidth = captionWidth
        self.fontTheme = fontTheme
        self.blogColor = blogColor

        // Pass 2: re-measure with photoCaptionFontSize (13pt) — the actual render font —
        // against the geometrically accurate per-slot available height passed from the layout engine.
        if captionWidth > 0, !fullCaption.isEmpty {
            let font = StoryFontHelper.uiFont(for: fontTheme, size: StoryPageLayout.photoCaptionFontSize)
            let measured = fullCaption.boundingRect(
                with: CGSize(width: captionWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            isSplitSpurious = measured.height <= availableCaptionHeight
        } else {
            isSplitSpurious = false
        }
    }

    private var secondary: Color {
        blogColor == .black ? Color.white.opacity(0.55) : Color.black.opacity(0.45)
    }

    private var bodyColor: Color {
        blogColor == .black ? Color.white.opacity(0.82) : Color.black.opacity(0.78)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isSplitSpurious {
                Text("Continued")
                    .font(Font(StoryFontHelper.uiItalicFont(for: fontTheme, size: 10)))
                    .foregroundColor(secondary)
            }

            Text(text)
                .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 11)))
                .foregroundColor(bodyColor)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

/// Yellow callout for the day-level story caption (matches `StoryPageLayout` day caption metrics).
private struct StoryDayCaptionCallout: View {
    let text: String
    var fontTheme: FontTheme = .classic

    private let accentColor = Color(red: 1, green: 0.82, blue: 0.12)
    private let fillColor = Color(red: 1, green: 0.97, blue: 0.88)

    var body: some View {
        let r = StoryPageLayout.dayStoryBoxCornerRadius
        // The accent bar is an overlay so the callout sizes to its text content.
        // Previously the bar used .frame(maxHeight: .infinity) inside an HStack,
        // which made the callout a greedy height consumer in the page VStack,
        // causing it to be compressed when place blocks were on the same page.
        Text(text)
            .italic()
            .font(Font(StoryFontHelper.uiItalicFont(for: fontTheme, size: StoryPageLayout.dayStoryCaptionFontSize)))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, StoryPageLayout.dayStoryBoxDividerInsetFromLeft + StoryPageLayout.dayStoryBoxDividerWidth + 12)
            .padding(.trailing, StoryPageLayout.dayStoryBoxTextPaddingRight)
            .padding(.top, StoryPageLayout.dayStoryBoxTextPaddingTop)
            .padding(.bottom, StoryPageLayout.dayStoryBoxTextPaddingBottom)
            .background(
                RoundedRectangle(appChromeBaseRadius: r, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    cornerRadii: RectangleCornerRadii(
                        topLeading: r,
                        bottomLeading: r,
                        bottomTrailing: 0,
                        topTrailing: 0
                    ),
                    style: .continuous
                )
                .fill(accentColor)
                .frame(width: StoryPageLayout.dayStoryBoxDividerWidth)
                .frame(maxHeight: .infinity)
                .padding(.leading, StoryPageLayout.dayStoryBoxDividerInsetFromLeft)
            }
    }
}
