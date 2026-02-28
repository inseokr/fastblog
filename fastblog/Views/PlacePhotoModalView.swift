//
//  PlacePhotoModalView.swift
//  fastblog
//

import SwiftUI

/// Identifiable item for presenting the place photo modal (day + stop + initial photo).
struct PlacePhotoModalItem: Identifiable {
    let dayId: UUID
    let stopId: UUID
    let initialPhotoId: UUID
    var id: String { "\(dayId.uuidString)-\(stopId.uuidString)-\(initialPhotoId.uuidString)" }
}

/// Presents when user taps a photo in a Place. Full-screen photo viewer with overlays.
struct PlacePhotoModalView: View {
    @Binding var placeTitle: String
    let placeSubtitle: String?
    let photos: [RecapPhoto]
    let initialPhotoId: UUID
    var blogIsEditMode: Bool = false
    var photoCaption: (UUID) -> Binding<String>
    var onDismiss: () -> Void
    /// When provided, a "Generate" button is shown in the caption editing panel. Called with (photo, placeName, placeSubtitle); returns generated caption.
    var onGenerateCaption: ((RecapPhoto, String, String?) async -> String)?
    /// Called after the AI wand applies a caption. Used to mark captionIsManual = false and cascade overall story.
    var onAICaptionApplied: ((UUID) -> Void)?
    /// Called when the user manually edits a photo caption in the modal. Used to mark captionIsManual = true.
    var onPhotoCaptionManuallyEdited: ((UUID) -> Void)?

    @State private var currentPhotoId: UUID
    @State private var isGeneratingCaption = false
    @State private var isOverlayHidden = false
    @State private var isEditing = false
    @State private var editedCaptionText: String = ""
    @State private var editedPlaceTitle: String = ""
    /// Caption and Title when user entered edit mode; used by Cancel to revert with no save.
    @State private var captionWhenEditingStarted: String = ""
    @State private var titleWhenEditingStarted: String = ""
    @State private var debounceTask: Task<Void, Never>?

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy 'at' h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init(
        placeTitle: Binding<String>,
        placeSubtitle: String?,
        photos: [RecapPhoto],
        initialPhotoId: UUID,
        blogIsEditMode: Bool = false,
        photoCaption: @escaping (UUID) -> Binding<String>,
        onDismiss: @escaping () -> Void,
        onGenerateCaption: ((RecapPhoto, String, String?) async -> String)? = nil,
        onAICaptionApplied: ((UUID) -> Void)? = nil,
        onPhotoCaptionManuallyEdited: ((UUID) -> Void)? = nil
    ) {
        self._placeTitle = placeTitle
        self.placeSubtitle = placeSubtitle
        self.photos = photos
        self.initialPhotoId = initialPhotoId
        self.blogIsEditMode = blogIsEditMode
        self.photoCaption = photoCaption
        self.onDismiss = onDismiss
        self.onGenerateCaption = onGenerateCaption
        self.onAICaptionApplied = onAICaptionApplied
        self.onPhotoCaptionManuallyEdited = onPhotoCaptionManuallyEdited
        _currentPhotoId = State(initialValue: initialPhotoId)
    }

    private var currentPhoto: RecapPhoto? {
        photos.first { $0.id == currentPhotoId } ?? photos.first
    }

    private var currentCaption: String {
        photoCaption(currentPhotoId).wrappedValue
    }

    var body: some View {
        ZStack {
                // 1. Full screen media viewer
                fullScreenPhotoView
                    .blur(radius: isEditing ? 6 : 0)
                    .overlay(isEditing ? Color.black.opacity(0.4) : Color.clear)
                    .onTapGesture {
                        if !blogIsEditMode && !isEditing {
                            withAnimation {
                                isOverlayHidden.toggle()
                            }
                        }
                    }

                // 2. Bottom overlay
            VStack {
                Spacer()
                if !isEditing {
                    BottomInfoOverlay(
                        placeTitle: placeTitle,
                        dateTimeText: dateTimeTextForCurrentPhoto,
                        isEditing: $isEditing,
                        captionText: $editedCaptionText,
                        placeholder: "Leave a story for this photo...",
                        blogIsEditMode: blogIsEditMode,
                        onCommitCaption: { commitCaption() }
                    )
                }
                if !blogIsEditMode {
                    if photos.count > 1 {
                        PlacePhotoThumbnailStrip(
                            photos: photos,
                            currentPhotoId: currentPhotoId,
                            onSelectPhoto: { currentPhotoId = $0 }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    } else if let single = photos.first {
                        RecapPhotoThumbnail(photo: single, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 160, height: 160))
                            .frame(width: 56, height: 56)
                            .clipped()
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            )
                            .padding(.bottom, 24)
                    }
                }
            }
            .opacity(isOverlayHidden ? 0 : 1)

            // 3. Top bar + bottom-right action stack (drawn on top so never covered when modal is small)
            ZStack(alignment: .top) {
                // Drag Handle
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                
                VStack(spacing: 0) {
                    HStack {
                        if blogIsEditMode {
                            // In Blog Edit Mode: No "Back" button, no "Edit" button.
                            // User dismisses by dragging down or tapping background.
                             Color.clear.frame(width: 44, height: 44)
                        } else if isEditing && !blogIsEditMode {
                             Button("Cancel") {
                                 // Revert changes
                                 editedCaptionText = captionWhenEditingStarted
                                 editedPlaceTitle = titleWhenEditingStarted
                                 isEditing = false
                             }
                             .font(.subheadline)
                             .fontWeight(.semibold)
                             .foregroundColor(.white)
                             .padding(.horizontal, 12)
                             .padding(.vertical, 6)
                             .background(Color.black.opacity(0.35))
                             .clipShape(Capsule())
                        } else if !isEditing {
                            Button(action: {
                                captionWhenEditingStarted = currentCaption
                                titleWhenEditingStarted = placeTitle
                                editedCaptionText = currentCaption
                                editedPlaceTitle = placeTitle
                                isEditing = true
                            }) {
                                Text("Edit")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.35))
                                    .clipShape(Capsule())
                            }
                            .shadow(color: .black.opacity(0.4), radius: 2)
                        }

                        Spacer()
                        
                        if isEditing {
                            Button("Done") {
                                commitCaption()
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .clipShape(Capsule())
                        } else {
                            // Close Button (X) - Always visible when not editing caption
                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black.opacity(0.35))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    Spacer()
                }
                // Right side actions - only visible when NOT editing AND NOT in blog edit mode
                if !isEditing && !blogIsEditMode {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            RightActionStack(
                                onSparkles: { /* AI assist */ },
                                onNavigate: { openNavigation() },
                                onLink: { openGoogleSearch() }
                            )
                            .padding(.trailing, 16)
                            .padding(.bottom, photos.count > 1 ? 100 : 24)
                        }
                    }
                }
            }
            .allowsHitTesting(true)
            .opacity(isOverlayHidden ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .statusBar(hidden: false)
        // Editing panel anchors just above the keyboard via safeAreaInset
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditing {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Place Name", text: $editedPlaceTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)

                    HStack(alignment: .top, spacing: 8) {
                        TextField("Leave a story for this photo...", text: $editedCaptionText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .foregroundColor(.white)
                            .lineLimit(2...6)
                            .padding(12)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)
                        if let generate = onGenerateCaption, let photo = currentPhoto {
                            Button {
                                isGeneratingCaption = true
                                Task {
                                    let text = await generate(photo, editedPlaceTitle, placeSubtitle)
                                    await MainActor.run {
                                        editedCaptionText = text
                                        photoCaption(currentPhotoId).wrappedValue = text
                                        isGeneratingCaption = false
                                        onAICaptionApplied?(currentPhotoId)
                                    }
                                }
                            } label: {
                                if isGeneratingCaption {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                        .frame(width: 20, height: 20)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                        .font(.body)
                                        .foregroundColor(.white)
                                }
                            }
                            .disabled(isGeneratingCaption)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.9))
            }
        }
        .onAppear {
            editedCaptionText = currentCaption
            editedPlaceTitle = placeTitle
            if blogIsEditMode {
                // captionWhenEditingStarted = currentCaption
                // titleWhenEditingStarted = placeTitle
                // isEditing = true
            }
        }
        .onChange(of: currentPhotoId) { _, _ in
            editedCaptionText = currentCaption
            if isEditing {
                captionWhenEditingStarted = currentCaption
                // Place Title is same for all photos in this modal
            }
        }
        .onChange(of: editedCaptionText) { _, newValue in
            guard isEditing else { return }
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                photoCaption(currentPhotoId).wrappedValue = newValue
                if !isGeneratingCaption {
                    onPhotoCaptionManuallyEdited?(currentPhotoId)
                }
            }
        }
    }

    private var fullScreenPhotoView: some View {
        TabView(selection: $currentPhotoId) {
            ForEach(photos) { photo in
                photoFullScreenImage(photo)
                    .tag(photo.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }

    private func photoFullScreenImage(_ photo: RecapPhoto) -> some View {
        RecapPhotoThumbnail(photo: photo, cornerRadius: 0, showIcon: false, targetSize: CGSize(width: 1200, height: 1200))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(contentMode: .fill)
            .clipped()
    }

    private var dateTimeTextForCurrentPhoto: String {
        currentPhoto.map { Self.dateTimeFormatter.string(from: $0.timestamp) } ?? ""
    }

    private func openNavigation() {
        guard let location = currentPhoto?.location else { return }
        let lat = location.latitude
        let lon = location.longitude
        // Open Apple Maps navigation to this coordinate
        let urlString = "http://maps.apple.com/?daddr=\(lat),\(lon)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func openGoogleSearch() {
        // Query: "Place Name, City Name"
        let query = [placeTitle, placeSubtitle].compactMap { $0 }.joined(separator: ", ")
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }

    private func commitCaption() {
        let text = editedCaptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        photoCaption(currentPhotoId).wrappedValue = text
        let titleText = editedPlaceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !titleText.isEmpty {
            placeTitle = titleText
        }
        isEditing = false
    }
}

// MARK: - Top overlay controls

struct TopControlsRow: View {
    var onEdit: () -> Void

    var body: some View {
        HStack {
            Button(action: onEdit) {
                Text("Edit")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
            }
            .shadow(color: .black.opacity(0.4), radius: 2)

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Right side vertical action stack

struct RightActionStack: View {
    var onSparkles: () -> Void
    var onNavigate: () -> Void
    var onLink: () -> Void

    private let spacing: CGFloat = 20

    var body: some View {
        VStack(spacing: spacing) {
            Button(action: onSparkles) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.blue.opacity(0.85))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: onNavigate) {
                // Navigation icon replacing Share, and removed Heart/Comment/Bookmark
                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.green)
            }
            .buttonStyle(.plain)

            Button(action: onLink) {
                Image(systemName: "link")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.85))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .shadow(color: .black.opacity(0.3), radius: 2)
    }
}

// MARK: - Bottom overlay content block

struct BottomInfoOverlay: View {
    let placeTitle: String
    let dateTimeText: String
    @Binding var isEditing: Bool
    @Binding var captionText: String
    let placeholder: String
    var blogIsEditMode: Bool = false
    var onCommitCaption: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(placeTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 2)

            if !dateTimeText.isEmpty {
                Text(dateTimeText)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 1)
            }

            if isEditing {
                TextField(placeholder, text: $captionText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(2...6)
                    .padding(10)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(8)
                    .onSubmit { onCommitCaption() }
                Button("Done") {
                    onCommitCaption()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            } else if !captionText.isEmpty {
                Text(captionText)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            } else if blogIsEditMode {
                // Do not show the "leave a story..." placeholder in edit/restore mode
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Make the whole background tap-to-edit in blog edit mode
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.35), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
        )
        .onTapGesture {
            if blogIsEditMode && !isEditing {
                // Tapping to edit caption disabled in edit/restore mode for now
            }
        }
    }
}

// MARK: - Bottom thumbnail strip (all photos when multiple; tap to navigate)

struct PlacePhotoThumbnailStrip: View {
    let photos: [RecapPhoto]
    let currentPhotoId: UUID
    var onSelectPhoto: (UUID) -> Void

    /// AI rank badges (1–3) computed from quality scores.
    private var aiRanks: [UUID: Int] { photos.aiRanksByPhotoId() }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photos) { photo in
                    Button {
                        onSelectPhoto(photo.id)
                    } label: {
                        ZStack(alignment: .topLeading) {
                            RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 300, height: 300))
                                .frame(width: 56, height: 56)
                                .clipped()
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(photo.id == currentPhotoId ? Color.white : Color.white.opacity(0.35), lineWidth: photo.id == currentPhotoId ? 2 : 1)
                                )
                            // AI rank badge on thumbnails
                            if let rank = aiRanks[photo.id] {
                                HStack(spacing: 1) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                                    Text("\(rank)")
                                        .font(.system(size: 7, weight: .heavy))
                                        .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                                }
                                .padding(.horizontal, 3)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.72))
                                .cornerRadius(3)
                                .padding(3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 64)
    }
}

// MARK: - Bottom thumbnail preview (single thumbnail; used elsewhere if needed)

struct ThumbnailPreview: View {
    let photos: [RecapPhoto]
    let currentPhotoId: UUID
    var onSelectPhoto: (UUID) -> Void
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if let current = photos.first(where: { $0.id == currentPhotoId }) {
                RecapPhotoThumbnail(photo: current, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 160, height: 160))
                    .frame(width: 56, height: 56)
                    .clipped()
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
    }
}
