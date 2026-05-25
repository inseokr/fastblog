//
//  PlacesShareDraftBuilder.swift
//  fastblog
//

import CoreLocation
import Foundation

/// Builds an ephemeral `RecapBlogDetail` for exporting selected My Places — no itinerary / day cards.
enum PlacesShareDraftBuilder {

  static func makeShareDraft(
    selectedPlaces: [VisitedPlaceSummary],
    title: String? = nil
  ) -> RecapBlogDetail? {
    let sorted = selectedPlaces
      .filter { !$0.photos.isEmpty }
      .sorted { $0.latestVisitDate > $1.latestVisitDate }
    guard !sorted.isEmpty else { return nil }

    let stops: [PlaceStop] = sorted.enumerated().map { index, place in
      makePlaceStop(from: place, orderIndex: index)
    }

    let dayDate = sorted.map(\.latestVisitDate).max() ?? Date()
    let day = RecapBlogDay(
      dayIndex: 0,
      date: dayDate,
      placeStops: stops,
      isPlaceNamesResolved: true
    )

    let resolvedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
      ?? defaultTitle(for: sorted)

    let coverId = sorted.compactMap { place in
      place.heroPhoto?.localIdentifier ?? place.photos.first?.localIdentifier
    }.first

    let country = sorted.first?.country.trimmingCharacters(in: .whitespacesAndNewlines)
    let countryName = (country?.isEmpty == false) ? country : nil

    return RecapBlogDetail(
      id: UUID(),
      title: resolvedTitle,
      days: [day],
      selectedCoverPhotoIdentifier: coverId,
      countryName: countryName
    )
  }

  static func defaultTitle(for places: [VisitedPlaceSummary]) -> String {
    let countries = Set(places.map { $0.country.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    if countries.count == 1, let only = countries.first {
      return "Places in \(only)"
    }
    return "My Places"
  }

  private static func makePlaceStop(from place: VisitedPlaceSummary, orderIndex: Int) -> PlaceStop {
    let photos = place.photos.map { photo -> RecapPhoto in
      var copy = photo
      copy.isIncluded = true
      return copy
    }
    let repLocation = photos.compactMap(\.location).first
    let earliest = photos.map(\.timestamp).min() ?? place.latestVisitDate
    let digitized = exifDigitizedString(from: earliest)

    let city = place.cityDisplay
    let subtitle: String? = {
      guard let city, !city.isEmpty else { return nil }
      return city
    }()

    return PlaceStop(
      id: stableStopID(placeId: place.placeId),
      orderIndex: orderIndex,
      placeTitle: place.displayName,
      placeSubtitle: subtitle,
      placeTitleIsManual: true,
      representativeLocation: repLocation,
      photos: photos,
      noteText: place.placeCaption,
      visitedTimeDigitized: digitized,
      placeCategory: place.categoryRawValue
    )
  }

  /// Stable stop id per aggregated place key so export filters stay consistent across sessions.
  private static func stableStopID(placeId: String) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    for (i, b) in placeId.utf8.enumerated() {
      bytes[i % 16] ^= b
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x40
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    let tuple = (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    )
    return UUID(uuid: tuple)
  }

  private static func exifDigitizedString(from date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return f.string(from: date)
  }
}
