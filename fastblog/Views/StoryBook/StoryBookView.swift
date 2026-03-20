// fastblog/Views/StoryBook/StoryBookView.swift
import SwiftUI

struct StoryBookView: View {
    let detail: RecapBlogDetail
    @StateObject private var viewModel = StoryBookViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch viewModel.state {
            case .loading:
                VStack(spacing: 16) {
                    ProgressView()
                    Text(detail.title)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)

            case .ready(let pages):
                TabView {
                    ForEach(0..<pages.count, id: \.self) { i in
                        StoryPageView(page: pages[i])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

            case .failed:
                VStack(spacing: 20) {
                    Text("Could not load your trip.\nPlease try again.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                    Button("Retry") {
                        viewModel.build(from: detail)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Close") { dismiss() }
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
            }

            // Close button — always on top
            Button {
                viewModel.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(radius: 4)
            }
            .padding(.top, 56)
            .padding(.trailing, 16)
        }
        .task {
            viewModel.build(from: detail)
        }
    }
}
