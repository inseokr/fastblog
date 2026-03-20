// fastblog/Views/StoryBook/DayContentPageView.swift
import SwiftUI

struct DayContentPageView: View {
    let page: DayContentPage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Day header
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Day \(page.day.dayNumber)")
                    .font(.system(size: 22, weight: .bold))
                if page.isFirstPage {
                    Text(page.shortDateText)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                } else {
                    Text("continued")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .italic()
                }
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
        .background(Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func slotView(_ slot: ContentSlot) -> some View {
        switch slot {
        case .dayCaption(let text):
            Text(text)
                .italic()
                .font(.system(size: 14))
                .foregroundColor(Color.black)
                .lineLimit(4)

        case .placeBlock(let place, let photoSlice):
            let photos: [PhotoContent] = place.photos.isEmpty ? [] : {
                let lo = photoSlice.lowerBound
                let hi = min(photoSlice.upperBound, place.photos.count - 1)
                guard lo <= hi else { return [] }
                return Array(place.photos[lo...hi])
            }()
            PlaceBlockView(place: place, photos: photos)

        case .photoOverflowContinuation(let name, let place, let photoSlice):
            let photos: [PhotoContent] = {
                let lo = photoSlice.lowerBound
                let hi = min(photoSlice.upperBound, place.photos.count - 1)
                guard lo <= hi else { return [] }
                return Array(place.photos[lo...hi])
            }()
            PhotoContinuationBlockView(placeName: name, photos: photos)
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
