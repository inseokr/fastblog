// fastblog/Views/StoryBook/PageFooterView.swift
import SwiftUI

struct PageFooterView: View {
    let isLastPageOfTrip: Bool
    let isLastPageOfDay: Bool
    let nextDayName: String?

    var body: some View {
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
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            } else if isLastPageOfDay, let nextDay = nextDayName {
                Text("\(nextDay) →")
                    .font(.system(size: 12, weight: .medium))
            } else {
                Text("Next Page →")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
    }
}
