//
//  StorageManagementView.swift
//  fastblog
//

import Photos
import SwiftUI
import UIKit

struct StorageManagementView: View {
    @Binding var draft: RecapBlogDetail
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Selection state

    @State private var isSelectMode = false
    @State private var selectedPhotoIds: Set<UUID> = []

    // MARK: - Filter state

    @State private var activeDayFilter: Int?
    @State private var showFilterDropdown = false

    // MARK: - Delete state

    @State private var pendingInApp: [RecapPhoto] = []
    @State private var pendingPhone: [RecapPhoto] = []
    @State private var deletedAny = false
    @State private var showInAppAlert = false
    @State private var showPhoneAlert = false

    // MARK: - Triage state

    @State private var triageStartPhotoId: UUID?

    // MARK: - First-time tooltip

    @AppStorage("bloggo.hasSeenUnusedPhotosTooltip") private var hasSeenUnusedPhotosTooltip: Bool = false
    @State private var showIntroTooltip: Bool = false

    // MARK: - Grid layout (matches ManagePhotosView)

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    // MARK: - Derived data

    private var allUnused: [(dayIndex: Int, photo: RecapPhoto)] {
        draft.days.flatMap { day in
            day.placeStops.flatMap { stop in
                stop.photos
                    .filter { !$0.isIncluded }
                    .map { (day.dayIndex, $0) }
            }
        }
    }

    private var visiblePhotos: [(dayIndex: Int, photo: RecapPhoto)] {
        guard let filter = activeDayFilter else { return allUnused }
        return allUnused.filter { $0.dayIndex == filter }
    }

    private var filterableDays: [(dayIndex: Int, date: Date)] {
        let daysWithPhotos = Set(allUnused.map(\.dayIndex))
        return draft.days
            .filter { daysWithPhotos.contains($0.dayIndex) }
            .map { ($0.dayIndex, $0.date) }
            .sorted { $0.dayIndex < $1.dayIndex }
    }

    private var navigationTitleText: String {
        if isSelectMode { return "\(selectedPhotoIds.count) selected" }
        return "Unused Photos"
    }

    private var allVisiblePhotosAreSelected: Bool {
        !visiblePhotos.isEmpty && visiblePhotos.allSatisfy { selectedPhotoIds.contains($0.photo.id) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            photoGrid
            if triageStartPhotoId == nil {
                bottomActionBar
            }
            if showFilterDropdown {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { showFilterDropdown = false }

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        filterDropdown
                            .padding(.leading, 16)
                            .padding(.bottom, 88)
                        Spacer()
                    }
                }
            }

            if showIntroTooltip {
                UnusedPhotosIntroTooltipOverlay(onGotIt: {
                    hasSeenUnusedPhotosTooltip = true
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showIntroTooltip = false
                    }
                })
                .transition(.opacity)
                .zIndex(60)
            }

            if let startId = triageStartPhotoId {
                UnusedPhotoTriageView(
                    photos: visiblePhotos.map(\.photo),
                    startingPhotoId: startId,
                    onDelete: { beginDeleteFromSlideshow($0) },
                    onDismiss: {
                        triageStartPhotoId = nil
                    }
                )
                .transition(.opacity)
                .zIndex(40)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showIntroTooltip)
        .animation(.easeInOut(duration: 0.3), value: triageStartPhotoId != nil)
        .onAppear {
            if !hasSeenUnusedPhotosTooltip && !showIntroTooltip {
                showIntroTooltip = true
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { navigationToolbar }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onChange(of: activeDayFilter) { _, _ in
            let visibleIds = Set(visiblePhotos.map(\.photo.id))
            selectedPhotoIds = selectedPhotoIds.intersection(visibleIds)
        }
        .alert(
            "Delete \(pendingInApp.count) Photo\(pendingInApp.count == 1 ? "" : "s") From Bloggo?",
            isPresented: $showInAppAlert
        ) {
            Button("Delete", role: .destructive) { executeDeleteInApp() }
            Button("No", role: .cancel) {
                pendingInApp = []
                if !pendingPhone.isEmpty { showPhoneAlert = true }
            }
        } message: {
            Text("Removes from Bloggo gallery.")
        }
        .alert(
            "Delete \(pendingPhone.count) Photo\(pendingPhone.count == 1 ? "" : "s") From Phone?",
            isPresented: $showPhoneAlert
        ) {
            Button("Delete", role: .destructive) { executeDeletePhone() }
            Button("No", role: .cancel) {
                pendingPhone = []
                finishDeleteFlow()
            }
        } message: {
            Text("Save storage by cleaning up unwanted photos.")
        }
    }

    // MARK: - Grid

    private var photoGrid: some View {
        Group {
            if visiblePhotos.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(visiblePhotos, id: \.photo.id) { item in
                            photoCell(item.photo)
                        }
                    }
                }
            }
        }
    }

    private func photoCell(_ photo: RecapPhoto) -> some View {
        let size = (UIScreen.main.bounds.width - 4) / 3
        let isSelected = selectedPhotoIds.contains(photo.id)

        return ZStack(alignment: .topTrailing) {
            RecapPhotoThumbnail(
                photo: photo,
                cornerRadius: 0,
                showIcon: false,
                targetSize: CGSize(width: size * 2, height: size * 2)
            )
            .frame(width: size, height: size)
            .clipped()
            .opacity(isSelectMode && !isSelected ? 0.4 : 1.0)

            if isSelectMode {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                        .padding(4)
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(4)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectMode {
                toggleSelection(photo.id)
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    triageStartPhotoId = photo.id
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No unused photos")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("All photos in this blog are included.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if isSelectMode {
                Button("Cancel") { exitSelectMode() }
            } else {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                }
            }
        }
        if triageStartPhotoId == nil {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSelectMode {
                    Button(allVisiblePhotosAreSelected ? "Deselect All" : "Select All") {
                        if allVisiblePhotosAreSelected {
                            deselectAll()
                        } else {
                            selectAll()
                        }
                    }
                } else {
                    Button("Select") { enterSelectMode() }
                }
            }
        }
    }

    private func enterSelectMode() {
        isSelectMode = true
        selectedPhotoIds = []
    }

    private func exitSelectMode() {
        isSelectMode = false
        selectedPhotoIds = []
        showFilterDropdown = false
    }

    private func toggleSelection(_ id: UUID) {
        if selectedPhotoIds.contains(id) {
            selectedPhotoIds.remove(id)
        } else {
            selectedPhotoIds.insert(id)
        }
    }

    private func selectAll() {
        selectedPhotoIds = Set(visiblePhotos.map(\.photo.id))
    }

    private func deselectAll() {
        selectedPhotoIds = []
    }

    // MARK: - Bottom bar (matches AppCaptureGalleryView select-mode chrome)

    private var bottomActionBar: some View {
        let filterActive = activeDayFilter != nil || showFilterDropdown
        return HStack {
            Button {
                showFilterDropdown.toggle()
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(filterActive ? Color(red: 0.04, green: 0.52, blue: 1.0) : .white)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
            }
            .accessibilityLabel("Filter by day")

            Spacer()

            if isSelectMode {
                Text("\(selectedPhotoIds.count) Photos Selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    beginDeleteSelected()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(selectedPhotoIds.isEmpty ? .gray : Color(red: 1.0, green: 0.27, blue: 0.23))
                        .frame(width: 56, height: 56)
                        .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                }
                .disabled(selectedPhotoIds.isEmpty)
                .accessibilityLabel("Delete selected photos")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    /// True when this photo is backed by the system Photos library (not Bloggo in-app capture storage).
    private func isPhotoLibraryAsset(_ photo: RecapPhoto) -> Bool {
        guard let lid = photo.localIdentifier, !lid.isEmpty else { return false }
        return !lid.hasPrefix(AppCapturePhotoService.prefix)
    }

    private func beginDeleteSelected() {
        let selected = visiblePhotos
            .filter { selectedPhotoIds.contains($0.photo.id) }
            .map(\.photo)
        queueDeletion(for: selected)
    }

    private func beginDeleteFromSlideshow(_ photo: RecapPhoto) {
        queueDeletion(for: [photo])
    }

    private func queueDeletion(for photos: [RecapPhoto]) {
        pendingInApp = photos.filter { !isPhotoLibraryAsset($0) }
        pendingPhone = photos.filter { isPhotoLibraryAsset($0) }
        deletedAny = false
        if !pendingInApp.isEmpty {
            showInAppAlert = true
        } else if !pendingPhone.isEmpty {
            showPhoneAlert = true
        }
    }

    // MARK: - Filter dropdown

    /// Indicator for the active filter row; other rows use a neutral dot.
    private var filterSelectionDotColor: Color {
        Color(red: 0.35, green: 0.85, blue: 0.5)
    }

    private var filterInactiveDotColor: Color {
        Color.white.opacity(0.35)
    }

    private var filterDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FILTER BY DAY")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            Divider().background(Color.white.opacity(0.1))

            Button {
                activeDayFilter = nil
                showFilterDropdown = false
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(activeDayFilter == nil ? filterSelectionDotColor : filterInactiveDotColor)
                        .frame(width: 8, height: 8)
                    Text("All Days")
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            if !filterableDays.isEmpty {
                Divider().background(Color.white.opacity(0.08)).padding(.leading, 16)
            }

            ForEach(filterableDays, id: \.dayIndex) { item in
                let isActive = activeDayFilter == item.dayIndex
                Button {
                    activeDayFilter = isActive ? nil : item.dayIndex
                    showFilterDropdown = false
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(isActive ? filterSelectionDotColor : filterInactiveDotColor)
                            .frame(width: 8, height: 8)
                        Text("Day \(item.dayIndex + 1)")
                            .foregroundStyle(.white)
                        Text(formattedDate(item.date))
                            .foregroundStyle(.white)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                if item.dayIndex != filterableDays.last?.dayIndex {
                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 16)
                }
            }
        }
        .background(
            RoundedRectangle(appChromeBaseRadius: 14)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.97))
                .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 4)
        )
        .frame(minWidth: 220, maxWidth: 280)
    }

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }

    // MARK: - Delete helpers

    private func executeDeleteInApp() {
        for photo in pendingInApp {
            if let lid = photo.localIdentifier,
               lid.hasPrefix(AppCapturePhotoService.prefix),
               let uuid = AppCapturePhotoService.uuid(from: lid) {
                AppCapturePhotoService.shared.deleteCapture(captureId: uuid)
            }
        }
        let storeIds: Set<UUID> = Set(pendingInApp.compactMap { photo in
            let name = photo.imageName
            if let direct = UUID(uuidString: name) { return direct }
            let stripped = (name as NSString).deletingPathExtension
            return UUID(uuidString: stripped)
        })
        if !storeIds.isEmpty {
            InAppCameraPhotoStore.shared.removePhotos(ids: storeIds)
        }
        removeFromDraft(pendingInApp)
        deletedAny = true
        pendingInApp = []

        if !pendingPhone.isEmpty {
            showPhoneAlert = true
        } else {
            finishDeleteFlow()
        }
    }

    private func executeDeletePhone() {
        let photos = pendingPhone
        let identifiers = photos.compactMap(\.localIdentifier).filter { lid in
            !lid.isEmpty && !lid.hasPrefix(AppCapturePhotoService.prefix)
        }
        guard !identifiers.isEmpty else {
            removeFromDraft(photos)
            deletedAny = true
            pendingPhone = []
            finishDeleteFlow()
            return
        }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(fetchResult)
        }, completionHandler: { _, _ in
            DispatchQueue.main.async {
                removeFromDraft(photos)
                deletedAny = true
                pendingPhone = []
                finishDeleteFlow()
            }
        })
    }

    private func removeFromDraft(_ photos: [RecapPhoto]) {
        let ids = Set(photos.map(\.id))
        for dayIdx in draft.days.indices {
            for stopIdx in draft.days[dayIdx].placeStops.indices {
                draft.days[dayIdx].placeStops[stopIdx].photos.removeAll { ids.contains($0.id) }
            }
        }
    }

    private func finishDeleteFlow() {
        if deletedAny { onSave() }
        deletedAny = false
        let remaining = Set(visiblePhotos.map(\.photo.id))
        selectedPhotoIds = selectedPhotoIds.intersection(remaining)
        if visiblePhotos.isEmpty {
            isSelectMode = false
            selectedPhotoIds = []
            activeDayFilter = nil
            triageStartPhotoId = nil
        }
    }
}

// MARK: - Full-screen slideshow (ManagePhotos-style pager + filmstrip)

private struct UnusedPhotosSlideshowView: View {
    let photos: [RecapPhoto]
    @Binding var selectedPhotoId: UUID?
    var shouldOfferDownload: (RecapPhoto) -> Bool
    var onDelete: (RecapPhoto) -> Void
    var onDownload: (RecapPhoto) -> Void

    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoomScale: CGFloat = 1.0

    private var currentPhoto: RecapPhoto? {
        if let id = selectedPhotoId, let p = photos.first(where: { $0.id == id }) { return p }
        return photos.first
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if photos.isEmpty {
                Color.black.ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    TabView(selection: $selectedPhotoId) {
                        ForEach(photos) { photo in
                            ZStack {
                                RecapPhotoThumbnail(
                                    photo: photo,
                                    cornerRadius: 0,
                                    showIcon: false,
                                    targetSize: CGSize(width: 1200, height: 1200)
                                )
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .scaleEffect(zoomScale)
                            }
                            .contentShape(Rectangle())
                            .tag(photo.id)
                            .onTapGesture {
                                if zoomScale > 1.01 {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        zoomScale = 1.0
                                        baseZoomScale = 1.0
                                    }
                                }
                            }
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        zoomScale = max(1.0, baseZoomScale * value)
                                    }
                                    .onEnded { _ in
                                        if zoomScale < 1.1 {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                zoomScale = 1.0
                                                baseZoomScale = 1.0
                                            }
                                        } else {
                                            baseZoomScale = zoomScale
                                        }
                                    }
                            )
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxHeight: .infinity)

                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(photos) { photo in
                                    let isCurrent = photo.id == selectedPhotoId
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedPhotoId = photo.id
                                        }
                                    } label: {
                                        RecapPhotoThumbnail(
                                            photo: photo,
                                            cornerRadius: 8,
                                            showIcon: false,
                                            targetSize: CGSize(width: 120, height: 120)
                                        )
                                        .frame(width: 56, height: 56)
                                        .clipped()
                                        .overlay(
                                            RoundedRectangle(appChromeBaseRadius: 8)
                                                .stroke(isCurrent ? Color.white : Color.clear, lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .id(photo.id)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                        .onAppear {
                            if let id = selectedPhotoId {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                        .onChange(of: selectedPhotoId) { _, newId in
                            guard let id = newId else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                    .padding(.bottom, 4)

                    HStack {
                        if let p = currentPhoto, shouldOfferDownload(p) {
                            Button {
                                onDownload(p)
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 56, height: 56)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                            }
                            .accessibilityLabel("Download Photo")
                        }

                        Spacer()

                        Button {
                            if let p = currentPhoto { onDelete(p) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                                .frame(width: 56, height: 56)
                                .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 12))
                        }
                        .accessibilityLabel("Delete Photo")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .padding(.top, 8)
            }
        }
        .onChange(of: photos.map(\.id)) { _, _ in
            if photos.isEmpty {
                selectedPhotoId = nil
                return
            }
            if let id = selectedPhotoId, photos.contains(where: { $0.id == id }) { return }
            selectedPhotoId = photos.first?.id
        }
        .onChange(of: selectedPhotoId) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                zoomScale = 1.0
                baseZoomScale = 1.0
            }
        }
    }
}

// MARK: - Triage view

private struct UnusedPhotoTriageView: View {
    let photos: [RecapPhoto]
    let startingPhotoId: UUID
    var onDelete: (RecapPhoto) -> Void
    var onDismiss: () -> Void

    @State private var triageQueue: [UUID] = []
    @State private var currentQueueIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var dragRotation: Double = 0
    @State private var deleteOverlayOpacity: Double = 0
    @State private var keepOverlayOpacity: Double = 0
    @AppStorage("bloggo.hasSeenUnusedPhotosTriageTooltip") private var hasSeenTriageTooltip: Bool = false
    @State private var showTriageTooltip = false

    // MARK: - Derived

    private var currentPhoto: RecapPhoto? {
        guard currentQueueIndex < triageQueue.count else { return nil }
        let id = triageQueue[currentQueueIndex]
        return photos.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom top bar
                HStack {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if !triageQueue.isEmpty {
                        Text("Photo \(currentQueueIndex + 1) of \(triageQueue.count)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // Photo area
                if let photo = currentPhoto {
                    ZStack {
                        RecapPhotoThumbnail(
                            photo: photo,
                            cornerRadius: 0,
                            showIcon: false,
                            targetSize: CGSize(width: 1200, height: 1200)
                        )
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Delete tint (swipe left)
                        Color.red
                            .opacity(deleteOverlayOpacity * 0.35)
                            .allowsHitTesting(false)

                        // Keep tint (swipe right)
                        Color.green
                            .opacity(keepOverlayOpacity * 0.35)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: dragOffset)
                    .rotationEffect(.degrees(dragRotation))
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                let x = value.translation.width
                                dragOffset = x
                                dragRotation = max(-5, min(5, Double(x) / 20))
                                if x < 0 {
                                    deleteOverlayOpacity = min(abs(Double(x)) / 80, 1.0)
                                    keepOverlayOpacity = 0
                                } else {
                                    keepOverlayOpacity = min(Double(x) / 80, 1.0)
                                    deleteOverlayOpacity = 0
                                }
                            }
                            .onEnded { value in
                                let x = value.translation.width
                                if x < -80 {
                                    commitSwipe(direction: .left)
                                } else if x > 80 {
                                    commitSwipe(direction: .right)
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                        resetDrag()
                                    }
                                }
                            }
                    )
                } else {
                    Spacer()
                }

                // Swipe hint
                Text("\u{2190} delete      keep \u{2192}")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.vertical, 12)

                // CTA buttons
                HStack(spacing: 12) {
                    Button { triggerDelete() } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button { triggerKeep() } label: {
                        Label("Keep", systemImage: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.ultraThinMaterial, in: RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            if showTriageTooltip {
                UnusedPhotosTriageTooltipOverlay(onGotIt: {
                    hasSeenTriageTooltip = true
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showTriageTooltip = false
                    }
                })
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showTriageTooltip)
        .onAppear {
            buildQueue()
            if !hasSeenTriageTooltip {
                showTriageTooltip = true
            }
        }
        .onChange(of: photos.map(\.id)) { _, newIds in
            if newIds.isEmpty { onDismiss(); return }
            guard currentQueueIndex < triageQueue.count else { return }
            let currentId = triageQueue[currentQueueIndex]
            let newIdSet = Set(newIds)
            if !newIdSet.contains(currentId) { advance() }
        }
    }

    // MARK: - Queue

    private func buildQueue() {
        let allIds = photos.map(\.id)
        guard let startIdx = allIds.firstIndex(of: startingPhotoId) else {
            triageQueue = allIds
            currentQueueIndex = 0
            return
        }
        triageQueue = Array(allIds[startIdx...]) + Array(allIds[..<startIdx])
        currentQueueIndex = 0
    }

    // MARK: - Actions

    private func advance() {
        currentQueueIndex += 1
        if currentQueueIndex >= triageQueue.count {
            onDismiss()
        }
    }

    private func triggerDelete() {
        guard let photo = currentPhoto else { advance(); return }
        onDelete(photo)
        advance()
    }

    private func triggerKeep() {
        advance()
    }

    private enum SwipeDirection { case left, right }

    private func commitSwipe(direction: SwipeDirection) {
        let targetOffset: CGFloat = direction == .left
            ? -UIScreen.main.bounds.width
            : UIScreen.main.bounds.width
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = targetOffset
        }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            resetDrag()
            if direction == .left {
                triggerDelete()
            } else {
                triggerKeep()
            }
        }
    }

    private func resetDrag() {
        dragOffset = 0
        dragRotation = 0
        deleteOverlayOpacity = 0
        keepOverlayOpacity = 0
    }
}

// MARK: - First-time tooltip overlay

private struct UnusedPhotosIntroTooltipOverlay: View {
    let onGotIt: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.stack")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Unused Photos")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                Text("These are the photos from this trip that aren't included in your blog.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Free up space by removing the ones you no longer need from your phone or from Bloggo.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onGotIt) {
                    Text("Got it")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.2), in: RoundedRectangle(appChromeBaseRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(24)
            .background(
                RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .padding(.horizontal, 28)
        }
    }
}

private struct UnusedPhotosTriageTooltipOverlay: View {
    let onGotIt: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "hand.draw")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Review Your Photos")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                Text("Swipe left to delete \u{00B7} Swipe right to keep.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Text("We'll go through each one.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onGotIt) {
                    Text("Got it")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color.white.opacity(0.2),
                            in: RoundedRectangle(appChromeBaseRadius: 14, style: .continuous)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(24)
            .background(
                RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .padding(.horizontal, 28)
        }
    }
}
