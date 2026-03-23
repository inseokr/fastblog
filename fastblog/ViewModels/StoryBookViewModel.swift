// fastblog/ViewModels/StoryBookViewModel.swift
import SwiftUI

@MainActor
final class StoryBookViewModel: ObservableObject {
    enum State {
        case loading
        case ready([StoryPage])
        case failed(Error)
    }

    @Published var state: State = .loading
    private var buildTask: Task<Void, Never>?

    func build(from detail: RecapBlogDetail, fontTheme: FontTheme) {
        buildTask?.cancel()
        state = .loading
        buildTask = Task {
            do {
                let content = try await StoryBookBuilder.build(from: detail)
                guard !Task.isCancelled else { return }
                let pages = StoryPageLayout.buildPages(from: content, fontTheme: fontTheme)
                state = .ready(pages)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error)
            }
        }
    }

    func cancel() {
        buildTask?.cancel()
    }
}
