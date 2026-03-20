// fastblog/Views/StoryBook/PhotoContinuationBlockView.swift
import SwiftUI

struct PhotoContinuationBlockView: View {
    let placeName: String
    let photos: [PhotoContent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("More from \(placeName)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<photos.count, id: \.self) { i in
                    PhotoCardView(photo: photos[i])
                }
            }
        }
        .padding(.vertical, 4)
    }
}
