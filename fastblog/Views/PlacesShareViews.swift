//
//  PlacesShareViews.swift
//  fastblog
//

import SwiftUI

enum PlacesShareDestination: Equatable {
  case socialCarousel
  case video
  case pdf
}

// MARK: - Share menu

struct ShareYourPlacesSheet: View {
  let onPickDestination: (PlacesShareDestination) -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 14) {
        Image(systemName: "mappin.and.ellipse")
          .font(.system(size: 28, weight: .semibold))
          .foregroundColor(.primary)
          .frame(maxWidth: .infinity)
          .padding(.top, 4)

        VStack(spacing: 6) {
          Text("Share Your Places")
            .font(.title3.weight(.semibold))
            .foregroundColor(.primary)
          Text("Choose how you want to share")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      }
      .padding(.top, 12)
      .padding(.bottom, 18)

      VStack(spacing: 14) {
        VStack(spacing: 0) {
          placesShareOptionRow(
            title: "Post to Social Media",
            subtitle: "TikTok, Instagram, and others..",
            icon: "rectangle.stack",
            iconColor: .white,
            titleColor: .white
          ) {
            onPickDestination(.socialCarousel)
          }
          Divider().padding(.leading, 52)
          placesShareOptionRow(
            title: "Stitch Reels",
            subtitle: "Video from your moments",
            icon: "video.badge.plus"
          ) {
            onPickDestination(.video)
          }
          Divider().padding(.leading, 52)
          placesShareOptionRow(
            title: "Export as PDF",
            subtitle: "Save slides as a PDF",
            icon: "doc.richtext"
          ) {
            onPickDestination(.pdf)
          }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .appChromeCornerRadius(14)
      }
      .padding(.horizontal, 20)

      Spacer(minLength: 18)

      Button("Cancel", action: onDismiss)
        .font(.subheadline.weight(.medium))
        .foregroundColor(.secondary)
        .padding(.bottom, 8)
    }
    .padding(.top, 26)
  }
}

private func placesShareOptionRow(
  title: String,
  subtitle: String,
  icon: String,
  iconColor: Color = .primary,
  titleColor: Color = .primary,
  action: @escaping () -> Void
) -> some View {
  Button(action: action) {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(iconColor)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body.weight(.semibold))
          .foregroundColor(titleColor)
        Text(subtitle)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 14)
    .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
}

