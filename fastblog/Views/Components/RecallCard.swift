//
//  RecallCard.swift
//  Capper
//

import SwiftUI
import Photos

struct RecallCard: View {
    let recall: RecallTrigger
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: iconName)
                            .foregroundColor(.blue)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recall.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text(recall.subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                // Photo mini-strip
                HStack(spacing: 8) {
                    ForEach(recall.thumbnailAssets, id: \.localIdentifier) { asset in
                        AssetPhotoView(assetIdentifier: asset.localIdentifier, cornerRadius: 8, targetSize: CGSize(width: 200, height: 200))
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(appChromeBaseRadius: 8))
                    }
                    
                    if recall.photoCount > 3 {
                        ZStack {
                            RoundedRectangle(appChromeBaseRadius: 8)
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 80, height: 80)
                            Text("+\(recall.photoCount - 3)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                
                HStack {
                    Spacer()
                    Text("View Photos")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(appChromeBaseRadius: 20)
                    .fill(Color(white: 0.1))
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            )
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 20)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var iconName: String {
        switch recall.type {
        case .onThisDay: return "calendar"
        case .seasonal: return "leaf.fill"
        case .cityRepeat: return "mappin.and.ellipse"
        case .activeMonth: return "chart.bar.fill"
        }
    }
}
