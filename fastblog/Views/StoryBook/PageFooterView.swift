// fastblog/Views/StoryBook/PageFooterView.swift
import SwiftUI
import UIKit

/// Subtle book page position (1-based index / total pages) used across story mode.
struct StoryBookPageNumberLabel: View {
    let bookPageIndex: Int
    let bookPageCount: Int
    let fontTheme: FontTheme
    var surface: Surface = .content(.white)

    enum Surface {
        case content(BlogColor)
        case photoOverlay
    }

    var body: some View {
        Text("\(bookPageIndex) / \(bookPageCount)")
            .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 11)))
            .modifier(PageNumberForeground(surface: surface))
    }
}

private struct PageNumberForeground: ViewModifier {
    let surface: StoryBookPageNumberLabel.Surface

    func body(content: Content) -> some View {
        switch surface {
        case .content(let bg):
            content.foregroundColor(bg == .black ? Color.white.opacity(0.6) : Color.gray)
        case .photoOverlay:
            content
                .foregroundColor(Color.white.opacity(0.78))
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        }
    }
}

struct PageFooterView: View {
    let isLastPageOfTrip: Bool
    let isLastPageOfDay: Bool
    let nextDayName: String?
    let showNextDayLabel: Bool
    let blogColor: BlogColor
    let fontTheme: FontTheme
    let bookPageIndex: Int
    let bookPageCount: Int

    var body: some View {
        ZStack {
            HStack {
                if let appIcon = UIImage(named: "AppIcon") {
                    Image(uiImage: appIcon)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                if isLastPageOfTrip {
                    Text("The End")
                        .italic()
                        .font(Font(StoryFontHelper.uiItalicFont(for: fontTheme, size: 12)))
                        .foregroundColor(blogColor == .black ? .white : .black)
                } else if showNextDayLabel, isLastPageOfDay, let nextDay = nextDayName {
                    Text("\(nextDay) →")
                        .font(Font(StoryFontHelper.uiFont(for: fontTheme, size: 12, weight: .medium)))
                        .foregroundColor(blogColor == .black ? .white : .black)
                } else {
                    EmptyView()
                }
            }
            StoryBookPageNumberLabel(
                bookPageIndex: bookPageIndex,
                bookPageCount: bookPageCount,
                fontTheme: fontTheme,
                surface: .content(blogColor)
            )
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
    }
}
