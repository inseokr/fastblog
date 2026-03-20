// fastblog/Views/StoryBook/PhotoCardView.swift
import SwiftUI
import UIKit

struct PhotoCardView: View {
    let photo: PhotoContent
    let photoShape: PhotoShape
    let blogColor: BlogColor
    let fontTheme: FontTheme
    /// Width driven by the caller (half-page for 2 photos, full width for 1 photo)
    let width: CGFloat
    /// Overrides the image frame height for story-mode layout packing.
    /// When nil, we fall back to the natural 3:4 portrait aspect ratio from `width`.
    let imageHeight: CGFloat?

    @State private var measuredCaptionHeight: CGFloat = 0

    private var height: CGFloat { imageHeight ?? (width * (4 / 3)) }   // 3:4 portrait

    private var shortCaptionHeight: CGFloat {
        guard photo.captionIsLong == false,
              let caption = photo.caption,
              !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return 0 }

        let font = StoryFontHelper.uiFont(for: fontTheme, size: 10)
        let maxLines: CGFloat = 2
        let maxCaptionHeight = font.lineHeight * maxLines

        let rect = caption.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )

        return min(max(0, rect.height), maxCaptionHeight)
    }

    private struct CaptionHeightPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                Image(uiImage: photo.image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()

                if photo.captionIsLong, let caption = photo.caption {
                    let fallbackCaptionRegionHeight = height * 0.45
                    let maxGlowHeight = height * 0.5
                    let minGlowHeight: CGFloat = 44

                    // Measure caption height so the glow behind it grows/shrinks with the caption.
                    let captionContentHeight = measuredCaptionHeight > 0 ? measuredCaptionHeight : fallbackCaptionRegionHeight
                    let captionRegionHeight = min(maxGlowHeight, max(minGlowHeight, captionContentHeight + 24))

                    ZStack(alignment: .bottom) {
                        // Soft black glow/gradient behind the caption text.
                        PhotoClipShape(shape: photoShape)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .black.opacity(0.0),
                                        .black.opacity(0.75)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: width, height: captionRegionHeight)
                            .blur(radius: 10)
                            .allowsHitTesting(false)

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Text(caption)
                                .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 11)))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 10)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: CaptionHeightPreferenceKey.self,
                                            value: geo.size.height
                                        )
                                    }
                                )
                        }
                    }
                    // Don't vertically constrain the text so the measured caption height stays accurate.
                    .frame(width: width, height: height)
                    .onPreferenceChange(CaptionHeightPreferenceKey.self) { measuredCaptionHeight = $0 }
                }
            }
            .frame(width: width, height: height)
            .clipShape(PhotoClipShape(shape: photoShape))

            if !photo.captionIsLong, let caption = photo.caption {
                Text(caption)
                    .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 10)))
                    .foregroundColor(blogColor == .black ? Color.white : Color.black)
                    .lineLimit(2)
                    .frame(width: width, height: shortCaptionHeight, alignment: .topLeading)
                    .clipped()
            }
        }
    }

    /// Clips photos to match the `PDFExportOptions` photo style.
    ///
    /// Important: this only changes the clipping path; it does not change any layout sizing.
    private struct PhotoClipShape: Shape {
        let shape: PhotoShape

        func path(in rect: CGRect) -> Path {
            switch shape {
            case .rounded:
                return RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect)
            case .squircle:
                let r = min(rect.width, rect.height) * 0.25
                return RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect)
            case .circle:
                return Ellipse().path(in: rect)
            case .rectangle:
                return Rectangle().path(in: rect)
            case .arch:
                let w = rect.width
                let h = rect.height
                let r = w / 2
                var p = Path()
                p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h / 2))
                p.addArc(
                    center: CGPoint(x: rect.minX + w / 2, y: rect.minY + h / 2),
                    radius: r,
                    startAngle: .degrees(180),
                    endAngle: .degrees(0),
                    clockwise: true
                )
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                p.closeSubpath()
                return p
            case .diamond:
                let w = rect.width
                let h = rect.height
                var p = Path()
                p.move(to: CGPoint(x: rect.minX + w / 2, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h / 2))
                p.addLine(to: CGPoint(x: rect.minX + w / 2, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h / 2))
                p.closeSubpath()
                return p
            case .hexagon:
                let w = rect.width
                let h = rect.height
                let cx = rect.minX + w / 2
                let cy = rect.minY + h / 2
                let r = min(w, h) / 2
                var p = Path()
                for i in 0..<6 {
                    let angle = (-Double.pi / 2) + (Double(i) * Double.pi / 3)
                    let x = cx + CGFloat(cos(angle)) * r
                    let y = cy + CGFloat(sin(angle)) * r
                    if i == 0 {
                        p.move(to: CGPoint(x: x, y: y))
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                p.closeSubpath()
                return p
            }
        }
    }
}
