//
//  HighlightsStoryView.swift
//  Capper
//

import SwiftUI

struct HighlightsStoryView: View {
    let content: BlogHighlightsContent
    var onDismiss: () -> Void
    var onCompleted: () -> Void
    var onOpenBlog: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: HighlightsStoryViewModel
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var isRenderingShareCard = false

    init(
        content: BlogHighlightsContent,
        onDismiss: @escaping () -> Void,
        onCompleted: @escaping () -> Void,
        onOpenBlog: @escaping () -> Void
    ) {
        self.content = content
        self.onDismiss = onDismiss
        self.onCompleted = onCompleted
        self.onOpenBlog = onOpenBlog
        _viewModel = StateObject(
            wrappedValue: HighlightsStoryViewModel(
                content: content,
                onReachedEnd: onCompleted
            )
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HighlightsStoryPageRenderer(
                    content: content,
                    page: viewModel.currentPage,
                    beatIndex: viewModel.beatIndex,
                    progress: viewModel.pageProgress,
                    palette: viewModel.palette,
                    reduceMotion: reduceMotion,
                    onShare: shareCurrentPage,
                    onOpenBlog: openBlog
                )
                .id(viewModel.currentPage.id)
                .transition(.opacity)
                .animation(.easeInOut(duration: reduceMotion ? 0.18 : 0.34), value: viewModel.currentPage.id)
                .animation(.easeInOut(duration: 0.35), value: viewModel.paletteVersion)

                HighlightsParticleField(
                    palette: viewModel.palette,
                    burstToken: viewModel.confettiBurstToken
                )
                .ignoresSafeArea()

                tapZones
                    .zIndex(1)

                VStack(spacing: 0) {
                    progressBar
                        .padding(.top, geo.safeAreaInsets.top + 8)
                        .padding(.horizontal, 10)

                    HStack {
                        Spacer()
                        Button {
                            dismissStory()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 38, height: 38)
                                .background(Color.black.opacity(0.28), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    Spacer()

                    if !viewModel.currentPage.isEndCard {
                        HStack {
                            Spacer()
                            Button {
                                shareCurrentPage()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.34))
                                        .frame(width: 48, height: 48)
                                    if isRenderingShareCard {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isRenderingShareCard)
                            .accessibilityLabel("Share Highlight")
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 16)
                    }
                }
                .zIndex(2)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .simultaneousGesture(swipeDownGesture)
            .onLongPressGesture(
                minimumDuration: 0.18,
                maximumDistance: 30,
                pressing: { holding in
                    viewModel.onHoldChanged(holding)
                },
                perform: {}
            )
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showShareSheet, onDismiss: {
            shareURL = nil
            if !viewModel.currentPage.isEndCard {
                viewModel.onHoldChanged(false)
            }
        }) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectionHaptic)
        .sensoryFeedback(.impact(weight: .heavy), trigger: viewModel.impactHaptic)
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(viewModel.pages.enumerated()), id: \.element.id) { index, _ in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.26))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * viewModel.progress(for: index))
                    }
                }
                .frame(height: 3)
            }
        }
        .frame(height: 3)
    }

    private var tapZones: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geo.size.width / 2)
                    .onTapGesture {
                        viewModel.onTapBack()
                    }
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geo.size.width / 2)
                    .allowsHitTesting(!viewModel.currentPage.isEndCard)
                    .onTapGesture {
                        viewModel.onTapForward()
                    }
            }
        }
        .ignoresSafeArea()
    }

    private var swipeDownGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let vertical = value.translation.height
                guard vertical > 80, abs(vertical) > abs(value.translation.width) else { return }
                dismissStory()
            }
    }

    private func dismissStory() {
        viewModel.stop()
        onDismiss()
    }

    private func openBlog() {
        viewModel.stop()
        onOpenBlog()
    }

    private func shareCurrentPage() {
        guard !isRenderingShareCard else { return }
        viewModel.onHoldChanged(true)
        isRenderingShareCard = true
        let page = viewModel.currentPage
        let beatIndex = viewModel.beatIndex
        let palette = viewModel.palette
        Task { @MainActor in
            let url = await HighlightsShareCard.render(
                content: content,
                page: page,
                beatIndex: beatIndex,
                palette: palette
            )
            isRenderingShareCard = false
            guard let url else {
                if !viewModel.currentPage.isEndCard {
                    viewModel.onHoldChanged(false)
                }
                return
            }
            shareURL = url
            showShareSheet = true
        }
    }
}
