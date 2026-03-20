// fastblog/Views/StoryBook/DayContentPageView.swift
import SwiftUI
import UIKit

struct DayContentPageView: View {
    let page: DayContentPage
    let showNextDayLabel: Bool
    let photoShapeOptions: PDFPhotoShapeOptions
    let blogColor: BlogColor
    let fontTheme: FontTheme
    let layoutMode: PDFLayoutMode
    let bookPageIndex: Int
    let bookPageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Day header
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Day \(page.day.dayNumber)")
                    .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 22, weight: .bold)))
                    .foregroundColor(blogColor == .black ? .white : .black)
                if page.isFirstPage {
                    Text(page.shortDateText)
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 14)))
                        .foregroundColor(blogColor == .black ? .white : .black)
                } else {
                    Text("continued")
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 14)))
                        .foregroundColor(blogColor == .black ? .white : .black)
                        .italic()
                }
            }
            .frame(height: 44, alignment: .center)
            Divider().background(blogColor == .black ? Color.white.opacity(0.2) : Color.black.opacity(0.15))

            // Slots
            ForEach(0..<page.slots.count, id: \.self) { i in
                slotView(page.slots[i])
            }

            Spacer()

            PageFooterView(
                isLastPageOfTrip: page.isLastPageOfTrip,
                isLastPageOfDay: page.isLastPageOfDay,
                nextDayName: page.nextDayName,
                showNextDayLabel: showNextDayLabel,
                blogColor: blogColor,
                fontTheme: fontTheme,
                bookPageIndex: bookPageIndex,
                bookPageCount: bookPageCount
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(blogColor == .black ? Color.black : Color.white)
        .frame(
            width: StoryRenderMetrics.clampedScreenWidth,
            height: StoryRenderMetrics.clampedScreenHeight,
            alignment: .top
        )
    }

    @ViewBuilder
    private func slotView(_ slot: ContentSlot) -> some View {
        switch slot {
        case .dayCaption(let text):
            let pageWidth = max(0, StoryRenderMetrics.clampedScreenWidth - 32) // matches StoryPageLayout storyHorizontalPadding
            let boxH = StoryPageLayout.dayStoryCaptionBoxHeight(for: text, pageWidth: pageWidth, fontTheme: fontTheme)

            let yellowFill = Color(red: 1.00, green: 0.94, blue: 0.78).opacity(0.14)
            let dividerColor = Color(red: 0.88, green: 0.68, blue: 0.12)

            let textWidth = max(
                0,
                pageWidth
                    - StoryPageLayout.dayStoryBoxTextInsetFromLeft
                    - StoryPageLayout.dayStoryBoxTextPaddingRight
            )
            let textHAvail = max(
                0,
                boxH
                    - StoryPageLayout.dayStoryBoxTextPaddingTop
                    - StoryPageLayout.dayStoryBoxTextPaddingBottom
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: StoryPageLayout.dayStoryBoxCornerRadius)
                    .fill(yellowFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: boxH)

                Rectangle()
                    .fill(dividerColor)
                    .frame(width: StoryPageLayout.dayStoryBoxDividerWidth, height: boxH)

                Text(text)
                    // Use UIKit's italic system font so our height estimator matches SwiftUI's layout.
                    .font(Font(StoryFontHelper.uiItalicFont(for: fontTheme, size: StoryPageLayout.dayStoryCaptionFontSize)))
                    // Ensure SwiftUI Dynamic Type doesn't scale this caption text
                    // without StoryPageLayout's height estimator knowing about it.
                    .dynamicTypeSize(.medium)
                    .foregroundColor(blogColor == .black ? .white : .black)
                    .frame(
                        width: textWidth,
                        height: textHAvail,
                        alignment: Alignment(horizontal: .leading, vertical: .top)
                    )
                    .offset(
                        x: StoryPageLayout.dayStoryBoxTextInsetFromLeft,
                        y: StoryPageLayout.dayStoryBoxTextPaddingTop
                    )
                        // Intentionally do not clip so we can see the full caption lines.
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: boxH)
            .clipShape(RoundedRectangle(cornerRadius: StoryPageLayout.dayStoryBoxCornerRadius))

        case .placeBlock(let place, let photoSlice, let photoImageHeight, let photoGridLayout):
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
                photoShapeOptions: photoShapeOptions,
                blogColor: blogColor,
                fontTheme: fontTheme,
                layoutMode: layoutMode
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
                photoShapeOptions: photoShapeOptions,
                blogColor: blogColor,
                fontTheme: fontTheme
            )
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
