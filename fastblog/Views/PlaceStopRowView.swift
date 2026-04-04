//
//  PlaceStopRowView.swift
//  Capper
//

import MapKit
import SwiftUI
import UIKit

// MARK: - UserSentimentPill

/// Text pill for place sentiment: "Loved It" / "Neutral" / "Terrible" (values 3 / 2 / 1).
/// "Loved It" uses the same green as the Park POI category accent.
/// In edit mode: tapping cycles 1 → 2 → 3 → 1 and shows a white capsule outline.
/// In read mode: display only. Shown when the row has caption text.
private struct UserSentimentPill: View {
    let sentiment: Int
    var isEditMode: Bool = false
    var onChanged: ((Int) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    /// Matches `PlacePOICategoryPresentation` `.park` tone.
    private static let lovedAccentColor = PlacePOICategoryPresentation.presentation(forRaw: "MKPOICategoryPark").color

    private var label: String {
        switch sentiment {
        case 1: return "Terrible"
        case 3: return "Loved It"
        default: return "Neutral"
        }
    }

    private var accentColor: Color {
        switch sentiment {
        case 1: return Color(uiColor: .systemRed)
        case 3: return Self.lovedAccentColor
        default: return Color(uiColor: .systemOrange)
        }
    }

    @ViewBuilder
    private var sentimentThumbIcon: some View {
        switch sentiment {
        case 1:
            Image(systemName: "hand.thumbsdown.fill")
                .font(.caption2)
        case 3:
            Image(systemName: "hand.thumbsup.fill")
                .font(.caption2)
        default:
            Image(systemName: "hand.thumbsup.fill")
                .font(.caption2)
                .rotationEffect(.degrees(90))
        }
    }

    private var pill: some View {
        HStack(alignment: .center, spacing: 5) {
            sentimentThumbIcon
                .frame(width: 18, height: 16)
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(accentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, isEditMode ? 6 : 5)
            .background(
                Capsule()
                    .fill(accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14))
            )
            .overlay {
                if isEditMode, onChanged != nil {
                    Capsule()
                        .strokeBorder(Color.white, lineWidth: 1)
                }
            }
    }

    var body: some View {
        if isEditMode, let onChange = onChanged {
            Button {
                // Cycle: 1 → 2 → 3 → 1
                let next = sentiment >= 3 ? 1 : sentiment + 1
                onChange(next)
            } label: {
                pill
            }
            .buttonStyle(.plain)
        } else {
            pill
        }
    }
}

private struct OverallStoryTruncationKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - Place category chip (read vs edit: same footprint, edit adds outline only)

/// Shared pill for place POI category so read-only and edit mode align; edit mode adds a white ring (matches sentiment pill).
private struct PlaceCategoryChip: View {
    let symbol: String?
    let label: String
    let accentColor: Color
    var isEditMode: Bool = false
    /// Read-only recap uses a slightly tighter pill; edit mode keeps more vertical breathing room.
    var verticalPadding: CGFloat = 6
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2)
            }
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(accentColor)
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            Capsule()
                .fill(accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14))
        )
        .overlay {
            if isEditMode {
                Capsule()
                    .strokeBorder(Color.white, lineWidth: 1)
            }
        }
    }

    private static let horizontalPadding: CGFloat = 12
}


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
    /// When set and the place has a resolved name, tapping the category chip opens the category picker (edit flow).
    var onEditCategory: (() -> Void)? = nil
    /// Called when user taps Done on the keyboard toolbar; (stopId, isPlaceNote, photoId if photo caption).
    var onDoneEditingStory: ((UUID, Bool, UUID?) -> Void)?
    /// When set, a magic wand button is shown for the place note (only when user has written text).
    /// Receives the user's current draft; returns the enriched story.
    var onGeneratePlaceStory: ((String) async -> String)?
    /// When set, a magic wand button is shown for the overall story (only when user has written text).
    /// Receives the user's current draft; returns the enriched story.
    var onGenerateOverallStory: ((String) async -> String)?
    /// Reserved for future use. Photo caption enhancement happens in PlacePhotoModalView.
    var onGeneratePhotoCaption: ((RecapPhoto, String) async -> String)?
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
    /// When true, shows a "Writing caption…" spinner inside the caption area (e.g. while place-name-triggered generation runs).
    var isGeneratingCaption: Bool = false
    /// When true, shows a "Generating story…" spinner and disables the Tell Story button.
    var isGeneratingNarrative: Bool = false
    /// When set (and device is capable), shows a "Tell Story" button. Parent manages the async task.
    var onTellPlaceStory: (() -> Void)? = nil
    /// Called when user taps the sentiment pill in edit mode. Receives the new sentiment value (1/2/3).
    var onSentimentChanged: ((Int) -> Void)? = nil

    @FocusState private var focusedPlaceNote: Bool
    @FocusState private var focusedOverallStory: Bool
    @State private var isGeneratingPlaceStory = false
    @State private var isGeneratingOverallStory = false
    @State private var generatingPhotoId: UUID?
    @FocusState private var focusedPhotoId: UUID?
    @State private var expandedCaptionPhotoId: UUID? = nil
    @State private var isOverallStoryExpanded = false
    @State private var isOverallStoryTruncated = false
    // Vibe playback for blog photo thumbnails
    @StateObject private var vibePlayer = VibePlayer()
    @State private var playingVibePhotoId: UUID? = nil
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedBlogFont") private var selectedBlogFont: String = "Serif"

    private var rowSurface: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(uiColor: .secondarySystemGroupedBackground)
    }

    private var rowInset: Color {
        colorScheme == .dark ? Color(white: 0.08) : Color(uiColor: .tertiarySystemGroupedBackground)
    }

    private var rowTitle: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var rowCaptionFilled: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var rowStoryReadColor: Color {
        colorScheme == .dark ? .white.opacity(0.9) : .primary
    }

    private var editNamePillFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.08)
    }

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

    /// Parses EXIF-style `yyyy:MM:dd HH:mm:ss` into a 12-hour clock label (e.g. `3:42 PM`).
    private static func formattedClockTime(fromDigitized digitized: String) -> String? {
        let parts = digitized.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let timeParts = parts[1].split(separator: ":")
        guard timeParts.count >= 2,
              let hours = Int(timeParts[0]),
              let minutes = Int(timeParts[1]) else { return nil }
        let period = hours >= 12 ? "PM" : "AM"
        let h = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
        return "\(h):\(String(format: "%02d", minutes)) \(period)"
    }

    /// Clock time for one photo: digitized EXIF string when present, else asset `timestamp`.
    private func photoTimeDisplayText(for photo: RecapPhoto) -> String? {
        if let d = photo.digitizedTime,
           let t = Self.formattedClockTime(fromDigitized: d) {
            return t
        }
        return Self.visitTimeFormatter.string(from: photo.timestamp)
    }

    @ViewBuilder
    private func photoTimestampBadge(for photo: RecapPhoto) -> some View {
        if let text = photoTimeDisplayText(for: photo) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.black.opacity(0.6))
                .cornerRadius(6)
        }
    }

    /// Photo size in strip — 80% of screen width so one photo is prominent and the next peeks on the right.
    private var thumbnailSize: CGFloat { UIScreen.main.bounds.width * 0.8 }
    /// Returns the local vibe audio URL for a photo if it was captured with the in-app camera.
    private func vibeURL(for photo: RecapPhoto) -> URL? {
        guard let id = photo.localIdentifier,
              let captureId = AppCapturePhotoService.uuid(from: id) else { return nil }
        return AppCapturePhotoService.shared.vibeFileURL(for: captureId)
    }

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
            HStack(alignment: .top, spacing: 12) {
                stopBadge
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        if isEditMode {
                            HStack(alignment: .top, spacing: 10) {
                                Button { onEditName?() } label: {
                                    Text(stop.cleanedPlaceTitle)
                                        .font(Font.blog(selectedBlogFont, size: 22, bold: true))
                                        .foregroundColor(rowTitle)
                                }
                                .buttonStyle(.plain)
                                Button { onEditName?() } label: {
                                    ZStack {
                                        Circle()
                                            .fill(editNamePillFill)
                                        Image(systemName: "square.and.pencil")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(rowTitle)
                                    }
                                    .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit place name")
                            }
                        } else {
                            if let searchURL = StoryPlaceGoogleSearch.url(placeName: stop.placeTitle, placeSubtitle: stop.placeSubtitle) {
                                Link(destination: searchURL) {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(stop.cleanedPlaceTitle)
                                            .font(.blog(selectedBlogFont, size: 22, bold: true))
                                            .foregroundColor(rowTitle)
                                        StoryPlaceExternalLinkIcon(
                                            titleFontSize: UIFont.preferredFont(forTextStyle: .title2).pointSize,
                                            foregroundColor: colorScheme == .dark ? .white.opacity(0.78) : Color.primary.opacity(0.55)
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Search \(stop.placeTitle) on Google")
                            } else {
                                Button {
                                    onNavigate?()
                                } label: {
                                    Text(stop.cleanedPlaceTitle)
                                        .font(.blog(selectedBlogFont, size: 22, bold: true))
                                        .foregroundColor(rowTitle)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open place in Maps")
                            }
                        }
                        Spacer()
                        if isEditMode {
                            Button(action: onDelete) {
                                Image(systemName: "eye.slash")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Hide place")
                        } else {
                            Button { onKebab?() } label: {
                                Image(systemName: "ellipsis")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let subtitle = stop.placeSubtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Category chip + sentiment — aligned with photo section edges
            let cat = categoryInfo(for: stop.placeCategory)
            let hasResolvedPlaceName = day.isPlaceNamesResolved
                && !stop.placeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasCaptionText = !(overallStory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                || stop.photos.contains(where: { !($0.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            let categoryAccent = PlacePOICategoryPresentation.presentation(forRaw: stop.placeCategory).color
            if cat != nil || hasCaptionText {
                HStack(alignment: .center, spacing: 8) {
                    if let cat {
                        if hasResolvedPlaceName, let pickCategory = onEditCategory {
                            Button {
                                pickCategory()
                            } label: {
                                PlaceCategoryChip(
                                    symbol: cat.symbol,
                                    label: cat.label,
                                    accentColor: categoryAccent,
                                    isEditMode: isEditMode,
                                    verticalPadding: isEditMode ? 6 : 5
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Change place category, \(cat.label)")
                        } else {
                            PlaceCategoryChip(
                                symbol: cat.symbol,
                                label: cat.label,
                                accentColor: categoryAccent,
                                isEditMode: isEditMode,
                                verticalPadding: isEditMode ? 6 : 5
                            )
                        }
                    }
                    if hasCaptionText {
                        UserSentimentPill(
                            sentiment: stop.sentiment,
                            isEditMode: isEditMode,
                            onChanged: onSentimentChanged
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }

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
            let shouldShowManagePhotosCard = isEditMode && !stop.photos.isEmpty

            if includedPhotos.count == 1, let photo = includedPhotos.first {
                // --- CASE 2a: Single included photo — full-width hero (read and edit). Manage Photos bar sits above in edit mode.
                VStack(alignment: .leading, spacing: 12) {
                    if shouldShowManagePhotosCard {
                        Button(action: onManagePhotos) {
                            HStack(spacing: 14) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.92), Color.white.opacity(0.58)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .background(rowSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Manage Photos")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                    Text("\(stop.photos.count) \(stop.photos.count == 1 ? "Photo" : "Photos")")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.secondary)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.9))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(rowInset)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Manage Photos, \(stop.photos.count) \(stop.photos.count == 1 ? "photo" : "photos")")
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        RecapPhotoThumbnail(photo: photo, cornerRadius: 10, showIcon: false, targetSize: CGSize(width: 960, height: 640))
                            .frame(maxWidth: .infinity, maxHeight: 260)
                            .clipped()
                            .cornerRadius(10)
                            .overlay(alignment: .topLeading) {
                                photoTimestampBadge(for: photo)
                                    .padding(.leading, 8)
                                    .padding(.top, 8)
                            }
                            .overlay(alignment: .topTrailing) {
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
                            .overlay(alignment: .bottomLeading) {
                                if vibeURL(for: photo) != nil {
                                    let isPlaying = playingVibePhotoId == photo.id && vibePlayer.isPlaying
                                    HStack(spacing: 5) {
                                        Button {
                                            if isPlaying {
                                                vibePlayer.stop()
                                                playingVibePhotoId = nil
                                            } else {
                                                if let url = vibeURL(for: photo) {
                                                    playingVibePhotoId = photo.id
                                                    vibePlayer.play(url: url)
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "waveform")
                                                .font(.system(size: isPlaying ? 15 : 11, weight: .semibold))
                                                .foregroundStyle(
                                                    LinearGradient(colors: [.cyan, .green], startPoint: .top, endPoint: .bottom)
                                                )
                                                .symbolEffect(.variableColor.iterative.reversing, isActive: isPlaying)
                                                .padding(isPlaying ? 8 : 6)
                                                .background(Color.black.opacity(0.55))
                                                .clipShape(Circle())
                                                .overlay(Circle().stroke(Color.green.opacity(isPlaying ? 0.85 : 0.5), lineWidth: isPlaying ? 1.5 : 1))
                                                .scaleEffect(isPlaying ? 1.25 : 1.0)
                                                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isPlaying)
                                        }
                                        .buttonStyle(.plain)
                                        if !isPlaying {
                                            Button {
                                                if let url = vibeURL(for: photo) {
                                                    playingVibePhotoId = photo.id
                                                    vibePlayer.play(url: url)
                                                }
                                            } label: {
                                                Text("Play Vibe")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.black.opacity(0.55))
                                                    .clipShape(Capsule())
                                                    .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                                        }
                                    }
                                    .padding(8)
                                    .animation(.easeInOut(duration: 0.2), value: isPlaying)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onPhotoTapped?(photo) }

                    if isEditMode {
                        Button {
                            onCaptionTapped?(photo.id)
                        } label: {
                            let caption = photoCaption(photo.id).wrappedValue
                            Text(caption.isEmpty ? "Leave a story for this photo" : caption)
                                .font(.caption)
                                .foregroundColor(caption.isEmpty ? .secondary.opacity(0.8) : rowCaptionFilled)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(rowInset)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    } else if !photoCaption(photo.id).wrappedValue.isEmpty {
                        let isExpanded = expandedCaptionPhotoId == photo.id
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedCaptionPhotoId = isExpanded ? nil : photo.id
                            }
                        } label: {
                            Text(photoCaption(photo.id).wrappedValue)
                                .font(.blog(selectedBlogFont, size: 16))
                                .lineSpacing(6)
                                .foregroundColor(rowStoryReadColor)
                                .lineLimit(isExpanded ? nil : 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: isExpanded)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, isEditMode ? 4 : 0)
                .padding(.bottom, isEditMode ? 20 : 12)
            } else if includedPhotos.count > 1 || (includedPhotos.isEmpty && shouldShowManagePhotosCard) {
                // --- CASE 2b: Multiple included photos, or edit mode with none included but a pool to manage — Manage Photos bar + horizontal strip when applicable ---
                VStack(alignment: .leading, spacing: 12) {
                    if shouldShowManagePhotosCard {
                        Button(action: onManagePhotos) {
                            HStack(spacing: 14) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.92), Color.white.opacity(0.58)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .background(rowSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Manage Photos")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                    Text("\(stop.photos.count) \(stop.photos.count == 1 ? "Photo" : "Photos")")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.secondary)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.9))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(rowInset)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Manage Photos, \(stop.photos.count) \(stop.photos.count == 1 ? "photo" : "photos")")
                    }

                    if !includedPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(includedPhotos) { photo in
                                    VStack(alignment: .leading, spacing: 6) {
                                        RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 480, height: 480))
                                            .aspectRatio(1, contentMode: .fill)
                                            .frame(width: thumbnailSize, height: thumbnailSize)
                                            .clipped()
                                            .cornerRadius(8)
                                            .overlay(alignment: .topLeading) {
                                                photoTimestampBadge(for: photo)
                                                    .padding(.leading, 8)
                                                    .padding(.top, 8)
                                            }
                                            .overlay(alignment: .topTrailing) {
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
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                onPhotoTapped?(photo)
                                            }
                                        .overlay(alignment: .bottomLeading) {
                                            if vibeURL(for: photo) != nil {
                                                let isPlaying = playingVibePhotoId == photo.id && vibePlayer.isPlaying
                                                HStack(spacing: 5) {
                                                    Button {
                                                        if isPlaying {
                                                            vibePlayer.stop()
                                                            playingVibePhotoId = nil
                                                        } else {
                                                            if let url = vibeURL(for: photo) {
                                                                playingVibePhotoId = photo.id
                                                                vibePlayer.play(url: url)
                                                            }
                                                        }
                                                    } label: {
                                                        Image(systemName: "waveform")
                                                            .font(.system(size: isPlaying ? 15 : 11, weight: .semibold))
                                                            .foregroundStyle(
                                                                LinearGradient(colors: [.cyan, .green], startPoint: .top, endPoint: .bottom)
                                                            )
                                                            .symbolEffect(.variableColor.iterative.reversing, isActive: isPlaying)
                                                            .padding(isPlaying ? 8 : 6)
                                                            .background(Color.black.opacity(0.55))
                                                            .clipShape(Circle())
                                                            .overlay(Circle().stroke(Color.green.opacity(isPlaying ? 0.85 : 0.5), lineWidth: isPlaying ? 1.5 : 1))
                                                            .scaleEffect(isPlaying ? 1.25 : 1.0)
                                                            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isPlaying)
                                                    }
                                                    .buttonStyle(.plain)

                                                    if !isPlaying {
                                                        Button {
                                                            if let url = vibeURL(for: photo) {
                                                                playingVibePhotoId = photo.id
                                                                vibePlayer.play(url: url)
                                                            }
                                                        } label: {
                                                            Text("Play Vibe")
                                                                .font(.system(size: 11, weight: .semibold))
                                                                .foregroundColor(.white)
                                                                .padding(.horizontal, 8)
                                                                .padding(.vertical, 4)
                                                                .background(Color.black.opacity(0.55))
                                                                .clipShape(Capsule())
                                                                .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
                                                        }
                                                        .buttonStyle(.plain)
                                                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                                                    }
                                                }
                                                .padding(5)
                                                .animation(.easeInOut(duration: 0.2), value: isPlaying)
                                            }
                                        }
                                        if isEditMode {
                                            Button {
                                                onCaptionTapped?(photo.id)
                                            } label: {
                                                let caption = photoCaption(photo.id).wrappedValue
                                                Text(caption.isEmpty ? "Leave a story for this photo" : caption)
                                                    .font(.caption)
                                                    .foregroundColor(caption.isEmpty ? .secondary.opacity(0.8) : rowCaptionFilled)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(8)
                                                    .background(rowInset)
                                                    .cornerRadius(6)
                                            }
                                            .frame(width: thumbnailSize)
                                            .buttonStyle(.plain)
                                        } else if !photoCaption(photo.id).wrappedValue.isEmpty {
                                            let isExpanded = expandedCaptionPhotoId == photo.id
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    expandedCaptionPhotoId = isExpanded ? nil : photo.id
                                                }
                                            } label: {
                                                Text(photoCaption(photo.id).wrappedValue)
                                                    .font(.blog(selectedBlogFont, size: 16))
                                                    .lineSpacing(6)
                                                    .foregroundColor(rowStoryReadColor)
                                                    .lineLimit(isExpanded ? nil : 4)
                                                    .frame(width: thumbnailSize, alignment: .leading)
                                                    .fixedSize(horizontal: false, vertical: isExpanded)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .frame(width: thumbnailSize)
                                    .id(photo.id)
                                }
                            }
                            .padding(.trailing, 16)
                        }
                        .frame(minHeight: isEditMode ? thumbnailSize + 56 : thumbnailSize + 28)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, isEditMode ? 4 : 0)
                .padding(.bottom, isEditMode ? 20 : 12)
            }

            // timelineLine removed per user request
        }
        .background(rowSurface)
        .cornerRadius(16)
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
                            print("🟠 [PlaceStopRowView] Done tapped — stopId:\(stop.id) focusedPlaceNote:\(focusedPlaceNote) focusedOverallStory:\(focusedOverallStory) focusedPhotoId:\(String(describing: focusedPhotoId))")
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
        let isGenerating = isGeneratingCaption || isGeneratingOverallStory
        return VStack(spacing: 0) {
            if isEditMode {
                VStack(alignment: .leading, spacing: 6) {
                    // Tappable caption box — full width, no side column
                    Button {
                        if !isGenerating { onEditPlaceCaption?() }
                    } label: {
                        Group {
                            if isGenerating {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                                        .scaleEffect(0.8)
                                    Text("Writing caption…")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                let displayStory: String = {
                                    let manual = overallStory.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if stop.overallStoryIsManual, !manual.isEmpty { return manual }
                                    if let n = stop.placeNarrative, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return n }
                                    return manual
                                }()
                                Text(displayStory.isEmpty ? placeStoryPlaceholder : displayStory)
                                    .font(Font.blog(selectedBlogFont, size: 17))
                                    .lineSpacing(8)
                                    .foregroundColor(displayStory.isEmpty ? .secondary.opacity(0.9) : rowCaptionFilled)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(12)
                        .background(rowInset)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else if isGeneratingCaption {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                        .scaleEffect(0.8)
                    Text("Writing caption…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)
            } else {
                let displayStory: String = {
                    let manual = overallStory.trimmingCharacters(in: .whitespacesAndNewlines)
                    if stop.overallStoryIsManual, !manual.isEmpty { return manual }
                    if let n = stop.placeNarrative, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return n }
                    return manual
                }()
                if !displayStory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayStory)
                            .font(.blog(selectedBlogFont, size: 17))
                            .lineSpacing(8)
                            .foregroundColor(rowStoryReadColor)
                            .lineLimit(isOverallStoryExpanded ? nil : 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: isOverallStoryExpanded)
                            .background(
                                GeometryReader { constrainedGeo in
                                    Text(displayStory)
                                        .font(.blog(selectedBlogFont, size: 17))
                                        .lineSpacing(8)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(width: constrainedGeo.size.width)
                                        .background(GeometryReader { fullGeo in
                                            Color.clear.preference(
                                                key: OverallStoryTruncationKey.self,
                                                value: fullGeo.size.height > constrainedGeo.size.height + 1
                                            )
                                        })
                                        .hidden()
                                }
                            )
                            .onPreferenceChange(OverallStoryTruncationKey.self) { value in
                                isOverallStoryTruncated = value
                            }

                        if isOverallStoryTruncated || isOverallStoryExpanded {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isOverallStoryExpanded.toggle()
                                }
                            } label: {
                                Text(isOverallStoryExpanded ? "Show less" : "Show more")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, onTellPlaceStory != nil && LocalLLMStoryCaptionGenerator.isCapable && isEditMode ? 8 : 6)
                }
            }
            let placeStoryEmptyForAI: Bool = {
                if let n = stop.placeNarrative, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
                return overallStory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }()
            let showGenerateStoryInStoryRow = isEditMode
                && onTellPlaceStory != nil
                && LocalLLMStoryCaptionGenerator.isCapable
                && placeStoryEmptyForAI
            if showGenerateStoryInStoryRow {
                VStack(alignment: .leading, spacing: 8) {
                    if showGenerateStoryInStoryRow {
                        HStack {
                            Spacer(minLength: 0)
                            if isGeneratingNarrative {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                                        .scaleEffect(0.7)
                                    Text("Generating story…")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            } else if let tell = onTellPlaceStory {
                                Button(action: tell) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                            .font(.caption)
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                        Text("Generate story")
                                            .font(.caption)
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [Color(red: 0.8, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
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
        case _ where raw == "MKPOICategoryMusicVenue": return ("music.mic", "Music Venue")
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
            onEditCategory: nil,
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
