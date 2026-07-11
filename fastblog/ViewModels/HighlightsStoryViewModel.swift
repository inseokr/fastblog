//
//  HighlightsStoryViewModel.swift
//  Capper
//

import CoreImage
import Foundation
import SwiftUI
import UIKit

struct BlogHighlightsResolvedPalette {
    let tint: Color
    let accent: Color
    let deep: Color
    let uiTint: UIColor

    static let fallback = BlogHighlightsResolvedPalette(
        tint: Color(red: 0.20, green: 0.48, blue: 0.86),
        accent: Color(red: 0.96, green: 0.62, blue: 0.16),
        deep: Color(red: 5 / 255, green: 10 / 255, blue: 48 / 255),
        uiTint: UIColor(red: 0.20, green: 0.48, blue: 0.86, alpha: 1)
    )
}

extension BlogHighlightsTint {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

@MainActor
final class HighlightsStoryViewModel: ObservableObject {
    @Published private(set) var pageIndex = 0
    @Published private(set) var beatIndex = 0
    @Published private(set) var pageProgress: Double = 0
    @Published private(set) var isPaused = false
    @Published private(set) var palette = BlogHighlightsResolvedPalette.fallback
    @Published private(set) var paletteVersion = 0
    @Published var selectionHaptic = 0
    @Published var impactHaptic = 0
    @Published var confettiBurstToken = 0

    let content: BlogHighlightsContent

    private var playbackTask: Task<Void, Never>?
    private var pageElapsed: TimeInterval = 0
    private var firedNumberLandingIndices: Set<Int> = []
    private var didReportEndCard = false
    private let onReachedEnd: () -> Void

    private static var paletteCache: [String: BlogHighlightsResolvedPalette] = [:]
    private static let ciContext = CIContext()

    init(content: BlogHighlightsContent, onReachedEnd: @escaping () -> Void) {
        self.content = content
        self.onReachedEnd = onReachedEnd
    }

    var pages: [BlogHighlightsContent.Page] {
        content.pages
    }

    var currentPage: BlogHighlightsContent.Page {
        guard pages.indices.contains(pageIndex) else { return .endCard }
        return pages[pageIndex]
    }

    var currentBeatCount: Int {
        currentPage.beatCount
    }

    func start() {
        guard !pages.isEmpty else { return }
        move(toPage: min(pageIndex, pages.count - 1), beat: beatIndex, animated: false)
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
    }

    func onTapForward() {
        guard !pages.isEmpty else { return }
        if currentPage.beatCount > 1, beatIndex < currentPage.beatCount - 1 {
            move(toPage: pageIndex, beat: beatIndex + 1, animated: true)
            return
        }
        guard pageIndex < pages.count - 1 else { return }
        move(toPage: pageIndex + 1, beat: 0, animated: true)
    }

    func onTapBack() {
        guard !pages.isEmpty else { return }
        if currentPage.beatCount > 1, beatIndex > 0 {
            move(toPage: pageIndex, beat: beatIndex - 1, animated: true)
            return
        }
        guard pageIndex > 0 else {
            move(toPage: 0, beat: 0, animated: true)
            return
        }
        let previousPage = pages[pageIndex - 1]
        let lastBeat = max(0, previousPage.beatCount - 1)
        move(toPage: pageIndex - 1, beat: lastBeat, animated: true)
    }

    func onHoldChanged(_ holding: Bool) {
        guard isPaused != holding else { return }
        isPaused = holding
    }

    func progress(for index: Int) -> Double {
        guard index < pageIndex else { return 1 }
        guard index == pageIndex else { return 0 }
        return pageProgress
    }

    func momentForCurrentBeat(_ moments: [BlogHighlightsContent.Moment]) -> BlogHighlightsContent.Moment? {
        guard moments.indices.contains(beatIndex) else { return moments.last }
        return moments[beatIndex]
    }

    private func move(toPage newPageIndex: Int, beat newBeatIndex: Int, animated: Bool) {
        guard pages.indices.contains(newPageIndex) else { return }
        let page = pages[newPageIndex]
        playbackTask?.cancel()
        playbackTask = nil

        pageIndex = newPageIndex
        beatIndex = min(max(0, newBeatIndex), page.beatCount - 1)
        pageElapsed = elapsedTime(for: page, beat: beatIndex)
        pageProgress = progress(for: page, elapsed: pageElapsed)
        firedNumberLandingIndices = []

        if animated {
            selectionHaptic += 1
        }
        triggerEntryHaptic(for: page)
        refreshPalette(for: page, beat: beatIndex)
        reportEndIfNeeded(page)
        restartPlaybackIfNeeded()
    }

    private func restartPlaybackIfNeeded() {
        guard !currentPage.isEndCard, currentPage.duration > 0 else { return }
        playbackTask = Task { @MainActor in
            let tick: TimeInterval = 0.05
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                guard !isPaused else { continue }

                pageElapsed += tick
                pageProgress = progress(for: currentPage, elapsed: pageElapsed)
                updateBeatAndHaptics()

                if pageElapsed >= currentPage.duration {
                    guard pageIndex < pages.count - 1 else { return }
                    move(toPage: pageIndex + 1, beat: 0, animated: true)
                    return
                }
            }
        }
    }

    private func elapsedTime(for page: BlogHighlightsContent.Page, beat: Int) -> TimeInterval {
        guard page.beatCount > 1 else { return 0 }
        let beatDuration = page.duration / TimeInterval(page.beatCount)
        return min(page.duration, TimeInterval(beat) * beatDuration)
    }

    private func progress(for page: BlogHighlightsContent.Page, elapsed: TimeInterval) -> Double {
        guard page.duration > 0 else { return 1 }
        return min(1, max(0, elapsed / page.duration))
    }

    private func updateBeatAndHaptics() {
        let page = currentPage
        if page.beatCount > 1 {
            let beatDuration = page.duration / TimeInterval(page.beatCount)
            let nextBeat = min(page.beatCount - 1, Int(pageElapsed / beatDuration))
            if nextBeat != beatIndex {
                beatIndex = nextBeat
                impactHaptic += 1
                refreshPalette(for: page, beat: beatIndex)
            }
        }

        if case .numbers = page {
            let thresholds: [TimeInterval] = [1.2, 2.7, 4.1]
            for (index, threshold) in thresholds.enumerated() where pageElapsed >= threshold && !firedNumberLandingIndices.contains(index) {
                firedNumberLandingIndices.insert(index)
                selectionHaptic += 1
            }
        }
    }

    private func triggerEntryHaptic(for page: BlogHighlightsContent.Page) {
        switch page {
        case .bestMoments:
            impactHaptic += 1
        case .travelDNA:
            impactHaptic += 1
            confettiBurstToken += 1
        default:
            break
        }
    }

    private func reportEndIfNeeded(_ page: BlogHighlightsContent.Page) {
        guard page.isEndCard else {
            didReportEndCard = false
            return
        }
        guard !didReportEndCard else { return }
        didReportEndCard = true
        onReachedEnd()
    }

    private func refreshPalette(for page: BlogHighlightsContent.Page, beat: Int) {
        let fallback: BlogHighlightsResolvedPalette
        switch page {
        case .secondaryStat(let stat):
            fallback = Self.palette(from: stat.tint)
        case .travelDNA(let dna):
            fallback = Self.palette(from: dna.tint)
        default:
            fallback = BlogHighlightsResolvedPalette.fallback
        }
        palette = fallback
        paletteVersion += 1

        guard let assetIdentifier = assetIdentifier(for: page, beat: beat) else { return }
        if let cached = Self.paletteCache[assetIdentifier] {
            palette = cached
            paletteVersion += 1
            return
        }

        Task { @MainActor in
            guard let image = await ImageLoader.shared.loadThumbnail(
                assetIdentifier: assetIdentifier,
                targetSize: CGSize(width: 80, height: 80)
            ) else { return }
            let extracted = Self.palette(from: image)
            Self.paletteCache[assetIdentifier] = extracted
            guard assetIdentifier == self.assetIdentifier(for: self.currentPage, beat: self.beatIndex) else { return }
            self.palette = extracted
            self.paletteVersion += 1
        }
    }

    private func assetIdentifier(for page: BlogHighlightsContent.Page, beat: Int) -> String? {
        switch page {
        case .title, .numbers, .shootingPeak, .secondaryStat, .travelDNA:
            return content.coverAssetIdentifier
        case .bestMoments(let moments):
            guard moments.indices.contains(beat) else { return moments.last?.assetIdentifier }
            return moments[beat].assetIdentifier
        case .endCard:
            return content.coverAssetIdentifier ?? content.rankedMoments.compactMap(\.assetIdentifier).first
        }
    }

    private static func palette(from tint: BlogHighlightsTint) -> BlogHighlightsResolvedPalette {
        BlogHighlightsResolvedPalette(
            tint: tint.swiftUIColor,
            accent: Color(red: min(1, tint.red + 0.22), green: min(1, tint.green + 0.18), blue: min(1, tint.blue + 0.12)),
            deep: Color(red: 5 / 255, green: 10 / 255, blue: 48 / 255),
            uiTint: tint.uiColor
        )
    }

    private static func palette(from image: UIImage) -> BlogHighlightsResolvedPalette {
        guard let color = averageColor(from: image) else { return .fallback }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        let navy = (r: CGFloat(5 / 255.0), g: CGFloat(10 / 255.0), b: CGFloat(48 / 255.0))
        let deepR = Double(r * 0.38 + navy.r * 0.62)
        let deepG = Double(g * 0.38 + navy.g * 0.62)
        let deepB = Double(b * 0.38 + navy.b * 0.62)
        let accentR = min(1, Double(r * 0.75 + 0.18))
        let accentG = min(1, Double(g * 0.75 + 0.18))
        let accentB = min(1, Double(b * 0.75 + 0.18))
        let tint = Color(red: accentR, green: accentG, blue: accentB)
        return BlogHighlightsResolvedPalette(
            tint: tint,
            accent: Color(red: min(1, accentR + 0.14), green: min(1, accentG + 0.10), blue: min(1, accentB + 0.08)),
            deep: Color(red: deepR, green: deepG, blue: deepB),
            uiTint: UIColor(red: CGFloat(accentR), green: CGFloat(accentG), blue: CGFloat(accentB), alpha: 1)
        )
    }

    private static func averageColor(from image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }
}
