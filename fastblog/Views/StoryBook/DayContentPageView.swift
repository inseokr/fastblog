// fastblog/Views/StoryBook/DayContentPageView.swift
import SwiftUI

struct DayContentPageView: View {
    let page: DayContentPage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Day header — only on first page of the day
            if page.isFirstPage {
                HStack {
                    Text("Day \(page.day.dayNumber)")
                        .font(.system(size: 18, weight: .bold))
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(page.shortDateText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(height: 44, alignment: .center)
            }

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
                .foregroundColor(.primary)
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
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: day.date)
    }
}
