// fastblog/Views/StoryBook/StoryBookView.swift
import SwiftUI

struct StoryBookView: View {
    let detail: RecapBlogDetail
    var onDismiss: (() -> Void)? = nil
    @Binding var triggerShare: Bool
    @Binding var contentReady: Bool
    @Binding var showChrome: Bool
    @StateObject private var viewModel = StoryBookViewModel()

    init(detail: RecapBlogDetail, onDismiss: (() -> Void)? = nil, triggerShare: Binding<Bool> = .constant(false), contentReady: Binding<Bool> = .constant(false), showChrome: Binding<Bool> = .constant(true)) {
        self.detail = detail
        self.onDismiss = onDismiss
        self._triggerShare = triggerShare
        self._contentReady = contentReady
        self._showChrome = showChrome
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
                PreparingStoryBookView()

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
                    .preferredColorScheme(savedOptions.colorStyle == .black ? .dark : .light)

                    storyDaysMenuBottomTrailingOverlay(pages: pages)
                        .preferredColorScheme(.dark)
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

            // Soft top gradient for nav bar contrast — hides with chrome
            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 110)
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
        .onChange(of: triggerShare) { newValue in
            guard newValue else { return }
            triggerShare = false
            Task { await exportStoryModePDFAndShare() }
        }
        .onChange(of: isContentReady) { ready in
            contentReady = ready
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
        case .loading, .ready: return true
        case .failed: return false
        }
    }

    @ViewBuilder
    private var storyModeBottomBar: some View {
        // Page number badge — always visible while content is ready
        Group {
            if case .ready(let pages) = viewModel.state {
                StoryBookPageNumberBadge(
                    currentPage: selectedPageIndex + 1,
                    totalPages: max(1, pages.count)
                )
            }
        }
        .allowsHitTesting(false)
        .padding(.bottom, 18)
    }

    /// Concatenates TOC slices from all table-of-contents pages (order matches the book).
    private static func tocEntries(from pages: [StoryPage]) -> [TOCEntry] {
        pages.flatMap { page -> [TOCEntry] in
            if case .tableOfContents(let entries, _, _, _) = page {
                return entries
            }
            return []
        }
    }

    /// `TOCEntry.date` uses full weekday (e.g. "Saturday Jan-18"); menu rows use Mon–Sun.
    private static func dayMenuRowLabel(dayNumber: Int, dateLine: String) -> String {
        let weekdayAbbrev: [String: String] = [
            "Monday": "Mon",
            "Tuesday": "Tue",
            "Wednesday": "Wed",
            "Thursday": "Thu",
            "Friday": "Fri",
            "Saturday": "Sat",
            "Sunday": "Sun"
        ]
        let parts = dateLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let rest: String
        let dayPart: String
        if parts.count == 2, let abbr = weekdayAbbrev[String(parts[0])] {
            dayPart = abbr
            rest = String(parts[1])
        } else {
            return "Day \(dayNumber) | \(dateLine)"
        }
        return "Day \(dayNumber) | \(dayPart) \(rest)"
    }

    @ViewBuilder
    private func storyDaysMenuBottomTrailingOverlay(pages: [StoryPage]) -> some View {
        let entries = Self.tocEntries(from: pages)
        if !entries.isEmpty {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    storyDaysMenu(entries: entries, pages: pages)
                }
                .padding(.bottom, 18)
                .padding(.trailing, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func storyDaysMenu(entries: [TOCEntry], pages: [StoryPage]) -> some View {
        Menu {
            ForEach(entries, id: \.dayNumber) { entry in
                Button {
                    let idx = entry.dayStartPageNumber - 1
                    if pages.indices.contains(idx) {
                        selectedPageIndex = idx
                    }
                } label: {
                    Text(Self.dayMenuRowLabel(dayNumber: entry.dayNumber, dateLine: entry.date))
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.semibold))
                Text("Days")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.68))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.30), radius: 10, x: 0, y: 4)
        }
        .accessibilityLabel("Days")
        .accessibilityHint("Jump to a day in this story")
    }
}

/// Bottom bar page indicator (1-based index / total pages).
private struct StoryBookPageNumberBadge: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        Text("\(currentPage) / \(totalPages)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.45))
            )
    }
}
