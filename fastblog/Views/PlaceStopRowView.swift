//
//  PlaceStopRowView.swift
//  Capper
//

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
        .foregroundStyle(colorScheme == .dark ? Color.white : accentColor)
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            Capsule()
                .fill(accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14))
        )
    }

    private static let horizontalPadding: CGFloat = 12
}

// MARK: - Add category placeholder (edit mode only)

/// Muted pill when a stop has no POI category yet; opens the category picker on tap.
private struct AddPlaceCategoryPlaceholderChip: View {
    var verticalPadding: CGFloat = 6
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag")
                .font(.caption2)
            Text("Add category")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(Color.secondary.opacity(0.72))
        .padding(.horizontal, 12)
        .padding(.vertical, verticalPadding)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
    }
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
    /// On-device Bloggo capture reel playback (passed from parent — not observed here to avoid re-rendering every place row).
    var reelAutoplay: BlogReelAutoplayCoordinator
    /// Height of each photo/reel tile in the vertical stack (~80% of screen in recap timeline).
    var mediaTileHeight: CGFloat = 560
    var onDelete: () -> Void
    var onKebab: (() -> Void)?
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
    /// When set, shows a "Revert" button next to "Generate story" after a narrative has been generated.
    var onRevertPlaceStory: (() -> Void)? = nil
    /// Called when user taps the sentiment pill in edit mode. Receives the new sentiment value (1/2/3).
    var onSentimentChanged: ((Int) -> Void)? = nil
    /// When set, a "Manage Photos" button is shown below the photo strip in edit mode.
    var onManagePhotos: (() -> Void)? = nil

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
    @State private var showPlaceGoogleSearchSheet = false
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

    /// Clock time for one photo: digitized wall clock when present; else ``RecapPhoto.timestamp`` in the same
    /// timezone chain as fullscreen photo mode (``PlaceStop.recapThumbnailTimeZone`` — not raw device TZ).
    private func photoTimeDisplayText(for photo: RecapPhoto) -> String? {
        if let d = photo.digitizedTime,
           let t = Self.formattedClockTime(fromDigitized: d) {
            return t
        }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = stop.recapThumbnailTimeZone
        return f.string(from: photo.timestamp)
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
                .appChromeCornerRadius(6)
        }
    }

    /// Returns the local vibe audio URL for a photo if it was captured with the in-app camera.
    private func vibeURL(for photo: RecapPhoto) -> URL? {
        guard let id = photo.localIdentifier,
              let captureId = AppCapturePhotoService.uuid(from: id) else { return nil }
        return AppCapturePhotoService.shared.vibeFileURL(for: captureId)
    }

    /// Returns the explicit voice memo file URL for a photo captured in the in-app camera.
    private func voiceMemoURL(for photo: RecapPhoto) -> URL? {
        guard let id = photo.localIdentifier,
              let captureId = AppCapturePhotoService.uuid(from: id) else { return nil }
        return AppCapturePhotoService.shared.voiceMemoFileURL(for: captureId)
    }

    private func momentVideoURL(for photo: RecapPhoto) -> URL? {
        guard let id = photo.localIdentifier,
              let captureId = AppCapturePhotoService.uuid(from: id) else { return nil }
        return AppCapturePhotoService.shared.momentVideoFileURL(for: captureId)
    }

    @StateObject private var voiceMemoPlayer = VibePlayer()
    @State private var playingVoiceMemoPhotoId: UUID? = nil

    private var carouselThumbnailTargetSize: CGSize {
        let width = max(320, UIScreen.main.bounds.width - 16)
        let scale = UIScreen.main.scale
        let pixelWidth = width * scale
        let pixelHeight = mediaTileHeight * scale
        return CGSize(width: pixelWidth, height: pixelHeight)
    }

    /// Read-mode inline reel when a moment clip exists; otherwise the still thumbnail.
    @ViewBuilder
    private func blogPhotoThumbnail(
        photo: RecapPhoto,
        cornerRadius: CGFloat,
        targetSize: CGSize
    ) -> some View {
        if !isEditMode, let url = momentVideoURL(for: photo) {
            InlineMomentReelMedia(
                photo: photo,
                videoURL: url,
                cornerRadius: cornerRadius,
                targetSize: targetSize,
                photoId: photo.id
            )
        } else {
            RecapPhotoThumbnail(photo: photo, cornerRadius: cornerRadius, showIcon: false, targetSize: targetSize)
        }
    }

    @ViewBuilder
    private func photoReadSecondaryContent(for photo: RecapPhoto, width: CGFloat? = nil) -> some View {
        let caption = photoCaption(photo.id).wrappedValue
        let hasCaption = !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isExpanded = expandedCaptionPhotoId == photo.id

        if hasCaption {
            Text(caption)
                .font(.body)
                .foregroundColor(rowStoryReadColor)
                .lineLimit(isExpanded ? nil : 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: isExpanded)
                .contentShape(Rectangle())
                .frame(width: width, alignment: .leading)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedCaptionPhotoId = isExpanded ? nil : photo.id
                    }
                }
        }
    }

    /// True when the focused field (place note or photo caption) has text, so Clear should be red.
    private var clearButtonIsRed: Bool {
        if focusedPlaceNote { return !placeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if focusedOverallStory { return !overallStory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let id = focusedPhotoId { return !photoCaption(id).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }

    /// Top preview photos (max 3) shown in a vertical stack at recap level.
    private var stackPhotos: [RecapPhoto] {
        Array(displayableIncludedPhotos.prefix(3))
    }

    /// Included photos that still resolve to real pixels (omits deleted library assets / missing app captures).
    private var displayableIncludedPhotos: [RecapPhoto] {
        stop.photos.filter(\.isIncluded).filter(\.hasDisplayableLocalBacking)
    }

    @ViewBuilder
    private func mediaSlide(for photo: RecapPhoto) -> some View {
        GeometryReader { geo in
            blogPhotoThumbnail(
                photo: photo,
                cornerRadius: 0,
                targetSize: carouselThumbnailTargetSize
            )
            .aspectRatio(contentMode: .fill)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: mediaTileHeight)
        .appChromeCornerRadius(10)
        .overlay(alignment: .topLeading) {
            photoTimestampBadge(for: photo)
                .padding(.leading, 8)
                .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                if hasMomentVideo(for: photo), !isEditMode {
                    Image(systemName: "video.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
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
                }
            }
            .padding(8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPhotoTapped?(photo)
        }
        .blogReelCandidate(
            photoId: photo.id,
            isActive: !isEditMode && hasMomentVideo(for: photo)
        )
    }

    private func hasMomentVideo(for photo: RecapPhoto) -> Bool {
        momentVideoURL(for: photo) != nil
    }

    @ViewBuilder
    private func verticalPhotoBlock(photo: RecapPhoto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            mediaSlide(for: photo)

            if !isEditMode, hasMediaControls(for: photo) {
                PlaceMediaControlBar(
                    photos: [photo],
                    focusedPhotoId: photo.id,
                    reelAutoplay: reelAutoplay,
                    momentVideoURL: momentVideoURL(for:),
                    vibeURL: vibeURL(for:),
                    voiceMemoURL: voiceMemoURL(for:),
                    playingVibePhotoId: playingVibePhotoId,
                    playingVoiceMemoPhotoId: playingVoiceMemoPhotoId,
                    vibeIsPlaying: vibePlayer.isPlaying,
                    voiceMemoIsPlaying: voiceMemoPlayer.isPlaying,
                    onToggleVibe: toggleVibe(for:),
                    onToggleVoiceMemo: toggleVoiceMemo(for:)
                )
                .padding(.horizontal, 12)
            }

            if isEditMode {
                Button {
                    onCaptionTapped?(photo.id)
                } label: {
                    let caption = photoCaption(photo.id).wrappedValue
                    Text(caption.isEmpty ? "Leave a story for this photo" : caption)
                        .font(.subheadline)
                        .foregroundColor(caption.isEmpty ? .secondary.opacity(0.8) : rowCaptionFilled)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(rowInset)
                        .appChromeCornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            } else {
                photoReadSecondaryContent(for: photo)
                    .padding(.horizontal, 12)
            }
        }
    }

    private func hasMediaControls(for photo: RecapPhoto) -> Bool {
        momentVideoURL(for: photo) != nil
            || vibeURL(for: photo) != nil
            || voiceMemoURL(for: photo) != nil
    }

    private func toggleVibe(for photo: RecapPhoto) {
        if playingVibePhotoId == photo.id && vibePlayer.isPlaying {
            vibePlayer.stop()
            playingVibePhotoId = nil
        } else if let url = vibeURL(for: photo) {
            voiceMemoPlayer.stop()
            playingVoiceMemoPhotoId = nil
            reelAutoplay.pauseForAlternateAudio()
            playingVibePhotoId = photo.id
            vibePlayer.play(url: url)
        }
    }

    private func toggleVoiceMemo(for photo: RecapPhoto) {
        if playingVoiceMemoPhotoId == photo.id && voiceMemoPlayer.isPlaying {
            voiceMemoPlayer.stop()
            playingVoiceMemoPhotoId = nil
        } else if let memoURL = voiceMemoURL(for: photo) {
            vibePlayer.stop()
            playingVibePhotoId = nil
            reelAutoplay.pauseForAlternateAudio()
            playingVoiceMemoPhotoId = photo.id
            voiceMemoPlayer.play(url: memoURL)
        }
    }

    @ViewBuilder
    private var placeMediaSection: some View {
        let totalPhotoCount = displayableIncludedPhotos.count
        let photos = stackPhotos

        VStack(alignment: .leading, spacing: 12) {
            if isEditMode, let onManagePhotos {
                Button(action: onManagePhotos) {
                    Label("Manage Photos", systemImage: "photo.stack")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .background(rowInset)
                        .appChromeCornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }

            if photos.isEmpty && isEditMode && !stop.photos.isEmpty {
                Text("No photos are shown for this place.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
            }

            if !photos.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    PlaceMediaCarouselView(
                        photos: photos,
                        isEditMode: isEditMode,
                        reportsReelCandidates: false,
                        cornerRadius: 10,
                        slideContent: { photo in
                            verticalPhotoBlock(photo: photo)
                        }
                    )

                    if !isEditMode, totalPhotoCount > 3,
                       let firstHidden = displayableIncludedPhotos.dropFirst(3).first {
                        Button {
                            onPhotoTapped?(firstHidden)
                        } label: {
                            HStack(spacing: 6) {
                                Text("Show all \(totalPhotoCount) photos")
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show all \(totalPhotoCount) photos")
                        .padding(.horizontal, 12)
                    }
                }
                .onChange(of: reelAutoplay.isUserMuted) { _, muted in
                    if !muted {
                        vibePlayer.stop()
                        playingVibePhotoId = nil
                        voiceMemoPlayer.stop()
                        playingVoiceMemoPhotoId = nil
                    }
                }
            }
        }
        .padding(.top, isEditMode ? 4 : 0)
        .padding(.bottom, isEditMode ? 20 : 12)
    }

    /// Blue coachmark pill when the place name has never been manually edited (`placeTitleIsManual` is false).
    private var tapToRenamePill: some View {
        let blue = Color(uiColor: .systemBlue)
        return HStack(spacing: 6) {
            Image(systemName: "hand.tap.fill")
                .font(.subheadline.weight(.bold))
            Text("Tap to rename")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(blue)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(blue.opacity(colorScheme == .dark ? 0.25 : 0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(blue.opacity(colorScheme == .dark ? 0.5 : 0.28), lineWidth: 1)
        )
    }

    private var categoryPresentForRow: PlacePOICategoryPresentation.Info? {
        PlacePOICategoryPresentation.presentationForPlaceRow(
            storedCategory: stop.placeCategory,
            placeTitle: stop.placeTitle
        )
    }

    private var hasResolvedPlaceNameForCategory: Bool {
        day.isPlaceNamesResolved
            && !stop.placeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasCaptionTextForCategoryRow: Bool {
        !(overallStory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || stop.photos.contains(where: { !($0.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    @ViewBuilder
    private var sentimentPillForRow: some View {
        if hasCaptionTextForCategoryRow || isEditMode {
            UserSentimentPill(
                sentiment: stop.sentiment,
                isEditMode: isEditMode,
                onChanged: onSentimentChanged
            )
        }
    }

    /// Shown when edit mode allows picking a category and none is set yet (excluding inferred-from-title presentation).
    private var showAddCategoryPlaceholder: Bool {
        isEditMode
            && onEditCategory != nil
            && hasResolvedPlaceNameForCategory
            && categoryPresentForRow == nil
    }

    /// Inline beside "Tap to rename"; once the title is manual, the chip stays in the category row only.
    private var showAddCategoryBesideTapToRename: Bool {
        showAddCategoryPlaceholder && !stop.placeTitleIsManual
    }

    /// Category row still shows the placeholder when the title was renamed but category is still unset.
    private var showAddCategoryInCategoryRow: Bool {
        showAddCategoryPlaceholder && stop.placeTitleIsManual
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Button { onEditName?() } label: {
                                        Text(stop.cleanedPlaceTitle)
                                            .font(Font.blog(selectedBlogFont, size: 22, bold: true))
                                            .foregroundColor(rowTitle)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(!stop.placeTitleIsManual ? "Tap to rename" : stop.cleanedPlaceTitle)

                                    if !stop.placeTitleIsManual,
                                       let subtitle = stop.placeSubtitle,
                                       !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }

                                    if !stop.placeTitleIsManual {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(alignment: .center, spacing: 8) {
                                                Button { onEditName?() } label: {
                                                    tapToRenamePill
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Tap to rename")

                                                if showAddCategoryBesideTapToRename, let pickCategory = onEditCategory {
                                                    Button {
                                                        pickCategory()
                                                    } label: {
                                                        AddPlaceCategoryPlaceholderChip(verticalPadding: isEditMode ? 6 : 5)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .accessibilityLabel("Add place category")
                                                } else if let cat = categoryPresentForRow {
                                                    // Named category persists even when MapKit/autocomplete never marked the title manual
                                                    // (“Tap to rename” flow). Previously we hid Add category without painting the chip.
                                                    let categoryAccent = cat.color
                                                    if hasResolvedPlaceNameForCategory, let pickCategory = onEditCategory {
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
                                            }
                                            sentimentPillForRow
                                        }
                                    } else {
                                        if let subtitle = stop.placeSubtitle, !subtitle.isEmpty {
                                            Text(subtitle)
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                        HStack(alignment: .center, spacing: 8) {
                                            if let cat = categoryPresentForRow {
                                                let categoryAccent = cat.color
                                                if hasResolvedPlaceNameForCategory, let pickCategory = onEditCategory {
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
                                            } else if showAddCategoryInCategoryRow, let pickCategory = onEditCategory {
                                                Button {
                                                    pickCategory()
                                                } label: {
                                                    AddPlaceCategoryPlaceholderChip(verticalPadding: isEditMode ? 6 : 5)
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Add place category")
                                            }

                                            sentimentPillForRow
                                        }
                                    }
                                }
                            }
                        } else {
                            HStack(alignment: .top, spacing: 10) {
                                Group {
                                    if StoryPlaceGoogleSearch.url(placeName: stop.placeTitle, placeSubtitle: stop.placeSubtitle) != nil {
                                        Button {
                                            showPlaceGoogleSearchSheet = true
                                        } label: {
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
                                        .accessibilityLabel("Web results for \(stop.placeTitle)")
                                        .sheet(isPresented: $showPlaceGoogleSearchSheet) {
                                            PlaceGoogleSearchSheet(
                                                placeTitle: stop.placeTitle,
                                                placeSubtitle: stop.placeSubtitle,
                                                displayTitle: stop.cleanedPlaceTitle
                                            )
                                        }
                                    } else if let navigate = onNavigate {
                                        Button {
                                            navigate()
                                        } label: {
                                            Text(stop.cleanedPlaceTitle)
                                                .font(.blog(selectedBlogFont, size: 22, bold: true))
                                                .foregroundColor(rowTitle)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Open place in Maps")
                                    } else {
                                        Text(stop.cleanedPlaceTitle)
                                            .font(.blog(selectedBlogFont, size: 22, bold: true))
                                            .foregroundColor(rowTitle)
                                    }
                                }
                            }
                        }
                        Spacer()
                        if isEditMode {
                            HStack(spacing: 12) {
                                if stop.placeTitleIsManual {
                                    Button { onEditName?() } label: {
                                        ZStack {
                                            Circle()
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.08))
                                            Image(systemName: "square.and.pencil")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(rowTitle)
                                        }
                                        .frame(width: 28, height: 28)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Edit place name")
                                }
                                Button(action: onDelete) {
                                    Image(systemName: "eye.slash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Hide place")
                            }
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
                    if !isEditMode,
                       let subtitle = stop.placeSubtitle,
                       !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Category chip + sentiment — aligned with photo section edges (same POI presentation as My Places / map).
            let categoryPresent = categoryPresentForRow
            let hasCaptionText = hasCaptionTextForCategoryRow
            if (!isEditMode) && (categoryPresent != nil || showAddCategoryInCategoryRow || hasCaptionText) {
                HStack(alignment: .center, spacing: 8) {
                    if let cat = categoryPresent {
                        let categoryAccent = cat.color
                        if hasResolvedPlaceNameForCategory, let pickCategory = onEditCategory {
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
                    } else if showAddCategoryInCategoryRow, let pickCategory = onEditCategory {
                        Button {
                            pickCategory()
                        } label: {
                            AddPlaceCategoryPlaceholderChip(verticalPadding: isEditMode ? 6 : 5)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add place category")
                    }
                    sentimentPillForRow
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
            //             .appChromeCornerRadius(8)
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

            // Photo media: 4:5 carousel (top 3) + unified controls
            if !displayableIncludedPhotos.isEmpty || (isEditMode && !stop.photos.isEmpty) {
                placeMediaSection
            }

            // timelineLine removed per user request
        }
        .background(rowSurface)
        .appChromeCornerRadius(16)
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
        .onChange(of: playingVibePhotoId) { _, photoId in
            reelAutoplay.setUserPlaybackSuspended(photoId != nil)
        }
        .onChange(of: playingVoiceMemoPhotoId) { _, photoId in
            if photoId != nil {
                reelAutoplay.setUserPlaybackSuspended(true)
            } else if playingVibePhotoId == nil {
                reelAutoplay.setUserPlaybackSuspended(false)
            }
        }
        .onDisappear {
            vibePlayer.stop()
            voiceMemoPlayer.stop()
            playingVibePhotoId = nil
            playingVoiceMemoPhotoId = nil
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
                        .appChromeCornerRadius(10)
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
            let hasAIPlaceNarrative = (stop.placeNarrative ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let showGenerateStoryInStoryRow = isEditMode
                && onTellPlaceStory != nil
                && LocalLLMStoryCaptionGenerator.isCapable
                && (placeStoryEmptyForAI || hasAIPlaceNarrative)
            if showGenerateStoryInStoryRow {
                VStack(alignment: .leading, spacing: 8) {
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
                        } else {
                            if hasAIPlaceNarrative, let revert = onRevertPlaceStory {
                                Button(action: revert) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.uturn.backward")
                                            .font(.caption)
                                        Text("Revert")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            if let tell = onTellPlaceStory {
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
                .padding(.top, 2)
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
            reelAutoplay: BlogReelAutoplayCoordinator(),
            mediaTileHeight: 560,
            onDelete: {},
            onKebab: nil,
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
