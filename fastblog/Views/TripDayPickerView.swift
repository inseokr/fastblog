//
//  TripDayPickerView.swift
//  Capper
//

import SwiftUI

struct TripDayPickerView: View {
    @StateObject private var viewModel: TripCreationViewModel
    var onStartCreateBlog: (TripDraft) -> Void
    var isEditMode: Bool = false
    var onCancel: (() -> Void)? = nil
    var onUpdate: ((TripDraft) -> Void)? = nil

    @State private var showNoPhotosAlert = false
    @State private var scrollToEdgeAfterDayChange: DayChangeScrollEdge? = nil

    init(trip: TripDraft, initialDayIndex: Int = 0, onStartCreateBlog: @escaping (TripDraft) -> Void = { _ in }, isEditMode: Bool = false, onCancel: (() -> Void)? = nil, onUpdate: ((TripDraft) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: TripCreationViewModel(trip: trip, initialDayIndex: initialDayIndex))
        self.onStartCreateBlog = onStartCreateBlog
        self.isEditMode = isEditMode
        self.onCancel = onCancel
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
                    embeddedBottomContent: isEditMode ? nil : { AnyView(createButton) }
                )
            } else {
                Color.black
                    .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .safeAreaInset(edge: .top, spacing: 0) {
            dayTabStrip
        }
        .navigationTitle("Photo Selection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let cancel = onCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: cancel) {
                        Image(systemName: "xmark")
                            .fontWeight(.medium)
                    }
                }
            }
            if isEditMode {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        if viewModel.canCreateBlog {
                            onUpdate?(viewModel.trip)
                        } else {
                            showNoPhotosAlert = true
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .alert("Select Photos", isPresented: $showNoPhotosAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You must select at least one photo to create a blog.")
        }
        .onAppear {
            if !isEditMode { AppAnalytics.shared.trackEvent(name: "trip_selected") }
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
        .appChromeCornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 8)
        .disabled(!viewModel.canCreateBlog)
    }

    private var dayTabStrip: some View {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
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
