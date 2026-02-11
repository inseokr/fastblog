//
//  TripDayPickerView.swift
//  Capper
//

import SwiftUI

struct TripDayPickerView: View {
    @StateObject private var viewModel: TripCreationViewModel
    var onStartCreateBlog: (TripDraft) -> Void
    var isEditMode: Bool = false
    var onUpdate: ((TripDraft) -> Void)? = nil

    @State private var showNoPhotosAlert = false
    @State private var scrollToEdgeAfterDayChange: DayChangeScrollEdge? = nil

    init(trip: TripDraft, onStartCreateBlog: @escaping (TripDraft) -> Void = { _ in }, isEditMode: Bool = false, onUpdate: ((TripDraft) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: TripCreationViewModel(trip: trip))
        self.onStartCreateBlog = onStartCreateBlog
        self.isEditMode = isEditMode
        self.onUpdate = onUpdate
    }

    private var currentDay: TripDay? {
        let idx = viewModel.selectedDayIndex
        guard viewModel.trip.days.indices.contains(idx) else { return nil }
        return viewModel.trip.days[idx]
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let day = currentDay {
                PhotoSelectView(
                    day: day,
                    viewModel: viewModel,
                    embedded: true,
                    onCreateBlog: isEditMode ? nil : { onStartCreateBlog(viewModel.trip) },
                    isEditMode: isEditMode,
                    onUpdate: isEditMode ? { onUpdate?(viewModel.trip) } : nil,
                    onRequestNextDay: {
                        guard viewModel.selectedDayIndex + 1 < viewModel.trip.days.count else { return }
                        scrollToEdgeAfterDayChange = .first
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.selectedDayIndex += 1
                        }
                    },
                    onRequestPreviousDay: {
                        guard viewModel.selectedDayIndex > 0 else { return }
                        scrollToEdgeAfterDayChange = .last
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.selectedDayIndex -= 1
                        }
                    },
                    scrollToEdgeAfterDayChange: $scrollToEdgeAfterDayChange,
                    embeddedBottomContent: { AnyView(createButton) }
                )
            } else {
                Color.black
                    .ignoresSafeArea()
            }

            // Day filter toggles at top, overlaying the photo with glass style
            dayTabsOverlay
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .navigationTitle("Select Photos")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Select Photos", isPresented: $showNoPhotosAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You must select at least one photo to create a blog.")
        }
        .onAppear {
            viewModel.selectedDayIndex = 0
        }
        .onDisappear {
            if viewModel.trip.selectedPhotoCount > 0 {
                let ids = Set(viewModel.trip.days.flatMap { day in day.photos.filter(\.isSelected).map(\.id) })
                TripDraftStore.saveSelection(tripId: viewModel.trip.id, selectedPhotoIds: ids)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var createButton: some View {
        Button {
            if viewModel.canCreateBlog {
                if isEditMode {
                    onUpdate?(viewModel.trip)
                } else {
                    onStartCreateBlog(viewModel.trip)
                }
            } else {
                showNoPhotosAlert = true
            }
        } label: {
            Text(isEditMode ? "Update" : "Create")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .background(viewModel.canCreateBlog ? Color.orange : Color(white: 0.35))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .padding(.top, 8)
        .disabled(!viewModel.canCreateBlog)
    }

    /// Day filters stay fixed (no programmatic scroll) so they don't flicker or shift when changing photos or days.
    private var dayTabsOverlay: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.trip.days.enumerated()), id: \.element.id) { index, day in
                    DayTabPill(
                        title: "Day \(day.dayIndex)",
                        isSelected: viewModel.selectedDayIndex == index
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedDayIndex = index
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// Wireframe style: selected = white text on dark pill, unselected = dark text on light gray pill
struct DayTabPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(isSelected ? Color(white: 0.22) : Color(uiColor: .tertiarySystemFill))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
