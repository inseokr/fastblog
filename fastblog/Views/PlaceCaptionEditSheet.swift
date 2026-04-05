//
//  PlaceCaptionEditSheet.swift
//  fastblog
//
//  Full-screen place story editor (presented as a fade overlay from RecapBlogPageView).
//

import SwiftUI
import UIKit

struct PlaceCaptionEditSheet: View {
    let placeTitle: String
    let placeSubtitle: String?
    let photos: [RecapPhoto]
    @Binding var caption: String
    /// Bindings for per-photo captions (only the first three thumbnails are shown).
    var photoCaption: (UUID) -> Binding<String>
    /// `placeCaptionChanged` / `changedPhotoIds` reflect edits vs. values when the sheet opened.
    var onSave: (_ placeCaptionChanged: Bool, _ changedPhotoIds: Set<UUID>) -> Void
    var onCancel: () -> Void
    /// When provided, the Enhance button is shown. Receives the draft; returns AI-enriched text.
    var onEnhance: ((String) async -> String)? = nil
    /// Called after AI successfully applies a result (so caller can mark overallStoryIsManual = false).
    var onEnhanceApplied: (() -> Void)? = nil
    /// Pure translation — no AI story generation.
    var onTranslate: ((String) async -> String)? = nil
    /// Parent presents recap `PlacePhotoModalView` for this photo id (e.g. sets `placePhotoModalItem`).
    var onRequestFullPhotoView: ((UUID) -> Void)? = nil
    /// Match `PlacePhotoModalItem.id` while that modal is presented; when it becomes nil, local drafts reload from bindings.
    var activePhotoModalToken: String? = nil
    @State private var editedText: String = ""
    @State private var isEnhancing = false
    @State private var isTranslating = false
    @State private var showEnhanceStylePicker = false
    @State private var showWritingStyleSheet = false
    @AppStorage(StoryWritingStyle.presetStorageKey) private var stylePresetId: String = ""
    /// Captures the user's own text before the first AI run, enabling "Revert to original".
    @State private var originalDraft: String? = nil
    @FocusState private var isFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Matches kebab `PlaceStopActionSheet` “Edit Caption & Details” row (`text.alignleft`).
    private enum CaptionThumbnailSelection: Equatable {
        case placeCaption
        case photo(UUID)
    }

    @State private var captionThumbnailSelection: CaptionThumbnailSelection = .placeCaption
    @State private var draftPlaceCaption: String = ""
    @State private var draftPhotoCaptions: [UUID: String] = [:]
    @State private var initialPlaceCaption: String = ""
    @State private var initialPhotoCaptions: [UUID: String] = [:]

    private let thumbnailSize: CGFloat = 60
    private let thumbnailCorner: CGFloat = 10
    private let thumbnailStroke: CGFloat = 2

    /// Horizontal inset for typed text inside the rounded editor (both sides). Slightly tight so the caret sits a bit left of default.
    private let editorTextHorizontalPadding: CGFloat = 14
    /// Matches outer sheet padding + `editorTextHorizontalPadding` so placeholder lines up with the caret.
    private let placeholderLeadingInset: CGFloat = 34
    private let placeholderTrailingInset: CGFloat = 20

    private var trimmedEditedText: String {
        editedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Matches other blog sheets: non‑Max width + xxxLarge Dynamic Type so long placeholders don’t clip awkwardly.
    private var shouldUseTwoLineCaptionPlaceholder: Bool {
        UIScreen.main.bounds.width < 428 && dynamicTypeSize >= .xxxLarge
    }

    /// Single line by default; explicit newline on narrow phones at largest content sizes.
    private var captionPlaceholderText: String {
        switch captionThumbnailSelection {
        case .placeCaption:
            if shouldUseTwoLineCaptionPlaceholder {
                return "Describe this\nplace..."
            }
            return "Describe this place..."
        case .photo:
            if shouldUseTwoLineCaptionPlaceholder {
                return "Describe this\nmoment..."
            }
            return "Describe this moment..."
        }
    }

    private var captionPlaceholderLineLimit: Int {
        captionThumbnailSelection == .placeCaption ? 2 : 3
    }

    /// Caption editor uses a **fixed** height (scrolls inside). It must not expand with spare vertical space,
    /// or the thumbnail strip can end up under the keyboard on small phones at large Dynamic Type sizes.
    private var captionTextEditorFixedHeight: CGFloat {
        let w = UIScreen.main.bounds.width
        let narrowPhone = w < 400
        let belowLargePhoneWidth = w < 428

        if dynamicTypeSize >= .accessibility5 {
            return narrowPhone ? 92 : 104
        }
        if dynamicTypeSize >= .accessibility3 {
            return narrowPhone ? 104 : 116
        }
        if dynamicTypeSize >= .xxxLarge {
            return belowLargePhoneWidth ? 118 : 132
        }
        if dynamicTypeSize >= .xxLarge {
            return belowLargePhoneWidth ? 132 : 144
        }
        return 152
    }

    @ViewBuilder
    private var captionThumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                placeCaptionThumbnailCell
                ForEach(photos.prefix(3)) { photo in
                    photoThumbnailCell(photo)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: thumbnailSize)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private var placeTitleAndSubtitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(placeTitle)
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
            if let placeSubtitle, !placeSubtitle.isEmpty {
                Text(placeSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 12-hour clock from `RecapPhoto.timestamp` (matches `PlaceStopRowView` strip badges).
    private static let headerPhotoTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

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

    private static func photoTimeDisplayText(for photo: RecapPhoto) -> String {
        if let d = photo.digitizedTime,
           let t = formattedClockTime(fromDigitized: d) {
            return t
        }
        return headerPhotoTimeFormatter.string(from: photo.timestamp)
    }

    /// Shown beside the place name only when a photo thumbnail is selected (place story uses title only).
    @ViewBuilder
    private func headerPhotoThumbnail(for photoId: UUID) -> some View {
        if let photo = photos.first(where: { $0.id == photoId }) {
            RecapPhotoThumbnail(
                photo: photo,
                cornerRadius: thumbnailCorner,
                showIcon: false,
                targetSize: CGSize(width: 200, height: 200)
            )
            .frame(width: thumbnailSize * 3, height: thumbnailSize * 3)
            .clipShape(RoundedRectangle(cornerRadius: thumbnailCorner, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text(Self.photoTimeDisplayText(for: photo))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .padding(6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: thumbnailCorner, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: thumbnailStroke)
            }
            .accessibilityLabel("Editing caption for selected photo")
        } else {
            RoundedRectangle(cornerRadius: thumbnailCorner, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: thumbnailSize * 3, height: thumbnailSize * 3)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Photo")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if case .photo(let photoId) = captionThumbnailSelection {
                    HStack(alignment: .top, spacing: 12) {
                        Group {
                            if let openFull = onRequestFullPhotoView {
                                Button {
                                    syncDraftToUnderlyingBindings()
                                    isFocused = false
                                    openFull(photoId)
                                } label: {
                                    headerPhotoThumbnail(for: photoId)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("View full photo")
                            } else {
                                headerPhotoThumbnail(for: photoId)
                            }
                        }
                        placeTitleAndSubtitle
                    }
                } else {
                    placeTitleAndSubtitle
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $editedText)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundColor(.primary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, editorTextHorizontalPadding)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if editedText.isEmpty {
                    Text(captionPlaceholderText)
                        .font(.body)
                        .foregroundColor(Color(uiColor: .placeholderText))
                        .multilineTextAlignment(.leading)
                        .lineLimit(captionPlaceholderLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, placeholderLeadingInset)
                        .padding(.trailing, placeholderTrailingInset)
                        .padding(.top, 22)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: captionTextEditorFixedHeight)
            .padding(.horizontal, 20)

            if !trimmedEditedText.isEmpty {
                HStack(spacing: 16) {
                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            editedText = ""
                            originalDraft = nil
                        }
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    if let draft = originalDraft {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                editedText = draft
                                originalDraft = nil
                            }
                        } label: {
                            Label("", systemImage: "arrow.uturn.backward")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let translate = onTranslate {
                        Button {
                            runTranslate(translate)
                        } label: {
                            if isTranslating {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.75)
                                    Text("Translating…")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "translate")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled(isEnhancing || isTranslating)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !photos.isEmpty {
                captionThumbnailStrip
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(alignment: .center) {
                Button("Cancel") {
                    isFocused = false
                    onCancel()
                }
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary)
                .buttonStyle(.plain)

                Spacer()

                Button("Done") {
                    flushCurrentDraftFromEditor()
                    caption = draftPlaceCaption
                    for p in photos.prefix(3) {
                        photoCaption(p.id).wrappedValue = draftPhotoCaptions[p.id] ?? ""
                    }
                    let placeChanged = draftPlaceCaption != initialPlaceCaption
                    let changedPhotoIds = Set(
                        photos.prefix(3).map(\.id).filter { id in
                            (draftPhotoCaptions[id] ?? "") != (initialPhotoCaptions[id] ?? "")
                        }
                    )
                    isFocused = false
                    onSave(placeChanged, changedPhotoIds)
                }
                .font(.body)
                .fontWeight(.bold)
                .foregroundStyle(Color(uiColor: .systemBlue))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground))
        }
        .preferredColorScheme(.dark)
        .onAppear {
            initialPlaceCaption = caption
            draftPlaceCaption = caption
            var photoMap: [UUID: String] = [:]
            for p in photos.prefix(3) {
                photoMap[p.id] = p.caption ?? ""
            }
            initialPhotoCaptions = photoMap
            draftPhotoCaptions = photoMap
            editedText = draftPlaceCaption
            captionThumbnailSelection = .placeCaption
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: activePhotoModalToken) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                refreshDraftFromBindings()
            }
        }
    }

    /// Pushes in-memory drafts into the recap bindings so `PlacePhotoModalView` sees the latest text.
    private func syncDraftToUnderlyingBindings() {
        flushCurrentDraftFromEditor()
        caption = draftPlaceCaption
        for p in photos.prefix(3) {
            photoCaption(p.id).wrappedValue = draftPhotoCaptions[p.id] ?? ""
        }
    }

    /// After the full-screen photo viewer dismisses, pull caption text from bindings (modal may have edited them).
    private func refreshDraftFromBindings() {
        draftPlaceCaption = caption
        for p in photos.prefix(3) {
            draftPhotoCaptions[p.id] = photoCaption(p.id).wrappedValue
        }
        switch captionThumbnailSelection {
        case .placeCaption:
            editedText = draftPlaceCaption
        case .photo(let id):
            editedText = draftPhotoCaptions[id] ?? ""
        }
    }

    private func flushCurrentDraftFromEditor() {
        switch captionThumbnailSelection {
        case .placeCaption:
            draftPlaceCaption = editedText
        case .photo(let id):
            draftPhotoCaptions[id] = editedText
        }
    }

    private func selectThumbnail(_ newSelection: CaptionThumbnailSelection) {
        guard newSelection != captionThumbnailSelection else { return }
        flushCurrentDraftFromEditor()
        captionThumbnailSelection = newSelection
        switch newSelection {
        case .placeCaption:
            editedText = draftPlaceCaption
        case .photo(let id):
            editedText = draftPhotoCaptions[id] ?? ""
        }
    }

    private var placeCaptionThumbnailCell: some View {
        let placeSelected = captionThumbnailSelection == .placeCaption
        return Button {
            selectThumbnail(.placeCaption)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: thumbnailCorner, style: .continuous)
                    .fill(placeSelected ? Color.white : Color.clear)
                Image(systemName: "text.alignleft")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(placeSelected ? Color.black : Color.white)
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .opacity(placeSelected ? 1 : 0.6)
            .overlay {
                RoundedRectangle(cornerRadius: thumbnailCorner, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: thumbnailStroke)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Place caption")
    }

    private func photoThumbnailCell(_ photo: RecapPhoto) -> some View {
        let photoSelected = captionThumbnailSelection == .photo(photo.id)
        return Button {
            selectThumbnail(.photo(photo.id))
        } label: {
            RecapPhotoThumbnail(
                photo: photo,
                cornerRadius: thumbnailCorner,
                showIcon: false,
                targetSize: CGSize(width: 200, height: 200)
            )
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: thumbnailCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: thumbnailCorner, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: photoSelected ? thumbnailStroke : 0)
            }
            .opacity(photoSelected ? 1 : (captionThumbnailSelection == .placeCaption ? 1 : 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo thumbnail")
    }

    private var currentStyleTitle: String {
        StoryWritingStyle.preset(for: stylePresetId)?.title
            ?? StoryWritingStyle.preset(matching: UserDefaults.standard.string(forKey: StoryWritingStyle.storageKey) ?? "")?.title
            ?? "Custom"
    }

    private func runEnhance(_ enhance: @escaping (String) async -> String, preset: StoryWritingStylePreset?) {
        if let preset {
            stylePresetId = preset.id
            UserDefaults.standard.set(preset.prompt, forKey: StoryWritingStyle.storageKey)
        }
        if originalDraft == nil { originalDraft = editedText }
        let textToEnhance = editedText
        isEnhancing = true
        Task {
            let result = await enhance(textToEnhance)
            await MainActor.run {
                editedText = result
                isEnhancing = false
                onEnhanceApplied?()
            }
        }
    }

    private func runTranslate(_ translate: @escaping (String) async -> String) {
        if originalDraft == nil { originalDraft = editedText }
        let textToTranslate = editedText
        isTranslating = true
        Task {
            let result = await translate(textToTranslate)
            await MainActor.run {
                editedText = result
                isTranslating = false
            }
        }
    }
}
