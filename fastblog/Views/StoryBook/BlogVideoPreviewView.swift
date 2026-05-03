// fastblog/Views/StoryBook/BlogVideoPreviewView.swift
import SwiftUI
import AVKit

/// Full-screen video preview: generates the cinematic video on appear, plays it in a loop,
/// and offers a top-right Export/Share button. Presented as a ZStack overlay (zIndex 128).
struct BlogVideoPreviewView: View {

    let draft: RecapBlogDetail
    let onDismiss: () -> Void

    @State private var player: AVPlayer? = nil
    @State private var videoURL: URL? = nil
    @State private var isGenerating = true
    @State private var progress: Double = 0
    @State private var errorMessage: String? = nil
    @State private var generateTask: Task<Void, Never>? = nil
    @State private var playerLoopObserver: NSObjectProtocol? = nil
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isGenerating {
                LoadingScanView(
                    message: "Building your video…",
                    isOverlay: false,
                    progress: progress,
                    onCancel: { cancelAndDismiss() },
                    progressStepLabelOverride: { p in
                        if p < 0.10 { return "Building journey…" }
                        if p < 0.50 { return "Loading places & photos…" }
                        if p < 0.72 { return "Rendering map frames…" }
                        if p < 0.86 { return "Writing video…" }
                        return "Adding music…"
                    },
                    useCenteredLayout: true,
                    showsTopTrailingActions: false
                )
                .transition(.opacity)

                // Close button visible even during generation
                overlayChrome(showExport: false)

            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .transition(.opacity)

                overlayChrome(showExport: true)

            } else if let msg = errorMessage {
                errorState(msg)
                overlayChrome(showExport: false)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = videoURL {
                ShareSheet(items: [url])
            }
        }
        .onAppear { startGeneration() }
        .onDisappear { tearDown() }
    }

    // MARK: - Chrome

    private func overlayChrome(showExport: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                closeButton
                Spacer()
                if showExport {
                    exportButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, chromeTopPadding())
            Spacer(minLength: 0)
        }
        .allowsHitTesting(true)
    }

    private var closeButton: some View {
        Button { cancelAndDismiss() } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.50))
                    .frame(width: 36, height: 36)
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
    }

    private var exportButton: some View {
        Button { showShareSheet = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                Text("Export")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.18))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error state

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.65))
            Text("Couldn't build video")
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Try Again") { startGeneration() }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.18))
                .clipShape(Capsule())
        }
    }

    // MARK: - Generation

    @MainActor
    private func startGeneration() {
        generateTask?.cancel()
        isGenerating = true
        progress = 0.02
        errorMessage = nil

        generateTask = Task { @MainActor in
            defer { generateTask = nil }
            do {
                let opts = BlogVideoExportOptions() // cinematic defaults
                let url = try await BlogVideoExportService.exportVideo(
                    pages: [],
                    draft: draft,
                    options: opts,
                    progressHandler: { p in progress = 0.02 + p * 0.98 }
                )
                guard !Task.isCancelled else { return }

                videoURL = url
                let avPlayer = AVPlayer(url: url)
                avPlayer.actionAtItemEnd = .none
                playerLoopObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: avPlayer.currentItem,
                    queue: .main
                ) { _ in
                    avPlayer.seek(to: .zero)
                    avPlayer.play()
                }
                player = avPlayer
                withAnimation(.easeInOut(duration: 0.35)) { isGenerating = false }
                avPlayer.play()
            } catch is CancellationError {
                // dismissed mid-generation — no-op
            } catch {
                isGenerating = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelAndDismiss() {
        tearDown()
        onDismiss()
    }

    private func tearDown() {
        generateTask?.cancel()
        generateTask = nil
        if let obs = playerLoopObserver {
            NotificationCenter.default.removeObserver(obs)
            playerLoopObserver = nil
        }
        player?.pause()
        player = nil
    }

    // MARK: - Layout helpers

    private func chromeTopPadding() -> CGFloat {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
            return 49
        }
        let top = window.safeAreaInsets.top
        return (top > 0 ? top : 47) + 2
    }
}
