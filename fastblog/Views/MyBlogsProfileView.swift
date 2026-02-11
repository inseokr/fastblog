//
//  MyBlogsProfileView.swift
//  Capper
//
//  My Blogs: dark blue background, vertical list of Country Cards, fixed search bar and My Map button.
//

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

    init(createdRecapStore: CreatedRecapBlogStore, selectedCreatedRecap: Binding<CreatedRecapBlog?>) {
        _viewModel = StateObject(wrappedValue: MyBlogsProfileViewModel())
        _selectedCreatedRecap = selectedCreatedRecap
    }

    private let backgroundBlue = Color(red: 0.05, green: 0.08, blue: 0.22)

    var body: some View {
        ZStack(alignment: .bottom) {
            backgroundBlue
                .ignoresSafeArea()

            ScrollView {
                let allSections = MyBlogsProfileViewModel.sections(from: createdRecapStore.countrySummaries)
                let sections = viewModel.filteredSections(from: allSections)
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
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 12)
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
            selectedCreatedRecap: .constant(nil)
        )
        .environmentObject(CreatedRecapBlogStore.shared)
    }
}
