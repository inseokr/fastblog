//
//  PlaceStopRowView.swift
//  Capper
//

import SwiftUI



struct PlaceStopRowView: View {
    let day: RecapBlogDay
    let stop: PlaceStop
    let stopNumber: Int
    var isEditMode: Bool = true
    var badgeColor: Color = .blue
    @Binding var placeNote: String
    var photoCaption: (UUID) -> Binding<String>
    var onDelete: () -> Void
    var onKebab: (() -> Void)?
    var onManagePhotos: () -> Void
    var onRemovePhoto: ((UUID) -> Void)?
    var onPhotoTapped: ((RecapPhoto) -> Void)?
    var onCaptionFocus: (() -> Void)?
    var onNavigate: (() -> Void)?
    var onEditName: (() -> Void)?

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
                                Text(stop.placeTitle)
                                    .font(.title3) // Slightly larger place title for better tap target? Or keep headline? Keeping consistent but tappable.
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .underline(false) // No underline, just text
                            }
                            .buttonStyle(.plain)
                        }
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
            if isEditMode {
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
            } else if !placeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    Text(placeNote)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }

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
                                                .font(.system(size: 30))
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, Color.black.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(6)
                                    }
                                }
                                    if isEditMode {
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
                                    } else if !photoCaption(photo.id).wrappedValue.isEmpty {
                                        Text(photoCaption(photo.id).wrappedValue)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.9))
                                            .lineLimit(2)
                                            .frame(width: thumbnailSize, alignment: .leading)
                                    }
                                }
                                .frame(width: thumbnailSize)
                            }
                            // Manage Photos card at end of scroll
                            if isEditMode && stop.photos.count > 1 {
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
                            }
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 16)

                .frame(height: thumbnailSize + 28)
                .padding(.bottom, 12)
            }

            timelineLine
        }
        .background(Color(white: 0.12))
        .cornerRadius(12)
        .toolbar {
            if focusedPlaceNote || focusedPhotoId != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    KeyboardCaptionToolbar(
                        onCancel: {
                            focusedPlaceNote = false
                            focusedPhotoId = nil
                        },
                        onClear: {
                            if focusedPlaceNote {
                                placeNote = ""
                            } else if let id = focusedPhotoId {
                                photoCaption(id).wrappedValue = ""
                            }
                        },
                        onDone: {
                            focusedPlaceNote = false
                            focusedPhotoId = nil
                        },
                        isClearRed: clearButtonIsRed,
                        doneButtonTitle: "Done"
                    )
                }
            }
        }
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
