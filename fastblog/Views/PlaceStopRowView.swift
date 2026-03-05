//
//  PlaceStopRowView.swift
//  Capper
//

import MapKit
import SwiftUI



struct PlaceStopRowView: View {
    let day: RecapBlogDay
    let stop: PlaceStop
    let stopNumber: Int
    var isEditMode: Bool = true
    var badgeColor: Color = .blue
    @Binding var placeNote: String
    @Binding var overallStory: String
    var photoCaption: (UUID) -> Binding<String>
    var onDelete: () -> Void
    var onKebab: (() -> Void)?
    var onManagePhotos: () -> Void
    var onRemovePhoto: ((UUID) -> Void)?
    var onPhotoTapped: ((RecapPhoto) -> Void)?
    var onCaptionFocus: ((UUID) -> Void)?
    var onNavigate: (() -> Void)?
    var onEditName: (() -> Void)?
    /// Called when user taps Done on the keyboard toolbar; (stopId, isPlaceNote, photoId if photo caption).
    var onDoneEditingStory: ((UUID, Bool, UUID?) -> Void)?
    /// When set, a "Generate" button is shown for the place note. Returns AI-generated place story.
    var onGeneratePlaceStory: (() async -> String)?
    /// When set, a "Generate" button is shown for the overall story. Returns quick summary from photo captions.
    var onGenerateOverallStory: (() async -> String)?
    /// When set, a "Generate" button is shown for each photo caption. Returns AI-generated caption for that photo.
    var onGeneratePhotoCaption: ((RecapPhoto) async -> String)?
    /// Called after the user types in a photo caption field (not AI). Used to mark captionIsManual = true.
    var onPhotoUserEdited: ((UUID) -> Void)?
    /// Called when the user taps a photo caption (read mode) — used to open the Edit Caption modal.
    var onCaptionTapped: ((UUID) -> Void)?
    /// Called after the user types in the overall story field (not AI). Used to mark overallStoryIsManual = true.
    var onOverallStoryUserEdited: (() -> Void)?
    /// Called after AI successfully applied a caption to a photo. Used to cascade overall story.
    var onAICaptionApplied: ((UUID) -> Void)?
    /// Called after AI successfully applied the overall story. Used to mark overallStoryIsManual = false.
    var onAIOverallStoryApplied: (() -> Void)?
    /// When set, tapping the place caption row in edit mode opens the pull-up caption edit modal.
    var onEditPlaceCaption: (() -> Void)?

    @FocusState private var focusedPlaceNote: Bool
    @FocusState private var focusedOverallStory: Bool
    @State private var isGeneratingPlaceStory = false
    @State private var isGeneratingOverallStory = false
    @State private var generatingPhotoId: UUID?
    @FocusState private var focusedPhotoId: UUID?

    /// 12-hour visit time from earliest photo timestamp. Formatter: "h:mm a" (e.g. 3:42 PM).
    private static let visitTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var dayDateText: String {
        Self.dayDateFormatter.string(from: day.date)
    }

    private var visitTimeText: String? {
        // Prefer visitedTimeDigitized (EXIF local time — already timezone-correct) over
        // photo.timestamp (UTC Date formatted in device timezone, which may differ from capture location).
        if let digitized = stop.visitedTimeDigitized {
            let parts = digitized.split(separator: " ")
            if parts.count == 2 {
                let timeParts = parts[1].split(separator: ":")
                if timeParts.count >= 2,
                   let hours = Int(timeParts[0]),
                   let minutes = Int(timeParts[1]) {
                    let period = hours >= 12 ? "PM" : "AM"
                    let h = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
                    return "\(h):\(String(format: "%02d", minutes)) \(period)"
                }
            }
        }
        return stop.photos.map(\.timestamp).min().map { Self.visitTimeFormatter.string(from: $0) }
    }

    /// Photo size in strip (doubled from prior 120 so one photo is prominent and next peeks on the right).
    private let thumbnailSize: CGFloat = 240

    /// True when the focused field (place note or photo caption) has text, so Clear should be red.
    private var clearButtonIsRed: Bool {
        if focusedPlaceNote { return !placeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if focusedOverallStory { return !overallStory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let id = focusedPhotoId { return !photoCaption(id).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: badge + title, subtitle, time
            HStack(alignment: .center, spacing: 12) {
                stopBadge
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if isEditMode {
                            Button { onEditName?() } label: {
                                HStack(spacing: 4) {
                                    Text(stop.placeTitle)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Image(systemName: "pencil")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                onNavigate?()
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text(stop.placeTitle)
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        if isEditMode {
                            Button(action: onDelete) {
                                Image(systemName: "eye.slash")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                            }
                        } else {
                            Button { onKebab?() } label: {
                                Image(systemName: "ellipsis")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                    if let subtitle = stop.placeSubtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    let cat = categoryInfo(for: stop.placeCategory)
                    if visitTimeText != nil || cat != nil {
                        HStack(spacing: 8) {
                            if let time = visitTimeText {
                                Text(time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let cat {
                                if isEditMode {
                                    Button { onEditName?() } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: cat.symbol)
                                                .font(.caption2)
                                            Text(cat.label)
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: cat.symbol)
                                            .font(.caption2)
                                        Text(cat.label)
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Place story: between place info and photos — creative placeholder to encourage writing
            placeStoryRow

            // // Place note (longer note for your future self)
            // if isEditMode {
            //     HStack(alignment: .top, spacing: 8) {
            //         TextEditor(text: $placeNote)
            //             .scrollContentBackground(.hidden)
            //             .frame(minHeight: 44)
            //             .foregroundColor(.white)
            //             .background(Color(white: 0.08))
            //             .cornerRadius(8)
            //             .overlay(alignment: .topLeading) {
            //                 if placeNote.isEmpty {
            //                     Text("Leave a note for your future self")
            //                         .font(.body)
            //                         .foregroundColor(.secondary)
            //                         .padding(8)
            //                         .allowsHitTesting(false)
            //                 }
            //             }
            //             .focused($focusedPlaceNote)
            //             .onChange(of: focusedPlaceNote) { _, isFocused in
            //                 if isFocused { onCaptionFocus?(stop.id) }
            //             }
            //         if let generate = onGeneratePlaceStory {
            //             Button {
            //                 isGeneratingPlaceStory = true
            //                 Task {
            //                     let text = await generate()
            //                     await MainActor.run {
            //                         placeNote = text
            //                         isGeneratingPlaceStory = false
            //                     }
            //                 }
            //             } label: {
            //                 Image(systemName: "wand.and.stars")
            //                     .font(.body)
            //                     .foregroundColor(.white.opacity(0.9))
            //             }
            //             .disabled(isGeneratingPlaceStory)
            //         }
            //     }
            //     .padding(.leading, 16)
            //     .padding(.trailing, 16)
            //     .padding(.bottom, 12)
            // } else if !placeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            //     HStack(alignment: .top, spacing: 0) {
            //         Text(placeNote)
            //             .font(.body)
            //             .foregroundColor(.white.opacity(0.9))
            //             .frame(maxWidth: .infinity, alignment: .leading)
            //     }
            //     .padding(.leading, 16)
            //     .padding(.trailing, 16)
            //     .padding(.bottom, 12)
            // }

            // Photo strip: large thumbnails; one full photo visible + peek of next so users know they can scroll
            let includedPhotos = stop.photos.filter(\.isIncluded)
            let hasAnyPhotos = !stop.photos.isEmpty
            let hasMultipleAvailable = stop.photos.count > 1

            // --- CASE 1: No included photos — show standalone "Manage Photos" button in edit mode ---
            if isEditMode && includedPhotos.isEmpty && hasAnyPhotos {
                Button(action: onManagePhotos) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.body)
                        Text("Manage Photos")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.08))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            } else if !includedPhotos.isEmpty {
                // --- CASE 2: 1+ included photos — always use horizontal scroll + outlined Manage Photos card ---
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(includedPhotos) { photo in
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 480, height: 480))
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(width: thumbnailSize, height: thumbnailSize)
                                        .clipped()
                                        .cornerRadius(8)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            onPhotoTapped?(photo)
                                        }
                                    if isEditMode {
                                        Button {
                                            onRemovePhoto?(photo.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 30))
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, Color.black.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(6)
                                    }
                                }
                                if isEditMode {
                                    Button {
                                        onCaptionTapped?(photo.id)
                                    } label: {
                                        let caption = photoCaption(photo.id).wrappedValue
                                        Text(caption.isEmpty ? "Leave a story for this photo" : caption)
                                            .font(.caption)
                                            .foregroundColor(caption.isEmpty ? .secondary.opacity(0.8) : .white)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(8)
                                            .background(Color(white: 0.08))
                                            .cornerRadius(6)
                                    }
                                    .frame(width: thumbnailSize)
                                    .buttonStyle(.plain)
                                } else if !photoCaption(photo.id).wrappedValue.isEmpty {
                                    Button {
                                        onCaptionTapped?(photo.id)
                                    } label: {
                                        Text(photoCaption(photo.id).wrappedValue)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.9))
                                            .lineLimit(2)
                                            .frame(width: thumbnailSize, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(width: thumbnailSize)
                            .id(photo.id)
                        }
                        // Outlined-box Manage Photos card — always shown in edit mode when photos exist
                        if isEditMode && hasMultipleAvailable {
                            Button(action: onManagePhotos) {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
                                    .frame(width: thumbnailSize, height: thumbnailSize)
                                    .overlay {
                                        VStack(spacing: 6) {
                                            Image(systemName: "photo.on.rectangle")
                                                .font(.system(size: 40))
                                                .foregroundColor(.white)
                                            Text("Manage Photos")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 32) // Extra space so Manage Photos card scrolls fully into view
                }
                .frame(height: isEditMode ? thumbnailSize + 56 : thumbnailSize + 28)
                .padding(.top, 8) // Added top padding here
                .padding(.bottom, isEditMode ? 20 : 12)
            }

            // timelineLine removed per user request
        }
        .background(Color(white: 0.12))
        .cornerRadius(12)
        .toolbar {
            if focusedPlaceNote || focusedOverallStory || focusedPhotoId != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    KeyboardCaptionToolbar(
                        onCancel: {
                            focusedPlaceNote = false
                            focusedOverallStory = false
                            focusedPhotoId = nil
                        },
                        onClear: {
                            if focusedPlaceNote {
                                placeNote = ""
                            } else if focusedOverallStory {
                                overallStory = ""
                            } else if let id = focusedPhotoId {
                                photoCaption(id).wrappedValue = ""
                            }
                        },
                        onDone: {
                            onDoneEditingStory?(stop.id, focusedPlaceNote || focusedOverallStory, focusedPhotoId)
                            focusedPlaceNote = false
                            focusedOverallStory = false
                            focusedPhotoId = nil
                        },
                        isClearRed: clearButtonIsRed,
                        doneButtonTitle: "Done"
                    )
                }
            }
        }
    }

    /// Place story row: between place info and photos. Creative placeholder to encourage writing.
    private var placeStoryRow: some View {
        Group {
            if isEditMode {
                HStack(alignment: .top, spacing: 8) {
                    // Tappable display — opens PlaceCaptionEditSheet
                    Button {
                        onEditPlaceCaption?()
                    } label: {
                        HStack {
                            let trimmed = overallStory.trimmingCharacters(in: .whitespacesAndNewlines)
                            Text(trimmed.isEmpty ? placeStoryPlaceholder : trimmed)
                                .font(.subheadline)
                                .foregroundColor(trimmed.isEmpty ? .secondary.opacity(0.9) : .white)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(Color(white: 0.08))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    if let generate = onGenerateOverallStory {
                        Button {
                            isGeneratingOverallStory = true
                            Task {
                                let text = await generate()
                                await MainActor.run {
                                    overallStory = text
                                    isGeneratingOverallStory = false
                                    onAIOverallStoryApplied?()
                                }
                            }
                        } label: {
                            if isGeneratingOverallStory {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .disabled(isGeneratingOverallStory)
                        .padding(.top, 12)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            } else if !overallStory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(overallStory)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    /// Rotating encouraging placeholder so the story field feels inviting.
    private var placeStoryPlaceholder: String {
        let options = [
            "What made this stop special? A view, a meal, a laugh—one line is enough.",
            "One sentence that captures this place? Your future self will love it.",
            "What’s the one thing you’d want to remember? Tap and tell the story.",
            "A moment worth saving—what would you tell a friend about this spot?",
        ]
        let index = abs(stop.id.hashValue) % options.count
        return options[index]
    }

    private var stopBadge: some View {
        Text("\(stopNumber)")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(badgeColor)
            .clipShape(Circle())
    }

    private var timelineLine: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 2)
            .frame(maxHeight: 24)
            .padding(.leading, 27)
    }

    private func categoryInfo(for rawValue: String?) -> (symbol: String, label: String)? {
        guard let raw = rawValue else { return nil }
        let cat = MKPointOfInterestCategory(rawValue: raw)
        switch cat {
        case .restaurant:      return ("fork.knife", "Restaurant")
        case .cafe:            return ("cup.and.saucer.fill", "Café")
        case .bakery:          return ("birthday.cake.fill", "Bakery")
        case .winery:          return ("wineglass.fill", "Winery")
        case .brewery:         return ("mug.fill", "Brewery")
        case .nightlife:       return ("moon.stars.fill", "Nightlife")
        case .hotel:           return ("bed.double.fill", "Hotel")
        case .campground:      return ("tent.fill", "Campground")
        case .museum:          return ("building.columns.fill", "Museum")
        case .movieTheater:    return ("film.fill", "Movie Theater")
        case .theater:         return ("theatermasks.fill", "Theater")
        case .amusementPark:   return ("ferriswheel", "Amusement Park")
        case .zoo:             return ("pawprint.fill", "Zoo")
        case .aquarium:        return ("fish.fill", "Aquarium")
        case .park:            return ("leaf.fill", "Park")
        case .beach:           return ("beach.umbrella.fill", "Beach")
        case .nationalPark:    return ("tree.fill", "National Park")
        case .airport:         return ("airplane", "Airport")
        case .publicTransport: return ("tram.fill", "Transit")
        case .gasStation:      return ("fuelpump.fill", "Gas Station")
        case .hospital:        return ("cross.fill", "Hospital")
        case .pharmacy:        return ("cross.case.fill", "Pharmacy")
        case .fitnessCenter:   return ("dumbbell.fill", "Fitness")
        case .store:           return ("bag.fill", "Store")
        case .foodMarket:      return ("cart.fill", "Market")
        case .library:         return ("books.vertical.fill", "Library")
        case .school:          return ("graduationcap.fill", "School")
        case .university:      return ("graduationcap.fill", "University")
        case .marina:          return ("sailboat.fill", "Marina")
        case .stadium:         return ("sportscourt.fill", "Stadium")
        case .bank:            return ("banknote.fill", "Bank")
        default:               return nil
        }
    }
}

#Preview {
    ScrollView {
        PlaceStopRowView(
            day: RecapBlogDay(dayIndex: 1, date: Date(), placeStops: []),
            stop: PlaceStop(
                orderIndex: 0,
                placeTitle: "Iceland Ring Road",
                photos: [RecapPhoto(timestamp: Date(), imageName: "photo")]
            ),
            stopNumber: 1,
            placeNote: .constant(""),
            overallStory: .constant(""),
            photoCaption: { _ in .constant("") },
            onDelete: {},
            onKebab: nil,
            onManagePhotos: {},
            onRemovePhoto: nil,
            onPhotoTapped: nil,
            onCaptionFocus: nil,
            onNavigate: nil,
            onEditName: nil,
            onDoneEditingStory: nil,
            onGeneratePlaceStory: nil,
            onGenerateOverallStory: nil,
            onGeneratePhotoCaption: nil
        )
        .padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
