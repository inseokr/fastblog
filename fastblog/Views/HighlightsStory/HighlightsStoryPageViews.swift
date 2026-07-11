//
//  HighlightsStoryPageViews.swift
//  Capper
//

import SwiftUI

struct HighlightsStoryPageRenderer: View {
    let content: BlogHighlightsContent
    let page: BlogHighlightsContent.Page
    let beatIndex: Int
    let progress: Double
    let palette: BlogHighlightsResolvedPalette
    let reduceMotion: Bool
    var onShare: () -> Void
    var onOpenBlog: () -> Void

    var body: some View {
        ZStack {
            storyBackground

            switch page {
            case .title:
                HighlightsTitleStoryPage(content: content, palette: palette, progress: progress, reduceMotion: reduceMotion)
            case .numbers:
                HighlightsNumbersStoryPage(stats: content.stats, palette: palette, progress: progress, reduceMotion: reduceMotion)
            case .bestMoments(let moments):
                HighlightsBestMomentsStoryPage(moments: moments, beatIndex: beatIndex, palette: palette, progress: progress, reduceMotion: reduceMotion)
            case .shootingPeak(let peak):
                HighlightsShootingPeakStoryPage(peak: peak, palette: palette, progress: progress, reduceMotion: reduceMotion)
            case .secondaryStat(let stat):
                HighlightsSecondaryStatStoryPage(stat: stat, palette: palette, progress: progress, reduceMotion: reduceMotion)
            case .travelDNA(let dna):
                HighlightsTravelDNAStoryPage(dna: dna, stats: content.stats, palette: palette, progress: progress, reduceMotion: reduceMotion)
            case .endCard:
                HighlightsEndCardStoryPage(content: content, palette: palette, onShare: onShare, onOpenBlog: onOpenBlog)
            }
        }
        .clipped()
    }

    private var storyBackground: some View {
        LinearGradient(
            colors: [
                palette.deep,
                palette.tint.opacity(0.52),
                Color.black.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct HighlightsTitleStoryPage: View {
    let content: BlogHighlightsContent
    let palette: BlogHighlightsResolvedPalette
    let progress: Double
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                HighlightsStoryPhoto(assetIdentifier: content.coverAssetIdentifier, cornerRadius: 0)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(reduceMotion ? 1 : 1 + 0.06 * progress)
                    .animation(.linear(duration: 0.08), value: progress)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.10),
                        palette.deep.opacity(0.42),
                        Color.black.opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    Label("Blog Highlights", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.16), in: Capsule())

                    Text(content.title)
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(4)
                        .minimumScaleFactor(0.72)
                        .shadow(color: .black.opacity(0.48), radius: 18, y: 8)
                        .opacity(reduceMotion ? 1 : min(1, progress * 2.3))
                        .offset(y: reduceMotion ? 0 : max(0, 28 * (1 - progress * 2.2)))

                    if !content.dateRange.isEmpty {
                        Text(content.dateRange)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white.opacity(0.82))
                            .opacity(reduceMotion ? 1 : min(1, max(0, (progress - 0.28) * 2.8)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(48, geo.safeAreaInsets.bottom + 42))
            }
        }
    }
}

private struct HighlightsNumbersStoryPage: View {
    let stats: BlogHighlightsContent.Stats
    let palette: BlogHighlightsResolvedPalette
    let progress: Double
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 90)

            Text("The numbers")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.78))

            VStack(alignment: .leading, spacing: 24) {
                numberRow(value: stats.dayCount, label: "days", active: progress >= 0.05)
                numberRow(value: stats.placeCount, label: "places", active: progress >= 0.34)
                numberRow(value: stats.photoCount, label: "photos", active: progress >= 0.62)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.bottom, 80)
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(palette.accent.opacity(0.34))
                .frame(width: 180, height: 180)
                .blur(radius: 30)
                .offset(x: 50, y: 40)
        }
    }

    private func numberRow(value: Int, label: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HighlightsCountUpNumber(target: value, active: active, reduceMotion: reduceMotion)
                .font(.system(size: 74, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label.uppercased())
                .font(.headline.weight(.bold))
                .foregroundColor(palette.accent)
        }
        .opacity(active || reduceMotion ? 1 : 0.28)
        .offset(y: (active || reduceMotion) ? 0 : 16)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.36, dampingFraction: 0.76), value: active)
    }
}

private struct HighlightsBestMomentsStoryPage: View {
    let moments: [BlogHighlightsContent.Moment]
    let beatIndex: Int
    let palette: BlogHighlightsResolvedPalette
    let progress: Double
    let reduceMotion: Bool

    var body: some View {
        let moment = moments.indices.contains(beatIndex) ? moments[beatIndex] : moments.last
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 72)

            Text("Best moments")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.78))
                .padding(.horizontal, 24)

            if let moment {
                VStack(alignment: .leading, spacing: 18) {
                    ZStack(alignment: .topLeading) {
                        HighlightsStoryPhoto(assetIdentifier: moment.assetIdentifier, cornerRadius: 8)
                            .aspectRatio(0.82, contentMode: .fit)
                            .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
                            .scaleEffect(!reduceMotion && moment.rank == 1 ? 1 + 0.025 * progress : 1)

                        Text("#\(moment.rank)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(palette.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
                            .offset(x: 16, y: 16)
                            .scaleEffect(reduceMotion ? 1 : 1.0 + min(0.14, progress * 0.14))
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(moment.placeName)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                        if let locationLine = moment.locationLine, !locationLine.isEmpty {
                            Label(locationLine, systemImage: "mappin.and.ellipse")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white.opacity(0.72))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                        Text(moment.statLine)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.78))
                    }
                }
                .padding(.horizontal, 24)
                .id(moment.id)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.78), value: beatIndex)
            }

            Spacer()
        }
    }
}

private struct HighlightsShootingPeakStoryPage: View {
    let peak: BlogHighlightsContent.ShootingPeak
    let palette: BlogHighlightsResolvedPalette
    let progress: Double
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Text("Your camera loved")
                .font(.title3.weight(.bold))
                .foregroundColor(.white.opacity(0.78))

            Text(peak.hourRange)
                .font(.system(size: 62, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: reduceMotion ? 1 : max(0.04, progress))
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text("\(peak.photoCount)")
                        .font(.system(size: 52, weight: .black, design: .monospaced))
                    Text("photos")
                        .font(.headline.weight(.bold))
                }
                .foregroundColor(.white)
            }
            .frame(width: 230, height: 230)

            Text(peak.line)
                .font(.title2.weight(.bold))
                .foregroundColor(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.bottom, 70)
    }
}

private struct HighlightsSecondaryStatStoryPage: View {
    let stat: BlogHighlightsContent.SecondaryStat
    let palette: BlogHighlightsResolvedPalette
    let progress: Double
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Text(stat.title)
                .font(.title3.weight(.bold))
                .foregroundColor(.white.opacity(0.78))

            Text(stat.value)
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.64)

            statGraphic

            Text(stat.detail)
                .font(.title2.weight(.bold))
                .foregroundColor(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.bottom, 78)
    }

    @ViewBuilder
    private var statGraphic: some View {
        switch stat.kind {
        case .travelSpan:
            HStack(spacing: 0) {
                Circle().fill(Color.white).frame(width: 15, height: 15)
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: reduceMotion ? 210 : max(20, 210 * progress), height: 6)
                Circle().fill(Color.white).frame(width: 15, height: 15)
            }
            .frame(height: 54, alignment: .center)
        case .longestStay:
            ZStack {
                Circle().stroke(Color.white.opacity(0.14), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: reduceMotion ? 0.82 : min(0.82, progress * 0.82))
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "clock.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 180, height: 180)
        case .quietGap:
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { index in
                    Circle()
                        .fill(index == 3 ? palette.accent : Color.white.opacity(0.28))
                        .frame(width: index == 3 ? 34 : 14, height: index == 3 ? 34 : 14)
                        .scaleEffect(reduceMotion ? 1 : (progress > Double(index) / 8.0 ? 1 : 0.55))
                }
            }
            .frame(height: 72)
        }
    }
}

private struct HighlightsTravelDNAStoryPage: View {
    let dna: BlogHighlightsContent.TravelDNA
    let stats: BlogHighlightsContent.Stats
    let palette: BlogHighlightsResolvedPalette
    let progress: Double
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.24))
                    .frame(width: 250, height: 250)
                    .blur(radius: 16)
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 2)
                    .frame(width: 220, height: 220)
                Image(systemName: dna.iconSystemName)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(.white)
            }
            .scaleEffect(reduceMotion ? 1 : badgeScale)

            VStack(spacing: 12) {
                Text("Travel DNA")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white.opacity(0.74))
                Text(dna.name)
                    .font(.system(size: 50, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                Text(dna.why)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                dnaChip("\(stats.dayCount) days")
                dnaChip("\(stats.placeCount) places")
                dnaChip("\(stats.photoCount) photos")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 64)
    }

    private var badgeScale: CGFloat {
        if progress < 0.35 {
            return 0.6 + 0.45 * (progress / 0.35)
        }
        if progress < 0.55 {
            return 1.05 - 0.05 * ((progress - 0.35) / 0.2)
        }
        return 1
    }

    private func dnaChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundColor(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.14), in: Capsule())
    }
}

private struct HighlightsEndCardStoryPage: View {
    let content: BlogHighlightsContent
    let palette: BlogHighlightsResolvedPalette
    var onShare: () -> Void
    var onOpenBlog: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 74)

            Text("Your trip, wrapped")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            collage
                .frame(maxWidth: 330)

            VStack(spacing: 8) {
                Text(content.travelDNA.name)
                    .font(.title2.weight(.black))
                    .foregroundColor(.white)
                Text(content.openingLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 26)

            VStack(spacing: 12) {
                Button(action: onShare) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onOpenBlog) {
                    Text("Open your blog")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)

            Spacer(minLength: 30)
        }
    }

    private var collage: some View {
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(endCardItems.enumerated()), id: \.element.id) { index, item in
                HighlightsStoryPhoto(assetIdentifier: item.assetIdentifier, cornerRadius: 8)
                    .aspectRatio(index == 0 ? 0.82 : 1, contentMode: .fit)
                    .overlay(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.black))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                            if let subtitle = item.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.78))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(
                            LinearGradient(
                                colors: [Color.black.opacity(0), Color.black.opacity(0.72)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.7), radius: 6, y: 2)
                    }
            }
        }
    }

    private var endCardItems: [HighlightsEndCardImageItem] {
        var items: [HighlightsEndCardImageItem] = []
        var usedAssetIdentifiers = Set<String>()

        for moment in content.rankedMoments {
            let identifier = moment.assetIdentifier ?? "moment-\(moment.id.uuidString)"
            if let assetIdentifier = moment.assetIdentifier {
                guard !usedAssetIdentifiers.contains(assetIdentifier) else { continue }
                usedAssetIdentifiers.insert(assetIdentifier)
            }
            items.append(
                HighlightsEndCardImageItem(
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
                HighlightsEndCardImageItem(
                    id: "cover-\(coverAssetIdentifier)",
                    assetIdentifier: coverAssetIdentifier,
                    title: content.title,
                    subtitle: content.dateRange.isEmpty ? nil : content.dateRange
                ),
                at: 0
            )
            usedAssetIdentifiers.insert(coverAssetIdentifier)
        }

        while items.count < 4 {
            let index = items.count + 1
            items.append(
                HighlightsEndCardImageItem(
                    id: "fallback-\(index)",
                    assetIdentifier: nil,
                    title: index == 1 ? content.title : "Trip highlight",
                    subtitle: content.dateRange.isEmpty ? content.openingLine : content.dateRange
                )
            )
        }

        return Array(items.prefix(4))
    }
}

private struct HighlightsEndCardImageItem: Identifiable {
    let id: String
    let assetIdentifier: String?
    let title: String
    let subtitle: String?
}

private struct HighlightsCountUpNumber: View {
    let target: Int
    let active: Bool
    let reduceMotion: Bool

    @State private var displayedValue = 0

    var body: some View {
        Text("\(displayedValue)")
            .task(id: "\(target)-\(active)-\(reduceMotion)") {
                guard active || reduceMotion else {
                    displayedValue = 0
                    return
                }
                guard !reduceMotion, target > 0 else {
                    displayedValue = target
                    return
                }
                let steps = 24
                for step in 0...steps {
                    if Task.isCancelled { return }
                    let eased = Double(step) / Double(steps)
                    displayedValue = Int((Double(target) * eased).rounded())
                    try? await Task.sleep(for: .milliseconds(24))
                }
                displayedValue = target
            }
    }
}

struct HighlightsStoryPhoto: View {
    let assetIdentifier: String?
    var cornerRadius: CGFloat

    var body: some View {
        Group {
            if let assetIdentifier {
                AssetPhotoView(assetIdentifier: assetIdentifier, cornerRadius: cornerRadius, targetSize: CGSize(width: 1200, height: 1600))
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.34, blue: 0.56),
                        Color(red: 0.06, green: 0.08, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 38, weight: .light))
                        .foregroundColor(.white.opacity(0.42))
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .clipped()
    }
}
