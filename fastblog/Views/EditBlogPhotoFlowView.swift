//
//  EditBlogPhotoFlowView.swift
//  fastblog
//

import SwiftUI

/// Presents the photo selection flow (TripDayPickerView) in edit mode, then Title → Cover with "Update".
/// Used when user taps "Pick Photos" in Blog Settings.
struct EditBlogPhotoFlowView: View {
    let blogId: UUID
    var onDismiss: () -> Void
    /// Called after ``CreateBlogFlowView`` finishes `updateBlog` for this blog (not on Cancel).
    var onBlogPhotosUpdated: (() -> Void)? = nil
    /// Provide a pre-built trip to skip the store lookup — used by Canvas previews.
    var initialTrip: TripDraft? = nil
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @State private var trip: TripDraft?
    @State private var tripToUpdate: TripDraft?

    var body: some View {
        NavigationStack {
            Group {
                if let t = trip {
                    TripDayPickerView(
                        trip: t,
                        onStartCreateBlog: { _ in },
                        isEditMode: true,
                        onCancel: onDismiss,
                        onUpdate: { updated in
                            tripToUpdate = updated
                        }
                    )
                    .fullScreenCover(item: $tripToUpdate) { updatedTrip in
                        CreateBlogFlowView(
                            trip: updatedTrip,
                            existingBlogId: blogId,
                            onUpdateComplete: {
                                tripToUpdate = nil
                                onBlogPhotosUpdated?()
                                onDismiss()
                            },
                            onClose: { _ in }
                        )
                        .environmentObject(createdRecapStore)
                    }
                } else {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                trip = initialTrip ?? createdRecapStore.tripDraftApplyingBlogSelection(blogId: blogId)
            }
        }
    }
}

// MARK: - Preview

private extension TripDraft {
    static let preview: TripDraft = {
        func photos(count: Int, location: String, country: String, baseHour: Int) -> [MockPhoto] {
            (0..<count).map { i in
                MockPhoto(
                    imageName: "photo",
                    timestamp: Calendar.current.date(
                        bySettingHour: baseHour + i,
                        minute: i * 7,
                        second: 0,
                        of: Date()
                    ) ?? Date(),
                    locationName: location,
                    countryName: country,
                    isSelected: true
                )
            }
        }

        let day1 = TripDay(
            dayIndex: 0,
            dateText: "Apr 21, 2025",
            photos: photos(count: 6, location: "Shibuya", country: "Japan", baseHour: 9)
                + photos(count: 4, location: "Harajuku", country: "Japan", baseHour: 14),
            countryCode: "JP", countryName: "Japan", cityName: "Tokyo"
        )
        let day2 = TripDay(
            dayIndex: 1,
            dateText: "Apr 22, 2025",
            photos: photos(count: 5, location: "Shinjuku", country: "Japan", baseHour: 10)
                + photos(count: 3, location: "Akihabara", country: "Japan", baseHour: 15),
            countryCode: "JP", countryName: "Japan", cityName: "Tokyo"
        )
        let day3 = TripDay(
            dayIndex: 2,
            dateText: "Apr 23, 2025",
            photos: photos(count: 7, location: "Asakusa", country: "Japan", baseHour: 8)
                + photos(count: 5, location: "Ueno Park", country: "Japan", baseHour: 13),
            countryCode: "JP", countryName: "Japan", cityName: "Tokyo"
        )
        let day4 = TripDay(
            dayIndex: 3,
            dateText: "Apr 24, 2025",
            photos: photos(count: 4, location: "Kyoto Station", country: "Japan", baseHour: 11)
                + photos(count: 6, location: "Fushimi Inari", country: "Japan", baseHour: 14),
            countryCode: "JP", countryName: "Japan", cityName: "Kyoto"
        )

        return TripDraft(
            title: "Tokyo & Kyoto, Japan",
            dateRangeText: "Apr 21 - 24, 2025",
            days: [day1, day2, day3, day4],
            coverImageName: "photo",
            isScannedFromDefaultRange: false,
            draftCreatedAgoText: "Just now",
            daysSeasonText: "4 days • Spring 2025",
            coverTheme: "tokyo"
        )
    }()
}

private let previewBlogId = UUID()

#Preview {
    @Previewable @State var isDismissed = false
    EditBlogPhotoFlowView(
        blogId: previewBlogId,
        onDismiss: { isDismissed = true },
        initialTrip: .preview
    )
    .environmentObject(CreatedRecapBlogStore.shared)
    .overlay(alignment: .bottom) {
        if isDismissed {
            Text("Dismissed ✓")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.green.opacity(0.85), in: Capsule())
                .padding(.bottom, 40)
        }
    }
}
