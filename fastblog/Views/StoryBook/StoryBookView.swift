// fastblog/Views/StoryBook/StoryBookView.swift
import SwiftUI

struct StoryBookView: View {
    let detail: RecapBlogDetail
    @StateObject private var viewModel = StoryBookViewModel()
    @State private var selectedPageIndex: Int = 0
    @State private var showShareSheet = false
    @State private var pdfShareURL: URL?
    @State private var isExportingPDF = false
    @State private var showExportErrorAlert = false
    @State private var exportErrorMessage: String?
    /// Same key as `RecapBlogPageView` so Story Share matches Export → PDF Options.
    @AppStorage("pdfExportOptions") private var pdfExportOptionsData: Data = (try? JSONEncoder().encode(PDFExportOptions())) ?? Data()
    /// When false, the bottom Cancel/Share buttons and Days menu are hidden; tap the story to toggle.
    @State private var showStoryChrome = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
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
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .tag(i)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                showStoryChrome.toggle()
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

                    storyDaysMenuOverlay(pages: pages)
                }
                .task(id: pages.count) {
                    selectedPageIndex = min(max(0, selectedPageIndex), max(0, pages.count - 1))
                }
                .preferredColorScheme(.light)

            case .failed:
                VStack(spacing: 20) {
                    Text("Could not load your trip.\nPlease try again.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color.black)
                    Button("Retry") {
                        viewModel.build(from: detail)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Close") { dismiss() }
                        .foregroundColor(Color.black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
            }

            if showsStoryModeBottomBar {
                storyModeBottomBar
            }

            if isExportingPDF {
                ExportingPDFView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isContentReady)
        .task {
            viewModel.build(from: detail)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfShareURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Failed", isPresented: $showExportErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Unknown error")
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

    /// During loading the bar stays visible; when ready it follows `showStoryChrome` (tap story to toggle).
    private var storyBottomBarChromeVisible: Bool {
        switch viewModel.state {
        case .loading: return true
        case .ready: return showStoryChrome
        case .failed: return false
        }
    }

    @ViewBuilder
    private var storyModeBottomBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Button {
                viewModel.cancel()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.subheadline)
                    .fontWeight(.semibold)
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
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if case .ready(let pages) = viewModel.state {
                    StoryBookPageNumberBadge(
                        currentPage: selectedPageIndex + 1,
                        totalPages: max(1, pages.count)
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)

            Button {
                Task {
                    await exportStoryModePDFAndShare()
                }
            } label: {
                if isExportingPDF {
                    Text("Exporting…")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.blue)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                        Text("Share")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("Share")
            .disabled(isExportingPDF || !isContentReady)
        }
        .padding(.bottom, 18)
        .padding(.horizontal, 16)
        .opacity(storyBottomBarChromeVisible ? 1 : 0)
        .allowsHitTesting(storyBottomBarChromeVisible)
        .animation(.easeInOut(duration: 0.2), value: storyBottomBarChromeVisible)
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
    private func storyDaysMenuOverlay(pages: [StoryPage]) -> some View {
        let entries = Self.tocEntries(from: pages)
        if entries.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geo in
                storyDaysMenu(entries: entries, pages: pages)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, geo.safeAreaInsets.top + 6)
                    .padding(.trailing, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(showStoryChrome ? 1 : 0)
            .allowsHitTesting(showStoryChrome)
            .animation(.easeInOut(duration: 0.2), value: showStoryChrome)
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
            Text("Days")
                .font(.subheadline)
                .fontWeight(.semibold)
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

/// Bottom bar page indicator (1-based index / total pages), centered between Cancel and Share.
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
