// fastblog/Views/StoryBook/StoryBookView.swift
import SwiftUI
import Foundation
import UIKit

struct StoryBookView: View {
    let detail: RecapBlogDetail
    @StateObject private var viewModel = StoryBookViewModel()
    @State private var selectedPageIndex: Int = 0
    @State private var showShareSheet = false
    @State private var pdfExportURL: URL?
    @State private var pdfShareURL: URL?
    @State private var isExportingPDF = false
    @State private var showExportErrorAlert = false
    @State private var exportErrorMessage: String?
    /// When false, the bottom Cancel/Share buttons are hidden; tap anywhere on the story content to toggle.
    @State private var showStoryChrome = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            switch viewModel.state {
            case .loading:
                ExportingPDFView(title: "Preparing your storybook...", subtitle: detail.title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .ready(let pages):
                ZStack {
                    ZStack {
                        TabView(selection: $selectedPageIndex) {
                            ForEach(0..<pages.count, id: \.self) { i in
                                StoryPageView(
                                    page: pages[i],
                                    bookPageIndex: i + 1,
                                    bookPageCount: pages.count,
                                    showNextDayLabel: true,
                                    photoShapeOptions: PDFPhotoShapeOptions(),
                                    blogColor: .white,
                                    fontTheme: .classic,
                                    layoutMode: .normal,
                                    onNavigateToBookPage: { bookPage in
                                        let idx = bookPage - 1
                                        if pages.indices.contains(idx) {
                                            selectedPageIndex = idx
                                        }
                                    }
                                )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .tag(i)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .ignoresSafeArea()
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                showStoryChrome.toggle()
                            }
                        )

                        // Invisible click/tap zones on the left/right edges for prev/next navigation.
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

            // Bottom overlay controls (cancel on bottom-left, share on bottom-right).
            HStack(alignment: .bottom) {
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

                Spacer(minLength: 0)

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
                .accessibilityLabel("Share")
                .disabled(isExportingPDF)
            }
            .padding(.bottom, 26)
            .padding(.horizontal, 16)
            .opacity(showStoryChrome ? 1 : 0)
            .allowsHitTesting(showStoryChrome)
            .animation(.easeInOut(duration: 0.2), value: showStoryChrome)

            if isExportingPDF {
                ExportingPDFView(
                    title: "Opening sharing options…",
                    secondaryTitle: "Please wait a moment",
                    secondaryTitleDelay: 2,
                    subtitle: detail.title
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isContentReady)
        .task {
            viewModel.build(from: detail)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfShareURL ?? pdfExportURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Export Failed", isPresented: $showExportErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Unknown error")
        }
    }

    private func exportStoryModePDFAndShare() async {
        guard !isExportingPDF else { return }
        isExportingPDF = true
        defer { isExportingPDF = false }

        do {
            let result = try await StoryModePDFExportService.exportStoryModePDF(from: detail, options: PDFExportOptions())
            pdfShareURL = result.shareURL
            showShareSheet = true
        } catch is CancellationError {
            // Task cancelled (e.g. view dismissed); defer clears overlay.
        } catch {
            exportErrorMessage = "PDF export failed: \(error.localizedDescription)"
            showExportErrorAlert = true
        }
    }

    private var isContentReady: Bool {
        if case .ready = viewModel.state { return true }
        return false
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
            VStack {
                HStack {
                    Spacer(minLength: 0)
                    storyDaysMenu(entries: entries, pages: pages)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
