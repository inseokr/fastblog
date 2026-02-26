//
//  CreateBlogFlowView.swift
//  Capper
//

import SwiftUI

/// Four-step flow: Title → Cover Photo → Creating (animation) → Home. When existingBlogId is set, acts as Update flow: button says "Update" and calls updateBlog + onUpdateComplete instead of addCreatedBlog.
struct CreateBlogFlowView: View {
    let trip: TripDraft
    var existingBlogId: UUID? = nil
    var startDirectlyCreating: Bool = false
    var onUpdateComplete: (() -> Void)? = nil
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Environment(\.dismissToLanding) private var dismissToLanding
    @Environment(\.dismiss) private var dismiss
    var onClose: (UUID) -> Void

    @State private var step: Step = .title
    @State private var flowTitle: String = ""
    @State private var flowCoverTheme: String = ""
    @State private var flowCoverAssetIdentifier: String?

    /// Duration to show the Creating Recap animation before navigating home.
    private let creatingAnimationDuration: TimeInterval = 5.0

    @State private var showExitConfirmation = false

    private enum Step {
        case title
        case cover
        case creating
    }

    var body: some View {
        Group {
            switch step {
            case .title:
                TitleInputView(title: $flowTitle, onNext: goToCover)
            case .cover:
                CoverPhotoSelectView(
                    trip: trip,
                    coverTheme: flowCoverTheme.isEmpty ? trip.coverTheme : flowCoverTheme,
                    coverAssetIdentifier: $flowCoverAssetIdentifier,
                    onDone: { finishFromCover() },
                    primaryButtonTitle: existingBlogId != nil ? "Update" : nil
                )
            case .creating:
                CreatingRecapView()
                    .onAppear {
                        Task {
                            let animationStart = Date()

                            // Determine the trip to build from
                            let tripForBuild: TripDraft
                            if startDirectlyCreating {
                                let selectedTrip = await TripPhotoSelectionService.shared.selectTopPhotosPerCluster(trip: trip)
                                createdRecapStore.addCreatedBlog(trip: selectedTrip)
                                tripForBuild = selectedTrip
                            } else {
                                tripForBuild = createdRecapStore.tripDraft(for: trip.id) ?? trip
                            }

                            // Build full blog detail (geocoding + Vision AI scoring) during animation
                            let detail = await createdRecapStore.buildBlogDetailAsync(from: tripForBuild)

                            // Ensure minimum animation duration has elapsed
                            let elapsed = Date().timeIntervalSince(animationStart)
                            let remaining = creatingAnimationDuration - elapsed
                            if remaining > 0 {
                                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                            }

                            // Save pre-built detail so the blog page loads instantly
                            createdRecapStore.saveBlogDetail(detail, asDraft: true)
                            goToLanding()
                        }
                    }
            }
        }
        .onAppear {
            flowTitle = trip.defaultBlogTitle
            flowCoverTheme = trip.coverTheme
            if flowCoverAssetIdentifier == nil {
                flowCoverAssetIdentifier = trip.coverAssetIdentifier ?? trip.days.flatMap(\.photos).first(where: \.isSelected)?.localIdentifier
            }
            if startDirectlyCreating {
                step = .creating
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if step == .title || step == .cover {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showExitConfirmation = true
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .alert("Save Before Leaving?", isPresented: $showExitConfirmation) {
            Button("Save Draft") {
                finishFromCover(asDraft: true)
            }
            Button("Don't Save", role: .destructive) {
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Do you want to save this blog as a draft before leaving?")
        }
    }

    private func goToCover() {
        step = .cover
    }

    /// Called when user taps Done on Cover Photo. For new blog: add blog, show Creating animation, then go to landing. For update: update and dismiss.
    private func finishFromCover(asDraft: Bool = false) {
        var modifiedTrip = trip
        modifiedTrip.title = flowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? trip.defaultBlogTitle : flowTitle
        modifiedTrip.coverTheme = flowCoverTheme.isEmpty ? trip.coverTheme : flowCoverTheme
        modifiedTrip.coverImageName = modifiedTrip.coverTheme
        modifiedTrip.coverAssetIdentifier = flowCoverAssetIdentifier ?? trip.coverAssetIdentifier
        if let blogId = existingBlogId {
            Task {
                await createdRecapStore.updateBlog(blogId: blogId, trip: modifiedTrip)
                await MainActor.run {
                    onUpdateComplete?()
                    dismiss()
                }
            }
        } else {
            createdRecapStore.addCreatedBlog(trip: modifiedTrip)
            if asDraft {
                // If saving as draft, we don't show the "Creating" animation, just go home
                goToLanding()
            } else {
                // Deferred to goToLanding() so the "Creating" view isn't dismissed immediately.
                step = .creating
            }
        }
    }

    private func goToLanding() {
        // Now clean up the trip from drafts and dismiss
        onClose(trip.id)
        dismissToLanding()
    }
}

#Preview {
    CreateBlogFlowView(
        trip: TripDraft(
            title: "Iceland",
            dateRangeText: "Jan 1 – Jan 5",
            days: [],
            coverImageName: "photo",
            isScannedFromDefaultRange: true
        ),
        onClose: { _ in }
    )
    .environmentObject(CreatedRecapBlogStore.shared)
}
