//
//  AppCaptureDetailView.swift
//  fastblog
//
//  Full-screen paging viewer for in-app camera captures.
//  Supports caption editing and photo deletion.
//

import SwiftUI

struct AppCaptureDetailView: View {
    @Binding var items: [AppCaptureItem]
    let initialId: UUID
    var onDelete: (UUID) -> Void
    var onCaptionSaved: (UUID, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int = 0
    @State private var showControls = true
    @State private var isEditingCaption = false
    @State private var captionDraft = ""
    @State private var showDeleteConfirm = false
    @State private var isGeneratingCaption = false
    @FocusState private var captionFocused: Bool

    // MARK: - Vibe
    @StateObject private var vibePlayer = VibePlayer()
    /// Global toggle: once enabled, auto-plays Vibe as the user pages through photos.
    @State private var isVibeEnabled: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if items.isEmpty {
                emptyView
            } else {
                photoPageView
                if showControls && !isEditingCaption {
                    topBar
                    bottomOverlay
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditingCaption {
                captionEditor
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let idx = items.firstIndex(where: { $0.id == initialId }) {
                currentIndex = idx
            }
            captionDraft = currentItem?.caption ?? ""
        }
        .onDisappear {
            vibePlayer.stop()
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteCurrentPhoto() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the photo from your device.")
        }
    }

    // MARK: - Current item helper

    private var currentItem: AppCaptureItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    // MARK: - Photo pager

    private var photoPageView: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                PhotoPageCell(item: item)
                    .tag(index)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .onChange(of: currentIndex) { _, newIdx in
            if items.indices.contains(newIdx) {
                captionDraft = items[newIdx].caption ?? ""
            }
            vibePlayer.stop()
            if isVibeEnabled, let url = items[safe: newIdx]?.localVibeURL {
                vibePlayer.play(url: url)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack {
            ZStack {
                // Left: close button
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Spacer()

                    // Right: Vibe toggle (when available) + kebab/ellipsis menu
                    HStack(spacing: 10) {
                        if currentItem?.localVibeURL != nil {
                            let isPlaying = isVibeEnabled && vibePlayer.isPlaying
                            Button {
                                isVibeEnabled.toggle()
                                if isVibeEnabled, let url = currentItem?.localVibeURL {
                                    vibePlayer.play(url: url)
                                } else {
                                    vibePlayer.stop()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(
                                            isPlaying
                                                ? LinearGradient(
                                                    colors: [.cyan, .green],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                                : LinearGradient(
                                                    colors: [Color.white.opacity(0.08)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                        )
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(isPlaying ? .white : Color.white.opacity(0.35))
                                }
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            isPlaying
                                                ? LinearGradient(
                                                    colors: [.cyan, .green],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                                : LinearGradient(
                                                    colors: [Color.white.opacity(0.15)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                            lineWidth: isPlaying ? 2 : 1
                                        )
                                )
                                .shadow(color: isPlaying ? .cyan.opacity(0.55) : .clear, radius: isPlaying ? 10 : 0)
                            }
                            .accessibilityLabel(
                                isPlaying ? "Vibe playing" : (isVibeEnabled ? "Vibe enabled" : "Vibe disabled")
                            )
                            // Slight extra clarity: show a tiny badge when actually playing.
                            .overlay(alignment: .bottomTrailing) {
                                if isPlaying {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 7, height: 7)
                                        .overlay(Circle().stroke(Color.cyan.opacity(0.9), lineWidth: 1))
                                        .offset(x: -2, y: -2)
                                }
                            }
                        }

                        Menu {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete Photo", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                }

                // Center: photo index (e.g. 1/2)
                if items.count > 1 {
                    Text("\(currentIndex + 1) / \(items.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Bottom overlay (timestamp + caption preview)

    private var bottomOverlay: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                if let item = currentItem {
                    // Timestamp row with magic wand
                    HStack(alignment: .center) {
                        Text(Self.dateFormatter.string(from: item.timestamp))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        Spacer()

                        if let cap = item.caption, !cap.isEmpty, let cgImage = item.image?.cgImage {
                            Button {
                                isGeneratingCaption = true
                                Task {
                                    let text = await StoryCaptionService.shared.generateCaptionForImage(cgImage: cgImage)
                                    await MainActor.run {
                                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                        let newCaption: String? = trimmed.isEmpty ? nil : trimmed
                                        try? AppCapturePhotoService.shared.updateCaption(captureId: item.id, caption: newCaption)
                                        items[currentIndex].caption = newCaption
                                        onCaptionSaved(item.id, newCaption)
                                        isGeneratingCaption = false
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
                                        .font(.caption)
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.8, green: 0.5, blue: 1.0),
                                                    Color(red: 0.4, green: 0.7, blue: 1.0)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                            }
                            .disabled(isGeneratingCaption)
                        }
                    }

                    // Caption (tap to edit)
                    if let cap = item.caption, !cap.isEmpty {
                        Text(cap)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .lineLimit(3)
                            .onTapGesture {
                                captionDraft = cap
                                withAnimation { isEditingCaption = true }
                                DispatchQueue.main.async { captionFocused = true }
                            }
                    } else {
                        Button {
                            captionDraft = ""
                            withAnimation { isEditingCaption = true }
                            DispatchQueue.main.async { captionFocused = true }
                        } label: {
                            Label("Leave a story for this photo...", systemImage: "text.bubble")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Caption editor (anchored above keyboard via safeAreaInset)
    // Styling aligned with PlacePhotoModalView: gradient panel, TextField, AI wand.

    private var captionEditor: some View {
        VStack(spacing: 0) {
            // Toolbar: Cancel / Done
            HStack {
                Button("Cancel") {
                    withAnimation { isEditingCaption = false }
                    captionFocused = false
                    captionDraft = currentItem?.caption ?? ""
                }
                .foregroundColor(.white.opacity(0.7))

                Spacer()

                Text("Caption")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                Spacer()

                Button("Done") {
                    saveCaption()
                }
                .foregroundColor(.blue)
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.12))

            Divider().background(Color.white.opacity(0.15))

            // Content: title/date + caption field + AI wand (same pattern as PlacePhotoModalView)
            VStack(alignment: .leading, spacing: 12) {
                if let item = currentItem {
                    Text(Self.dateFormatter.string(from: item.timestamp))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 4)

                    TextField("Leave a story for this photo...", text: $captionDraft, axis: .vertical)
                        .focused($captionFocused)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundColor(.white)
                        .lineLimit(2...6)
                        .padding(12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.8),
                        Color.black.opacity(0.4),
                        Color.clear
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
        .background(Color(white: 0.12))
    }

    // MARK: - Actions

    private func saveCaption() {
        guard let item = currentItem else { return }
        let trimmed = captionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let newCaption: String? = trimmed.isEmpty ? nil : trimmed
        try? AppCapturePhotoService.shared.updateCaption(captureId: item.id, caption: newCaption)
        items[currentIndex].caption = newCaption
        onCaptionSaved(item.id, newCaption)
        withAnimation { isEditingCaption = false }
        captionFocused = false
    }

    private func deleteCurrentPhoto() {
        guard let item = currentItem else { return }
        vibePlayer.stop()
        AppCapturePhotoService.shared.deleteCapture(captureId: item.id)
        onDelete(item.id)

        // Navigate to adjacent item or dismiss if last
        if items.count == 1 {
            dismiss()
        } else {
            let newIndex = min(currentIndex, items.count - 2)
            items.remove(at: currentIndex)
            currentIndex = newIndex
            captionDraft = items[safe: currentIndex]?.caption ?? ""
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("No photos")
                .foregroundColor(.white.opacity(0.5))
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .padding(16)
            }
        }
    }
}

// MARK: - Individual page cell (zoomable image)

private struct PhotoPageCell: View {
    let item: AppCaptureItem

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let image = item.image {
                    imageContent(geo: geo, image: image)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func imageContent(geo: GeometryProxy, image: UIImage) -> some View {
        let base = Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(scale * magnifyBy)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .updating($magnifyBy) { value, state, _ in state = value }
                    .onEnded { value in
                        scale = max(1, scale * value)
                        if scale <= 1 { offset = .zero }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) {
                    if scale > 1 { scale = 1; offset = .zero }
                    else { scale = 2.5 }
                }
            }
        if scale > 1 {
            base.gesture(
                DragGesture()
                    .onChanged { value in
                        offset = value.translation
                    }
                    .onEnded { _ in }
            )
        } else {
            base
        }
    }
}

// MARK: - Safe subscript helper

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
