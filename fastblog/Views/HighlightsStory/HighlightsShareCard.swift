//
//  HighlightsShareCard.swift
//  Capper
//

import SwiftUI
import UIKit

struct HighlightsShareCard: View {
    let content: BlogHighlightsContent
    let page: BlogHighlightsContent.Page
    let beatIndex: Int
    let palette: BlogHighlightsResolvedPalette
    let images: [String: UIImage]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.deep, palette.tint.opacity(0.72), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 34) {
                cardContent
                Spacer()
                footer
            }
            .padding(.horizontal, 74)
            .padding(.top, 104)
            .padding(.bottom, 72)
        }
        .frame(width: 1080, height: 1920)
    }

    @ViewBuilder
    private var cardContent: some View {
        switch page {
        case .title:
            titleCard
        case .numbers:
            numbersCard
        case .bestMoments(let moments):
            momentCard(moment: moments.indices.contains(beatIndex) ? moments[beatIndex] : moments.last)
        case .shootingPeak(let peak):
            statCard(title: "Shooting Peak", value: peak.hourRange, detail: "\(peak.photoCount) photos captured. \(peak.line)")
        case .secondaryStat(let stat):
            statCard(title: stat.title, value: stat.value, detail: stat.detail)
        case .travelDNA(let dna):
            dnaCard(dna)
        case .endCard:
            recapCard
        }
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 38) {
            ShareCardImage(assetIdentifier: content.coverAssetIdentifier, images: images)
                .frame(width: 932, height: 1120)
                .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
            VStack(alignment: .leading, spacing: 18) {
                Text(content.title)
                    .font(.system(size: 86, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(4)
                    .minimumScaleFactor(0.68)
                if !content.dateRange.isEmpty {
                    Text(content.dateRange)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.78))
                }
            }
        }
    }

    private var numbersCard: some View {
        VStack(alignment: .leading, spacing: 58) {
            Text("The numbers")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.82))
            shareNumber(content.stats.dayCount, "days")
            shareNumber(content.stats.placeCount, "places")
            shareNumber(content.stats.photoCount, "photos")
        }
    }

    private func momentCard(moment: BlogHighlightsContent.Moment?) -> some View {
        VStack(alignment: .leading, spacing: 38) {
            if let moment {
                ZStack(alignment: .topLeading) {
                    ShareCardImage(assetIdentifier: moment.assetIdentifier, images: images)
                        .frame(width: 932, height: 1120)
                        .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                    Text("#\(moment.rank)")
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 22)
                        .background(palette.accent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(34)
                }
                Text(moment.placeName)
                    .font(.system(size: 78, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.68)
                if let locationLine = moment.locationLine, !locationLine.isEmpty {
                    Text(locationLine)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.70))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Text(moment.statLine)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.78))
            }
        }
    }

    private func statCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 42) {
            Text(title)
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            Text(value)
                .font(.system(size: 104, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(4)
                .minimumScaleFactor(0.58)
            Text(detail)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.82))
                .lineLimit(5)
            Spacer().frame(height: 120)
            ShareCardImage(assetIdentifier: content.coverAssetIdentifier, images: images)
                .frame(width: 520, height: 520)
                .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 2)
                )
        }
    }

    private func dnaCard(_ dna: BlogHighlightsContent.TravelDNA) -> some View {
        VStack(alignment: .leading, spacing: 42) {
            Text("Travel DNA")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.24))
                    .frame(width: 420, height: 420)
                Circle()
                    .stroke(Color.white.opacity(0.20), lineWidth: 4)
                    .frame(width: 348, height: 348)
                Image(systemName: dna.iconSystemName)
                    .font(.system(size: 132, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(dna.name)
                .font(.system(size: 104, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(4)
                .minimumScaleFactor(0.58)
            Text(dna.why)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.82))
                .lineLimit(5)
        }
    }

    private var recapCard: some View {
        VStack(alignment: .leading, spacing: 38) {
            Text("Your trip, wrapped")
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 22), GridItem(.flexible(), spacing: 22)], spacing: 22) {
                ForEach(Array(recapItems.enumerated()), id: \.element.id) { index, item in
                    ShareCardImage(assetIdentifier: item.assetIdentifier, images: images)
                        .frame(height: index == 0 ? 520 : 360)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .overlay(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.title)
                                    .font(.system(size: 34, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.70)
                                if let subtitle = item.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.76))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.70)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 22)
                            .background(
                                LinearGradient(
                                    colors: [Color.black.opacity(0), Color.black.opacity(0.76)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                }
            }
            Text(content.travelDNA.name)
                .font(.system(size: 58, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(content.openingLine)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.78))
                .lineLimit(4)
        }
    }

    private func shareNumber(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(value)")
                .font(.system(size: 130, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(palette.accent)
        }
    }

    private var footer: some View {
        HStack {
            Text("Bloggo")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            Text(content.dateRange)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.62))
                .lineLimit(1)
        }
    }

    private var recapItems: [HighlightsShareCardRecapItem] {
        var items: [HighlightsShareCardRecapItem] = []
        var usedAssetIdentifiers = Set<String>()

        for moment in content.rankedMoments {
            let identifier = moment.assetIdentifier ?? "moment-\(moment.id.uuidString)"
            if let assetIdentifier = moment.assetIdentifier {
                guard !usedAssetIdentifiers.contains(assetIdentifier) else { continue }
                usedAssetIdentifiers.insert(assetIdentifier)
            }
            items.append(
                HighlightsShareCardRecapItem(
                    id: identifier,
                    assetIdentifier: moment.assetIdentifier,
                    title: moment.placeName,
                    subtitle: moment.locationLine ?? moment.statLine
                )
            )
            if items.count == 4 { return items }
        }

        if let coverAssetIdentifier = content.coverAssetIdentifier,
           !usedAssetIdentifiers.contains(coverAssetIdentifier) {
            items.insert(
                HighlightsShareCardRecapItem(
                    id: "cover-\(coverAssetIdentifier)",
                    assetIdentifier: coverAssetIdentifier,
                    title: content.title,
                    subtitle: content.dateRange.isEmpty ? nil : content.dateRange
                ),
                at: 0
            )
        }

        while items.count < 4 {
            let index = items.count + 1
            items.append(
                HighlightsShareCardRecapItem(
                    id: "fallback-\(index)",
                    assetIdentifier: nil,
                    title: index == 1 ? content.title : "Trip highlight",
                    subtitle: content.dateRange.isEmpty ? content.openingLine : content.dateRange
                )
            )
        }

        return Array(items.prefix(4))
    }

    @MainActor
    static func render(
        content: BlogHighlightsContent,
        page: BlogHighlightsContent.Page,
        beatIndex: Int,
        palette: BlogHighlightsResolvedPalette
    ) async -> URL? {
        let assetIds = assetIdentifiers(content: content, page: page, beatIndex: beatIndex)
        var loadedImages: [String: UIImage] = [:]
        for id in assetIds where !id.isEmpty {
            if let image = await ImageLoader.shared.loadImage(
                assetIdentifier: id,
                targetSize: CGSize(width: 1080, height: 1920)
            ) {
                loadedImages[id] = image
            }
        }

        let view = HighlightsShareCard(
            content: content,
            page: page,
            beatIndex: beatIndex,
            palette: palette,
            images: loadedImages
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }

        let url = URL.temporaryDirectory.appendingPathComponent("Bloggo-Highlights-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    private static func assetIdentifiers(
        content: BlogHighlightsContent,
        page: BlogHighlightsContent.Page,
        beatIndex: Int
    ) -> [String] {
        var ids: [String?] = [content.coverAssetIdentifier]
        switch page {
        case .bestMoments(let moments):
            ids.append(moments.indices.contains(beatIndex) ? moments[beatIndex].assetIdentifier : moments.last?.assetIdentifier)
        case .endCard:
            ids.append(contentsOf: content.rankedMoments.map(\.assetIdentifier))
        default:
            break
        }
        return Array(Set(ids.compactMap { $0 })).prefix(8).map { $0 }
    }
}

private struct HighlightsShareCardRecapItem: Identifiable {
    let id: String
    let assetIdentifier: String?
    let title: String
    let subtitle: String?
}

private struct ShareCardImage: View {
    let assetIdentifier: String?
    let images: [String: UIImage]

    var body: some View {
        Group {
            if let assetIdentifier,
               !assetIdentifier.isEmpty,
               let image = images[assetIdentifier] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.20),
                        Color.black.opacity(0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 76, weight: .bold))
                        .foregroundColor(.white.opacity(0.42))
                }
            }
        }
        .clipped()
    }
}
