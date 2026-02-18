//
//  MyBlogsProfileView.swift
//  Capper
//
//  My Blogs: dark blue background, vertical list of Country Cards, fixed search bar and My Map button.
//

import Photos
import SwiftUI

private let searchBarHeight: CGFloat = 56
private let myMapButtonSize: CGFloat = 52
private let cardSpacing: CGFloat = 16
private let horizontalPadding: CGFloat = 20

struct MyBlogsProfileView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @Binding var selectedCreatedRecap: CreatedRecapBlog?
    @StateObject private var viewModel: MyBlogsProfileViewModel
    @State private var selectedSection: CountrySection?
    @State private var showMyMap = false
    @State private var showViewAll = false
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool
    
    @Binding var showTrips: Bool
    @Binding var showProfile: Bool
    @ObservedObject var tripsViewModel: TripsViewModel
    @StateObject private var recallViewModel = MemoryRecallViewModel()
    @State private var showingRecallModal = false
    @State private var showingCreateFlow = false
    @State private var draftToCreate: TripDraft?

    init(createdRecapStore: CreatedRecapBlogStore, showTrips: Binding<Bool>, showProfile: Binding<Bool>, tripsViewModel: TripsViewModel, selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        _viewModel = StateObject(wrappedValue: MyBlogsProfileViewModel())
        _selectedCreatedRecap = selectedCreatedRecap
        _showTrips = showTrips
        _showProfile = showProfile
        self.tripsViewModel = tripsViewModel
    }

    private let backgroundBlue = Color(red: 0.05, green: 0.08, blue: 0.22)

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundBlue
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    revisitSection
                        .padding(.top, 16)
                    
                    let allSections = MyBlogsProfileViewModel.sections(from: createdRecapStore.countrySummaries)
                    let sections = viewModel.filteredSections(from: allSections)
                    
                    if !sections.isEmpty {
                        countriesHeader
                    }
                    
                    Group {
                    if isSearchActive && !viewModel.isSearching {
                        // Search mode active but nothing typed yet
                        VStack(spacing: 12) {
                            Text("Search by city or blog title")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else if sections.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: cardSpacing) {
                            ForEach(sections) { section in
                                CountryCardView(section: section) {
                                    selectedSection = section
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, searchBarHeight + myMapButtonSize + 24)
            }
        }

        VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    MyMapButton {
                        showMyMap = true
                    }
                    .padding(.trailing, horizontalPadding + 12)
                    .padding(.bottom, searchBarHeight + 24)
                }
                searchBar
            }
            .allowsHitTesting(true)
        }
        .navigationTitle("My Blogs")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("View All") {
                    showViewAll = true
                }
                .foregroundColor(.white)
            }
        }
        .navigationDestination(item: $selectedSection) { section in
            CountryBlogsView(section: section, selectedBlog: $selectedCreatedRecap)
        }
        .navigationDestination(isPresented: $showMyMap) {
            MyMapView(selectedCreatedRecap: $selectedCreatedRecap)
        }
        .sheet(isPresented: $showViewAll) {
            AllRecentsSheet(
                createdRecapStore: createdRecapStore,
                selectedRecap: $selectedCreatedRecap
            )
        }
        .fullScreenCover(isPresented: $showingRecallModal) {
            if let recall = recallViewModel.currentRecall {
                MemoryRecallModal(recall: recall) {
                    // Create blog CTA
                    let draft = tripsViewModel.createDraft(from: recall)
                    draftToCreate = draft
                    showingRecallModal = false
                    
                    // Delay slightly to allow modal dismissal before presenting flow
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showingCreateFlow = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCreateFlow) {
            if let draft = draftToCreate {
                CreateBlogFlowView(trip: draft, startDirectlyCreating: true) { id in
                    // onClose: remove from drafts if any
                    tripsViewModel.removeTrip(id: id)
                    draftToCreate = nil
                    showingCreateFlow = false
                    recallViewModel.refreshRecall()
                }
            }
        }
        .onAppear {
            recallViewModel.onAppear()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No recap blogs yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.9))
            Text("Create one from a trip to see it here by country.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    @ViewBuilder
    private var revisitSection: some View {
        if let recall = recallViewModel.currentRecall {
            VStack(alignment: .leading, spacing: 12) {
                Text("Revisit")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, horizontalPadding)
                
                RevisitRecallCard(recall: recall) {
                    showingRecallModal = true
                }
                .padding(.horizontal, horizontalPadding)
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
            .padding(.bottom, 24)
        }
    }

    private var countriesHeader: some View {
        HStack {
            Text("Countries")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))
            TextField("Search city or blog title", text: $viewModel.searchText)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onTapGesture {
                    isSearchActive = true
                }
            if isSearchActive {
                Button {
                    viewModel.searchText = ""
                    isSearchFocused = false
                    isSearchActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: searchBarHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.4))
                .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 12)
    }
}

private struct RevisitRecallCard: View {
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
                HStack(spacing: 8) {
                    ForEach(recall.thumbnailAssets, id: \.localIdentifier) { asset in
                        AssetPhotoView(assetIdentifier: asset.localIdentifier, cornerRadius: 8, targetSize: CGSize(width: 200, height: 200))
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if recall.photoCount > 3 {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
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
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: 0.1))
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
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

private struct MyMapButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "map.fill")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: myMapButtonSize, height: myMapButtonSize)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        MyBlogsProfileView(
            createdRecapStore: CreatedRecapBlogStore.shared,
            showTrips: .constant(false),
            showProfile: .constant(true),
            tripsViewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared),
            selectedCreatedRecap: .constant(nil)
        )
        .environmentObject(CreatedRecapBlogStore.shared)
    }
}
