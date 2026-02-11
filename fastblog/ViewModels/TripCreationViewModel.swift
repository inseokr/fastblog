//
//  TripCreationViewModel.swift
//  Capper
//

import Combine
import Foundation

@MainActor
final class TripCreationViewModel: ObservableObject {
    @Published var trip: TripDraft

    init(trip: TripDraft) {
        self.trip = trip
    }

    @Published var selectedDayIndex: Int = 0

    var selectedPhotoCount: Int {
        trip.selectedPhotoCount
    }

    var totalPhotoCount: Int {
        trip.totalPhotoCount
    }

    var selectedCountLabel: String {
        "\(selectedPhotoCount) out of \(totalPhotoCount) Photos Selected"
    }

    var canCreateBlog: Bool {
        selectedPhotoCount > 0
    }

    func togglePhotoSelection(dayId: UUID, photoId: UUID) {
        guard let dayIdx = trip.days.firstIndex(where: { $0.id == dayId }),
              let photoIdx = trip.days[dayIdx].photos.firstIndex(where: { $0.id == photoId }) else { return }
        var day = trip.days[dayIdx]
        var photo = day.photos[photoIdx]
        photo.isSelected.toggle()
        day.photos[photoIdx] = photo
        trip.days[dayIdx] = day
    }

    func isPhotoSelected(dayId: UUID, photoId: UUID) -> Bool {
        guard let day = trip.days.first(where: { $0.id == dayId }),
              let photo = day.photos.first(where: { $0.id == photoId }) else { return false }
        return photo.isSelected
    }

    func selectCurrentPhoto(dayIndex: Int, photoIndex: Int) {
        guard trip.days.indices.contains(dayIndex),
              trip.days[dayIndex].photos.indices.contains(photoIndex) else { return }
        var day = trip.days[dayIndex]
        var photo = day.photos[photoIndex]
        photo.isSelected.toggle()
        day.photos[photoIndex] = photo
        trip.days[dayIndex] = day
    }
}
