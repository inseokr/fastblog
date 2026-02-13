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
    var photoCaption: (UUID) -> Binding<String>
    var onDismiss: () -> Void

    @State private var currentPhotoId: UUID
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
        photoCaption: @escaping (UUID) -> Binding<String>,
        onDismiss: @escaping () -> Void
    ) {
        self._placeTitle = placeTitle
        self.placeSubtitle = placeSubtitle
        self.photos = photos
        self.initialPhotoId = initialPhotoId
        self.photoCaption = photoCaption
        self.onDismiss = onDismiss
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

                // 2. Bottom overlay (or top when editing so caption stays visible above keyboard)
            VStack {
                if isEditing {
                    // Caption input at top for clearance above keyboard
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Place Name", text: $editedPlaceTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)

                        TextField("Leave a story for this photo...", text: $editedCaptionText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .foregroundColor(.white)
                            .lineLimit(2...6)
                            .padding(12)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                Spacer()
                if !isEditing {
                    BottomInfoOverlay(
                        placeTitle: placeTitle,
                        dateTimeText: dateTimeTextForCurrentPhoto,
                        isEditing: $isEditing,
                        captionText: $editedCaptionText,
                        placeholder: "Leave a story for this photo...",
                        onCommitCaption: { commitCaption() }
                    )
                }
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

            // 3. Top bar + bottom-right action stack (drawn on top so never covered when modal is small)
            ZStack(alignment: .topLeading) {
                Color.clear
                VStack(spacing: 0) {
                    HStack {
                        if isEditing {
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
                        } else {
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
                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
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
                // Right side actions - only visible when NOT editing
                if !isEditing {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .statusBar(hidden: false)
        .onAppear {
            editedCaptionText = currentCaption
            editedPlaceTitle = placeTitle
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
            } else {
                Button {
                    isEditing = true
                } label: {
                    Group {
                        if captionText.isEmpty {
                            Text(placeholder)
                                .foregroundColor(.white.opacity(0.7))
                        } else {
                            Text(captionText)
                                .foregroundColor(.white)
                                .lineLimit(2)
                        }
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.35), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }
}

// MARK: - Bottom thumbnail strip (all photos when multiple; tap to navigate)

struct PlacePhotoThumbnailStrip: View {
    let photos: [RecapPhoto]
    let currentPhotoId: UUID
    var onSelectPhoto: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photos) { photo in
                    Button {
                        onSelectPhoto(photo.id)
                    } label: {
                        RecapPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false, targetSize: CGSize(width: 300, height: 300))
                            .frame(width: 56, height: 56)
                            .clipped()
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(photo.id == currentPhotoId ? Color.white : Color.white.opacity(0.35), lineWidth: photo.id == currentPhotoId ? 2 : 1)
                            )
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
