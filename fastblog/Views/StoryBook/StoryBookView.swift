// fastblog/Views/StoryBook/StoryBookView.swift
import SwiftUI
import Combine

struct StoryBookView: View {
    let detail: RecapBlogDetail
    var onDismiss: (() -> Void)? = nil
    @Binding var triggerShare: Bool
    @Binding var contentReady: Bool
    @Binding var showChrome: Bool
    /// Drives `preferredColorScheme` on the full-screen Story overlay (including status bar); must match loading / PDF light-dark.
    @Binding var statusBarColorScheme: ColorScheme
    @StateObject private var viewModel = StoryBookViewModel()

    init(
        detail: RecapBlogDetail,
        onDismiss: (() -> Void)? = nil,
        triggerShare: Binding<Bool> = .constant(false),
        contentReady: Binding<Bool> = .constant(false),
        showChrome: Binding<Bool> = .constant(true),
        statusBarColorScheme: Binding<ColorScheme> = .constant(.dark)
    ) {
        self.detail = detail
        self.onDismiss = onDismiss
        self._triggerShare = triggerShare
        self._contentReady = contentReady
        self._showChrome = showChrome
        self._statusBarColorScheme = statusBarColorScheme
    }
    @State private var selectedPageIndex: Int = 0
    @State private var showShareSheet = false
    @State private var pdfShareURL: URL?
    @State private var isExportingPDF = false
    @State private var showExportErrorAlert = false
    @State private var exportErrorMessage: String?
    @State private var showSavedToFilesBanner = false
    /// Same key as `RecapBlogPageView` so Story Share matches Export → PDF Settings.
    @AppStorage("pdfExportOptions") private var pdfExportOptionsData: Data = (try? JSONEncoder().encode(PDFExportOptions())) ?? Data()
    @Environment(\.dismiss) private var dismiss

    private var stateChangePublisher: AnyPublisher<Void, Never> {
        viewModel.$state.map { _ in () }.eraseToAnyPublisher()
    }

    private var savedOptions: PDFExportOptions {
        (try? JSONDecoder().decode(PDFExportOptions.self, from: pdfExportOptionsData)) ?? PDFExportOptions()
    }

    /// Full-screen opaque fill so the recap blog never shows through TabView paging, safe-area gaps, or transitions.
    private var storyModeBackdropColor: Color {
        switch viewModel.state {
        case .failed:
            return .white
        case .loading:
            return .black
        case .ready:
            return savedOptions.colorStyle == .black ? .black : .white
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(storyModeBackdropColor)
                .ignoresSafeArea()

            switch viewModel.state {
            case .loading:
                PreparingStoryBookView(onCancel: {
                    if let od = onDismiss { od() } else { dismiss() }
                })

            case .ready(let pages):
                ZStack {
                    ZStack {
                        TabView(selection: $selectedPageIndex) {
                            ForEach(0..<pages.count, id: \.self) { i in
                                StoryPageView(page: pages[i], onTOCDayTap: { entry in
                                    let idx = entry.dayStartPageNumber - 1
                                    if pages.indices.contains(idx) {
                                        selectedPageIndex = idx
                                    }
                                })
                                    .environment(\.storyFontTheme, savedOptions.fontTheme)
                                    .environment(\.storyBlogColor, savedOptions.colorStyle)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .tag(i)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                showChrome.toggle()
                            }
                        )

                        // Invisible tap zones on the left/right edges for prev/next navigation.
                        HStack(spacing: 0) {
                            Button {
                                if selectedPageIndex > 0 {
                                    selectedPageIndex -= 1
                                }
                            } label: {
                                Rectangle().fill(Color.clear)
                            }
                            .frame(width: 56)
                            .buttonStyle(.plain)
                            .disabled(selectedPageIndex <= 0)
                            .accessibilityLabel("Previous page")
                            .accessibilityHint("Goes to the previous page in the story book")

                            Spacer(minLength: 0)

                            Button {
                                if selectedPageIndex < pages.count - 1 {
                                    selectedPageIndex += 1
                                }
                            } label: {
                                Rectangle().fill(Color.clear)
                            }
                            .frame(width: 56)
                            .buttonStyle(.plain)
                            .disabled(selectedPageIndex >= pages.count - 1)
                            .accessibilityLabel("Next page")
                            .accessibilityHint("Goes to the next page in the story book")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                    }

                }
                .task(id: pages.count) {
                    selectedPageIndex = min(max(0, selectedPageIndex), max(0, pages.count - 1))
                }

            case .failed:
                VStack(spacing: 20) {
                    Text("Could not load your trip.\nPlease try again.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color.black)
                    Button("Retry") {
                        viewModel.build(from: detail, fontTheme: savedOptions.fontTheme)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Close") { if let od = onDismiss { od() } else { dismiss() } }
                        .foregroundColor(Color.black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
            }

            // Soft top gradient for status/title contrast (with read-mode chrome hidden). Strength follows PDF light/dark.
            LinearGradient(
                colors: savedOptions.colorStyle == .black
                    ? [Color.black.opacity(0.48), Color.black.opacity(0.12), Color.clear]
                    : [Color.black.opacity(0.14), Color.black.opacity(0.05), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: savedOptions.colorStyle == .black ? 120 : 132)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .opacity(showChrome ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: showChrome)

            if showsStoryModeBottomBar {
                storyModeBottomBar
            }

            if isExportingPDF {
                ExportingPDFView()
                    .transition(.opacity)
            }

            if showSavedToFilesBanner {
                SavedToFilesBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 16)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSavedToFilesBanner)
        .animation(.easeInOut(duration: 0.2), value: isContentReady)
        .task(id: "\(detail.id.uuidString)-\(savedOptions.fontTheme.rawValue)-\(savedOptions.colorStyle.rawValue)") {
            viewModel.build(from: detail, fontTheme: savedOptions.fontTheme)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfShareURL {
                ShareSheet(items: [url]) { completed in
                    if completed {
                        showSavedToFilesBanner = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            showSavedToFilesBanner = false
                        }
                    }
                }
            }
        }
        .alert("Export Failed", isPresented: $showExportErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Unknown error")
        }
        .onChange(of: triggerShare) { _, newValue in
            guard newValue else { return }
            triggerShare = false
            Task { await exportStoryModePDFAndShare() }
        }
        .onChange(of: isContentReady) { _, ready in
            contentReady = ready
        }
        .onAppear { syncStoryStatusBarColorScheme() }
        .onReceive(stateChangePublisher) { _ in
            syncStoryStatusBarColorScheme()
        }
        .onChange(of: pdfExportOptionsData) { _, _ in syncStoryStatusBarColorScheme() }
    }

    private func syncStoryStatusBarColorScheme() {
        switch viewModel.state {
        case .loading:
            statusBarColorScheme = .dark
        case .failed:
            statusBarColorScheme = .light
        case .ready:
            statusBarColorScheme = savedOptions.colorStyle == .black ? .dark : .light
        }
    }

    @MainActor
    private func exportStoryModePDFAndShare() async {
        guard !isExportingPDF else { return }
        guard case .ready(let pages) = viewModel.state else { return }
        isExportingPDF = true
        defer { isExportingPDF = false }

        do {
            let options = (try? JSONDecoder().decode(PDFExportOptions.self, from: pdfExportOptionsData)) ?? PDFExportOptions()
            let url = try await StoryModePDFExportService.exportStoryPDF(
                pages: pages,
                draft: detail,
                options: options
            )
            pdfShareURL = url
            showShareSheet = true
        } catch is CancellationError {
            // Dismissed or task cancelled
        } catch {
            exportErrorMessage = "PDF export failed: \(error.localizedDescription)"
            showExportErrorAlert = true
        }
    }

    private var isContentReady: Bool {
        if case .ready = viewModel.state { return true }
        return false
    }

    private var showsStoryModeBottomBar: Bool {
        switch viewModel.state {
        case .ready: return true
        case .loading, .failed: return false
        }
    }

    @ViewBuilder
    private var storyModeBottomBar: some View {
        let isDark = savedOptions.colorStyle == .black
        let fg: Color = isDark ? .white : Color(white: 0.13)
        let barBg: Color = isDark ? Color.black.opacity(0.72) : Color.white.opacity(0.94)
        let bottomPad =
            StoryRenderMetrics.windowSafeAreaInsets.bottom + StoryPageLayout.storyModeBottomBarInnerBottomPadding
        let gradH = StoryPageLayout.storyModeBottomGradientHeight
        let rowH = StoryPageLayout.storyModeBottomBarRowHeight

        VStack(spacing: 0) {
            LinearGradient(
                colors: isDark
                    ? [Color.clear, Color.black.opacity(0.72)]
                    : [Color.clear, Color.white.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: gradH)
            .allowsHitTesting(false)

            ZStack {
                HStack(spacing: 0) {
                    Button {
                        if let od = onDismiss { od() } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(fg)
                            .frame(width: 56, height: rowH)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button {
                        Task { await exportStoryModePDFAndShare() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.doc")
                                .font(.subheadline.weight(.semibold))
                            Text("Export")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(fg)
                        .frame(height: rowH)
                        .padding(.trailing, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isContentReady ? 1 : 0.35)
                    .disabled(!isContentReady)
                }

                if case .ready(let pages) = viewModel.state {
                    Text("\(selectedPageIndex + 1) / \(max(1, pages.count))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(fg.opacity(0.6))
                        .monospacedDigit()
                        .allowsHitTesting(false)
                }
            }
            .frame(height: rowH)
            .padding(.bottom, bottomPad)
            .background(barBg)
        }
    }
}
