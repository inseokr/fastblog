//
//  PlaceStopRowView.swift
//  Capper
//

import SwiftUI

private let captionToolbarBlue = Color(red: 0, green: 122/255, blue: 1)

struct PlaceStopRowView: View {
    let day: RecapBlogDay
    let stop: PlaceStop
    let stopNumber: Int
    var isEditMode: Bool = true
    @Binding var placeNote: String
    var photoCaption: (UUID) -> Binding<String>
    var onDelete: () -> Void
    var onKebab: (() -> Void)?
    var onManagePhotos: () -> Void
    var onRemovePhoto: ((UUID) -> Void)?
    var onPhotoTapped: ((RecapPhoto) -> Void)?
    var onCaptionFocus: (() -> Void)?

    @FocusState private var focusedPlaceNote: Bool
    @FocusState private var focusedPhotoId: UUID?

    /// 12-hour visit time from earliest photo timestamp. Formatter: "h:mm a" (e.g. 3:42 PM).
    private static let visitTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var visitTimeText: String? {
        stop.photos.map(\.timestamp).min().map { Self.visitTimeFormatter.string(from: $0) }
    }

    /// Photo size in strip (doubled from prior 120 so one photo is prominent and next peeks on the right).
    private let thumbnailSize: CGFloat = 240

    /// True when the focused field (place note or photo caption) has text, so Clear should be red.
    private var clearButtonIsRed: Bool {
        if focusedPlaceNote { return !placeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let id = focusedPhotoId { return !photoCaption(id).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: badge + title, subtitle, time (no note here)
            HStack(alignment: .top, spacing: 12) {
                stopBadge
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stop.placeTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        if isEditMode {
                            Button(action: onDelete) {
                                Image(systemName: "trash")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Button { onKebab?() } label: {
                                Image(systemName: "ellipsis")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    if let subtitle = stop.placeSubtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let time = visitTimeText {
                        Text(time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Row 2: place caption aligned left with blue circle (same leading as badge)
            HStack(alignment: .top, spacing: 0) {
                TextEditor(text: $placeNote)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 44)
                    .foregroundColor(.white)
                    .background(Color(white: 0.08))
                    .cornerRadius(8)
                    .overlay(alignment: .topLeading) {
                        if placeNote.isEmpty {
                            Text("Leave a note for your future self")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .allowsHitTesting(false)
                        }
                    }
                    .focused($focusedPlaceNote)
                    .onChange(of: focusedPlaceNote) { _, isFocused in
                        if isFocused { onCaptionFocus?() }
                    }
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.bottom, 12)

            // Photo strip: large thumbnails; one full photo visible + peek of next so users know they can scroll
            if !stop.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(stop.photos) { photo in
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
                                                .font(.system(size: 22))
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, Color.black.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(6)
                                    }
                                }
                                TextField("Leave a story for this photo", text: photoCaption(photo.id))
                                    .textFieldStyle(.plain)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(width: thumbnailSize)
                                    .focused($focusedPhotoId, equals: photo.id)
                                    .onChange(of: focusedPhotoId) { _, _ in
                                        if focusedPhotoId != nil { onCaptionFocus?() }
                                    }
                            }
                            .frame(width: thumbnailSize)
                        }
                        if isEditMode {
                            // Manage Photos card at end of scroll
                            Button(action: onManagePhotos) {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
                                    .frame(width: thumbnailSize, height: thumbnailSize)
                                    .overlay {
                                        Text("Manage\nPhotos")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                            .multilineTextAlignment(.center)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                }
                .frame(height: thumbnailSize + 28)
                .padding(.bottom, 12)
            }

            timelineLine
        }
        .background(Color(white: 0.12))
        .cornerRadius(12)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                HStack(spacing: 12) {
                    Button("Cancel") {
                        focusedPlaceNote = false
                        focusedPhotoId = nil
                    }
                    .foregroundColor(.white)
                    Spacer()
                    Button("Clear") {
                        if focusedPlaceNote {
                            placeNote = ""
                        } else if let id = focusedPhotoId {
                            photoCaption(id).wrappedValue = ""
                        }
                    }
                    .foregroundColor(clearButtonIsRed ? .red : .white)
                    Spacer()
                    Button("Save") {
                        focusedPlaceNote = false
                        focusedPhotoId = nil
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(captionToolbarBlue)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial.opacity(0.75))
            }
        }
    }

    private var stopBadge: some View {
        Text("\(stopNumber)")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(Color.blue)
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
            photoCaption: { _ in .constant("") },
            onDelete: {},
            onKebab: nil,
            onManagePhotos: {},
            onRemovePhoto: nil,
            onPhotoTapped: nil,
            onCaptionFocus: nil
        )
        .padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
