// fastblog/Views/StoryBook/PageFooterView.swift
import SwiftUI

struct PageFooterView: View {
    let isLastPageOfTrip: Bool
    let isLastPageOfDay: Bool
    let nextDayName: String?

    var body: some View {
        HStack {
            Spacer()
            if isLastPageOfTrip {
                Text("The End")
                    .italic()
                    .font(.system(size: 12))
                    .foregroundColor(Color.black)
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
    }
}
