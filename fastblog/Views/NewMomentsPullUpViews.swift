// fastblog/Views/NewMomentsPullUpViews.swift
// On-the-go trip style pull-up (not used on recap). Kept for reuse in other flows.
import SwiftUI

// MARK: - On-the-go sheet slide-up wrapper

/// Wraps the on-the-go modal content so it slides up from the bottom on appear (offset animation).
/// Sheet height is limited so content above (e.g. map or blog) remains partially visible.
struct OnTheGoSheetWithSlideUp<Content: View>: View {
    let sheetContent: Content
    @State private var offsetY: CGFloat = 600
    private let sheetHeightFraction: CGFloat = 0.72

    init(@ViewBuilder sheetContent: () -> Content) {
        self.sheetContent = sheetContent()
    }

    var body: some View {
        GeometryReader { geo in
            let sheetHeight = max(400, geo.size.height * sheetHeightFraction)
            sheetContent
                .frame(maxWidth: .infinity)
                .frame(height: sheetHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: offsetY)
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    offsetY = 0
                }
            }
        }
        .transition(.asymmetric(
            insertion: .identity,
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
}

// MARK: - Newly Scanned Photos Sheet (on-the-go pull-up)

private let newMomentsCardBg = Color(uiColor: .tertiarySystemGroupedBackground)

struct NewlyScannedPhotosSheet: View {
    let photos: [MockPhoto]
    let matchedTrip: TripDraft?
    let matchedBlog: CreatedRecapBlog?
    /// When set, replaces the default "Add to \"Title\"" label on the primary blog button.
    var primaryAddToBlogTitle: String? = nil
    var onGoToTrip: (() -> Void)?
    var onGoToBlog: (() -> Void)?
    var onDismiss: () -> Void

    private var previewPhotos: [MockPhoto] { Array(photos.prefix(4)) }

    private var coverAssetId: String? {
        matchedBlog?.coverAssetIdentifier
            ?? matchedTrip?.coverAssetIdentifier
            ?? photos.first?.localIdentifier
    }

    private var entityTitle: String {
        matchedBlog?.title ?? matchedTrip?.title ?? "Your Trip"
    }

    private var entityDateRange: String {
        matchedBlog?.tripDateRangeText
            ?? matchedTrip?.tripDateRangeDisplayText
            ?? ""
    }

    private var entityDuration: String {
        if let blog = matchedBlog {
            let d = blog.tripDurationDays
            return "\(d) day\(d == 1 ? "" : "s")"
        }
        if let trip = matchedTrip {
            let d = trip.days.count
            return "\(d) day\(d == 1 ? "" : "s")"
        }
        return ""
    }

    private var newPhotoLabel: String {
        let n = photos.count
        let momentText = "\(n) moment\(n == 1 ? "" : "s")"
        if let blog = matchedBlog {
            return "\(momentText) – Add to \"\(blog.title)\""
        }
        return "\(momentText) found"
    }

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    blogCard
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)

                    photoStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)

                actionButtons
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
            .frame(maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 20, style: .continuous))
            .offset(y: max(dragOffset, 0))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        if value.translation.height > 120 {
                            onDismiss()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var blogCard: some View {
        let themeName = matchedBlog?.coverImageName ?? matchedTrip?.coverTheme ?? "blue"
        VStack(alignment: .leading, spacing: 12) {
            TripCoverImage(theme: themeName, coverAssetIdentifier: coverAssetId)
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text(newPhotoLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(10)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text(entityDateRange)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                }

                Text(entityTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack {
                    if !entityDuration.isEmpty {
                        Text(entityDuration)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var photoStrip: some View {
        if !previewPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("NEW MOMENTS FOUND")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))

                HStack(spacing: 6) {
                    ForEach(previewPhotos) { photo in
                        Group {
                            if let id = photo.localIdentifier {
                                AssetPhotoView(assetIdentifier: id, cornerRadius: 0, targetSize: CGSize(width: 160, height: 160))
                            } else {
                                MockPhotoView(seed: photo.id.hashValue, cornerRadius: 0, showIcon: false, iconName: photo.imageName)
                            }
                        }
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if photos.count > 4 {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(newMomentsCardBg)
                                .frame(width: 70, height: 70)
                            Text("+\(photos.count - 4)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                }
            }
            .contentShape(Rectangle())
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if let blog = matchedBlog {
                Button(action: { onGoToBlog?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                        Text(primaryAddToBlogTitle ?? "Add to \"\(blog.title)\"")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }
            } else if matchedTrip != nil {
                Button(action: { onGoToTrip?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "map.fill")
                        Text("View Trip")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }
            }

            Button(action: onDismiss) {
                Text("Later")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 13))
            }
        }
    }
}
