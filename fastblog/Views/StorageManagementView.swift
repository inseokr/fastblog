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

    // MARK: - Full-screen slideshow

    @State private var fullScreenPhotoId: UUID?
    @State private var downloadToast: String?

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
        if fullScreenPhotoId != nil { return "" }
        if isSelectMode { return "\(selectedPhotoIds.count) selected" }
        return "Unused Photos"
    }

    /// Photo currently shown in the full-screen unused-photos viewer (updates when the user swipes).
    private var fullScreenHeaderPhoto: RecapPhoto? {
        guard let id = fullScreenPhotoId else { return nil }
        return visiblePhotos.first { $0.photo.id == id }?.photo
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            photoGrid
            if fullScreenPhotoId == nil {
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
            if fullScreenPhotoId != nil {
                UnusedPhotosSlideshowView(
                    photos: visiblePhotos.map(\.photo),
                    selectedPhotoId: $fullScreenPhotoId,
                    shouldOfferDownload: { !isPhotoLibraryAsset($0) },
                    onDelete: { beginDeleteFromSlideshow($0) },
                    onDownload: { downloadPhotoToLibrary($0) }
                )
                .transition(.opacity)
                .zIndex(40)
            }
            if let downloadToast {
                VStack {
                    Spacer()
                    Text(downloadToast)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.7)))
                        .padding(.bottom, 32)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
                .zIndex(50)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: downloadToast != nil)
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
                    fullScreenPhotoId = photo.id
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
            if fullScreenPhotoId != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { fullScreenPhotoId = nil }
                } label: {
                    Image(systemName: "xmark")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Close full photo")
            } else if isSelectMode {
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
        if fullScreenPhotoId != nil, let photo = fullScreenHeaderPhoto {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(Self.unusedPhotoFullscreenHeaderDateFormatter.string(from: photo.timestamp))
                    Text(Self.unusedPhotoFullscreenHeaderTimeFormatter.string(from: photo.timestamp))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            }
        }
        if fullScreenPhotoId == nil {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSelectMode {
                    Button("Select All") { selectAll() }
                } else {
                    Button("Select") { enterSelectMode() }
                }
            }
        }
    }

    private static let unusedPhotoFullscreenHeaderDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d yyyy"
        f.locale = Locale.autoupdatingCurrent
        return f
    }()

    private static let unusedPhotoFullscreenHeaderTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale.autoupdatingCurrent
        return f
    }()

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
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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

    private func downloadPhotoToLibrary(_ photo: RecapPhoto) {
        Task {
            let image = await loadUIImageForBloggoExport(photo)
            await MainActor.run {
                guard let image else {
                    downloadToast = "Couldn't load photo"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { downloadToast = nil }
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }, completionHandler: { success, _ in
                    DispatchQueue.main.async {
                        downloadToast = success ? "1 photo saved to Photos" : "Couldn't save to Photos"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            downloadToast = nil
                        }
                    }
                })
            }
        }
    }

    private func loadUIImageForBloggoExport(_ photo: RecapPhoto) async -> UIImage? {
        if let lid = photo.localIdentifier, lid.hasPrefix(AppCapturePhotoService.prefix),
           let uuid = AppCapturePhotoService.uuid(from: lid) {
            return AppCapturePhotoService.shared.loadImage(captureId: uuid)
        }
        let name = photo.imageName
        let uuidFromName = UUID(uuidString: name) ?? UUID(uuidString: (name as NSString).deletingPathExtension)
        if let uuid = uuidFromName {
            if let entry = InAppCameraPhotoStore.shared.entries.first(where: { $0.id == uuid }) {
                return InAppCameraPhotoStore.shared.image(for: entry)
            }
            let url = InAppCameraPhotoStore.photoDirectory.appendingPathComponent("\(uuid.uuidString).jpg")
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                return img
            }
        }
        let cloud = photo.cloudURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cloud.isEmpty else { return nil }
        do {
            let signed = try await APIManager.shared.fetchSignedPhotoURL(permanentURL: cloud)
            let (data, _) = try await URLSession.shared.data(from: signed)
            return UIImage(data: data)
        } catch {
            return nil
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
            RoundedRectangle(cornerRadius: 14)
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
            fullScreenPhotoId = nil
        } else if let fs = fullScreenPhotoId, !remaining.contains(fs) {
            fullScreenPhotoId = visiblePhotos.first?.photo.id
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
                                            RoundedRectangle(cornerRadius: 8)
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
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .accessibilityLabel("Download Photo")
                        }

                        Spacer()

                        Button {
                            if let p = currentPhoto { onDelete(p) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
