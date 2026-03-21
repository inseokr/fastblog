// fastblog/Views/StoryBook/DayContentPageView.swift
import SwiftUI

struct DayContentPageView: View {
    let page: DayContentPage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Day header: "Day #" + date/Continue sit tight together; Spacer keeps the icon on the trailing edge.
            HStack(alignment: .center, spacing: 0) {
                // Center-align so date vs italic "Continue" share the same vertical slot (firstTextBaseline + italic mismatch).
                HStack(alignment: .center, spacing: 8) {
                    Text("Day \(page.day.dayNumber)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                        .monospacedDigit()

                    Group {
                        if page.isFirstPage {
                            Text(page.shortDateText)
                                .foregroundColor(.black.opacity(0.55))
                        } else {
                            Text("Continue")
                                .foregroundColor(.black)
                                .italic()
                        }
                    }
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(height: 22, alignment: .center)
                }

                Spacer(minLength: 12)

                Image("AppIconMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 44, alignment: .center)
            Divider()

            // Slots
            ForEach(0..<page.slots.count, id: \.self) { i in
                slotView(page.slots[i])
            }

            Spacer()

            PageFooterView(
                isLastPageOfTrip: page.isLastPageOfTrip,
                isLastPageOfDay: page.isLastPageOfDay,
                nextDayName: page.nextDayName
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, StoryPageLayout.storyChromeBottomOverlayHeight)
        .background(Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func slotView(_ slot: ContentSlot) -> some View {
        switch slot {
        case .dayCaption(let text):
            StoryDayCaptionCallout(text: text)

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
                photoShapeOptions: PDFPhotoShapeOptions(),
                blogColor: .white,
                fontTheme: .classic,
                layoutMode: .normal
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
                blogColor: .white,
                fontTheme: .classic
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

/// Yellow callout for the day-level story caption (matches `StoryPageLayout` day caption metrics).
private struct StoryDayCaptionCallout: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 1, green: 0.82, blue: 0.12))
                .frame(width: StoryPageLayout.dayStoryBoxDividerWidth)
            Text(text)
                .italic()
                .font(Font(StoryFontHelper.uiItalicFont(for: .classic, size: StoryPageLayout.dayStoryCaptionFontSize)))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, StoryPageLayout.dayStoryBoxDividerInsetFromLeft)
        .padding(.trailing, StoryPageLayout.dayStoryBoxTextPaddingRight)
        .padding(.top, StoryPageLayout.dayStoryBoxTextPaddingTop)
        .padding(.bottom, StoryPageLayout.dayStoryBoxTextPaddingBottom)
    }
}
