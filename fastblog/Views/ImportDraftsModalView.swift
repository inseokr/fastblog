//
//  ImportDraftsModalView.swift
//  Capper
//
//  Premium modal sheet presenting the option to import anonymous (logged-out)
//  drafts into the current account after signing in.
//  Shown at most once per login session.
//

import SwiftUI

struct ImportDraftsModalView: View {
    @EnvironmentObject private var authStateManager: AuthStateManager
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Environment(\.dismiss) private var dismiss

    /// Navigate to local blog list when "Review drafts" is tapped.
    @State private var isShowingReview = false

    private var draftCount: Int {
        createdRecapStore.anonymousDrafts.count
    }

    private var currentUserId: String? {
        authStateManager.currentUserId
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemBackground).opacity(0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.15), Color.indigo.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 24)

                    // Title
                    Text("Found local drafts")
                        .font(.system(.title, design: .serif).weight(.semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)

                    // Body
                    Text("We found **\(draftCount) \(draftCount == 1 ? "blog" : "blogs")** created on this device while you were signed out. Import \(draftCount == 1 ? "it" : "them") into your account?")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 36)

                    // Draft preview chips
                    if draftCount > 0 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(createdRecapStore.anonymousDrafts.prefix(5)) { draft in
                                    DraftChipView(draft: draft)
                                }
                                if draftCount > 5 {
                                    Text("+\(draftCount - 5) more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        .padding(.bottom, 36)
                    }

                    // Action Buttons
                    VStack(spacing: 12) {
                        // Primary: Import
                        Button {
                            if let userId = currentUserId {
                                createdRecapStore.importAnonymousDrafts(into: userId)
                            }
                            authStateManager.showImportDraftsModal = false
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import drafts")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundColor(.white)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .indigo],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

                        // Secondary: Not now
                        Button {
                            authStateManager.showImportDraftsModal = false
                            dismiss()
                        } label: {
                            Text("Not now")
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .foregroundColor(.primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        // Tertiary: Review drafts
                        Button {
                            isShowingReview = true
                        } label: {
                            Text("Review drafts")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        authStateManager.showImportDraftsModal = false
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Draft Review Row

private struct DraftReviewRow: View {
    let draft: CreatedRecapBlog
    let onImport: () -> Void

    @State private var isImported = false

    var body: some View {
        HStack(spacing: 12) {
            // Cover thumbnail
            TripCoverImage(
                theme: draft.coverImageName,
                coverAssetIdentifier: draft.coverAssetIdentifier,
                targetSize: CGSize(width: 160, height: 160)
            )
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title)
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .lineLimit(2)
                    .foregroundColor(isImported ? .secondary : .primary)

                HStack(spacing: 4) {
                    if let country = draft.countryName, !country.isEmpty {
                        Text(country)
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    Text(draft.tripDateRangeText ?? formattedDate(draft.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Import button / imported badge
            if isImported {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isImported = true
                    }
                    onImport()
                } label: {
                    Text("Import")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [.blue, .indigo],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Draft Chip

private struct DraftChipView: View {
    let draft: CreatedRecapBlog

    var body: some View {
        HStack(spacing: 6) {
            if let country = draft.countryName, !country.isEmpty {
                Text(countryFlagEmoji(for: country))
            } else {
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(draft.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
        )
    }

    /// Very simple emoji flag from country name (best-effort).
    private func countryFlagEmoji(for country: String) -> String {
        let flags: [String: String] = [
            "Japan": "🇯🇵", "Korea": "🇰🇷", "South Korea": "🇰🇷",
            "United States": "🇺🇸", "France": "🇫🇷", "Italy": "🇮🇹",
            "Spain": "🇪🇸", "Germany": "🇩🇪", "United Kingdom": "🇬🇧",
            "Australia": "🇦🇺", "Canada": "🇨🇦", "Thailand": "🇹🇭",
            "Vietnam": "🇻🇳", "Indonesia": "🇮🇩", "China": "🇨🇳",
            "Taiwan": "🇹🇼", "Singapore": "🇸🇬", "Mexico": "🇲🇽",
            "Brazil": "🇧🇷", "Portugal": "🇵🇹", "Netherlands": "🇳🇱",
            "India": "🇮🇳", "Turkey": "🇹🇷", "Greece": "🇬🇷",
        ]
        return flags[country] ?? "🌍"
    }
}

// MARK: - Preview

#Preview {
    ImportDraftsModalView()
        .environmentObject(AuthStateManager.shared)
        .environmentObject(CreatedRecapBlogStore.shared)
}
