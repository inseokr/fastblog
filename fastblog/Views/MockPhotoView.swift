//
//  MockPhotoView.swift
//  Capper
//

import SwiftUI

/// Static day cover for the day card: last selected photo for that day, or last photo of the day when none selected.
struct DayCoverPreviewView: View {
    let photos: [MockPhoto]

    /// Last selected photo if any; otherwise first photo of the day.
    private var previewPhoto: MockPhoto? {
        photos.filter(\.isSelected).last ?? photos.first
    }

    var body: some View {
        Group {
            if let photo = previewPhoto {
                if let id = photo.localIdentifier {
                    AssetPhotoView(assetIdentifier: id, cornerRadius: 0, targetSize: CGSize(width: 600, height: 600))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MockPhotoView(seed: photo.id.hashValue, cornerRadius: 0, showIcon: false, iconName: photo.imageName)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                MockPhotoView(seed: 0, cornerRadius: 0, showIcon: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipped()
    }
}

/// Loads and displays a photo library asset by identifier. Shows placeholder until loaded.
/// Resets and reloads when assetIdentifier changes so the correct photo always displays (avoids stale image when view is reused).
struct AssetPhotoView: View {
    let assetIdentifier: String
    var cornerRadius: CGFloat = 8
    var targetSize: CGSize = CGSize(width: 400, height: 400)

    @State private var image: UIImage?
    @State private var displayedIdentifier: String?

    var body: some View {
        Group {
            if let image = image, displayedIdentifier == assetIdentifier {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                MockPhotoView(seed: assetIdentifier.hashValue, cornerRadius: cornerRadius, showIcon: true)
            }
        }
        .clipped()
        .cornerRadius(cornerRadius)
        .task(id: assetIdentifier) {
            image = nil
            displayedIdentifier = nil
            let loader = ImageLoader()
            let loadedImage = await loader.loadThumbnail(assetIdentifier: assetIdentifier, targetSize: targetSize)
            if !Task.isCancelled {
                image = loadedImage
                displayedIdentifier = assetIdentifier
            }
        }
    }
}

/// Renders a mockup photo placeholder (varied gradient by seed) instead of an empty SF Symbol state.
struct MockPhotoView: View {
    var seed: Int
    var cornerRadius: CGFloat = 8
    var showIcon: Bool = false
    var iconName: String = "photo"

    var body: some View {
        ZStack {
            mockPhotoGradient
            if showIcon {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .clipped()
        .cornerRadius(cornerRadius)
    }

    private var mockPhotoGradient: some View {
        let palette = gradientPalette(for: seed)
        return LinearGradient(
            colors: palette.colors,
            startPoint: palette.startPoint,
            endPoint: palette.endPoint
        )
    }

    private func gradientPalette(for seed: Int) -> (colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        let palettes: [(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint)] = [
            // Sunset / sky
            ([Color(red: 0.95, green: 0.6, blue: 0.4), Color(red: 0.6, green: 0.35, blue: 0.6)], .top, .bottom),
            // Ocean / water
            ([Color(red: 0.2, green: 0.5, blue: 0.75), Color(red: 0.1, green: 0.3, blue: 0.5)], .topLeading, .bottomTrailing),
            // Forest / green
            ([Color(red: 0.2, green: 0.55, blue: 0.35), Color(red: 0.1, green: 0.35, blue: 0.2)], .top, .bottom),
            // Mountain / cool
            ([Color(red: 0.4, green: 0.5, blue: 0.65), Color(red: 0.25, green: 0.35, blue: 0.5)], .topLeading, .bottom),
            // Golden hour
            ([Color(red: 0.9, green: 0.7, blue: 0.4), Color(red: 0.7, green: 0.45, blue: 0.35)], .top, .bottomTrailing),
            // Aurora / night
            ([Color(red: 0.1, green: 0.4, blue: 0.35), Color(red: 0.15, green: 0.25, blue: 0.4)], .topLeading, .bottomTrailing),
            // Beach / warm
            ([Color(red: 0.85, green: 0.75, blue: 0.6), Color(red: 0.6, green: 0.5, blue: 0.45)], .top, .bottom),
            // City / dusk
            ([Color(red: 0.35, green: 0.3, blue: 0.45), Color(red: 0.2, green: 0.18, blue: 0.28)], .top, .bottom),
            // Meadow
            ([Color(red: 0.45, green: 0.65, blue: 0.4), Color(red: 0.3, green: 0.5, blue: 0.35)], .topLeading, .bottom),
            // Lake / blue
            ([Color(red: 0.35, green: 0.55, blue: 0.7), Color(red: 0.2, green: 0.4, blue: 0.55)], .top, .bottom),
        ]
        let index = abs(seed) % palettes.count
        return palettes[index]
    }
}

/// Convenience for MockPhoto: shows real image when localIdentifier is set, otherwise gradient placeholder.
struct MockPhotoThumbnail: View {
    let photo: MockPhoto
    var cornerRadius: CGFloat = 8
    var showIcon: Bool = false

    var body: some View {
        Group {
            if let id = photo.localIdentifier {
                AssetPhotoView(assetIdentifier: id, cornerRadius: cornerRadius)
            } else {
                MockPhotoView(
                    seed: photo.id.hashValue,
                    cornerRadius: cornerRadius,
                    showIcon: showIcon,
                    iconName: photo.imageName
                )
            }
        }
    }
}

/// Convenience for RecapPhoto. Shows real image when localIdentifier is set.
struct RecapPhotoThumbnail: View {
    let photo: RecapPhoto
    var cornerRadius: CGFloat = 8
    var showIcon: Bool = false
    var targetSize: CGSize = CGSize(width: 400, height: 400)

    var body: some View {
        Group {
            if let id = photo.localIdentifier {
                AssetPhotoView(assetIdentifier: id, cornerRadius: cornerRadius, targetSize: targetSize)
            } else {
                MockPhotoView(
                    seed: photo.id.hashValue,
                    cornerRadius: cornerRadius,
                    showIcon: showIcon,
                    iconName: photo.imageName
                )
            }
        }
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
        ForEach(0..<6, id: \.self) { i in
            MockPhotoView(seed: i, showIcon: true)
                .aspectRatio(1, contentMode: .fill)
        }
    }
    .padding()
}
