//
//  KakaoMapTestView.swift
//  fastblog
//
//  Developer test harness for Kakao Maps + Kakao Local API.
//  Not wired into production navigation — invoke from any debug entry point:
//    .sheet(isPresented: $showKakaoTest) { KakaoMapTestView() }
//
//  Tests:
//    1. Map renders and authenticates (watch Xcode console for "[KakaoMap]" logs)
//    2. Tap on map → Kakao Local category search (POI-style), else reverse geocode
//    3. Keyword search → pin moves to selected place
//    4. Zoom in / zoom out buttons
//    5. API key availability badge (both Native and REST keys)
//

import CoreLocation
import SwiftUI

@MainActor
final class KakaoMapTestViewModel: ObservableObject {
    // MARK: - Map state
    @Published var center = CLLocationCoordinate2D(latitude: 37.5796, longitude: 126.9770) // Gyeongbokgung
    @Published var zoomInTrigger = 0
    @Published var zoomOutTrigger = 0

    // MARK: - Search
    @Published var searchQuery = ""
    @Published var searchResults: [KakaoPlace] = []
    @Published var isSearching = false

    // MARK: - Tap / geocode
    @Published var lastTapCoord: CLLocationCoordinate2D?
    @Published var lastTapName: String?
    @Published var isGeocoding = false

    // MARK: - Key status
    var nativeKeyStatus: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "KakaoNativeAppKey") as? String,
              !key.isEmpty, !key.hasPrefix("$"), !key.contains("YOUR_KAKAO") else {
            return "missing"
        }
        return "✓ \(key.prefix(6))…"
    }

    var restKeyStatus: String {
        KakaoLocalService.shared.isAvailable
            ? "✓ \(KakaoLocalService.shared.apiKey.prefix(6))…"
            : "missing"
    }

    // MARK: - Actions

    /// Resolves tap like production: Kakao category POI search first, then reverse geocode.
    func handleTap(_ coord: CLLocationCoordinate2D, zoom: Int, isDirectPOITap: Bool, search: PlaceSearchViewModel) async {
        center = coord
        lastTapCoord = coord
        lastTapName = nil
        isGeocoding = true
        defer { isGeocoding = false }

        switch await search.resolveKakaoMapTapPOI(near: coord, kakaoZoomLevel: zoom, isDirectPOITap: isDirectPOITap) {
        case .single(let name, _, _):
            lastTapName = name
        case .ambiguous(let candidates):
            let sample = candidates.prefix(2).map(\.name).joined(separator: " · ")
            lastTapName = "\(candidates.count) nearby: \(sample)\(candidates.count > 2 ? " …" : "")"
        case .none:
            let doc = await KakaoLocalService.shared.reverseGeocode(coordinate: coord)
            lastTapName = doc?.bestPlaceName.isEmpty == false
                ? doc?.bestPlaceName
                : "(\(String(format: "%.5f", coord.latitude)), \(String(format: "%.5f", coord.longitude)))"
        }
    }

    func search() {
        guard !searchQuery.isEmpty else { searchResults = []; return }
        isSearching = true
        Task {
            searchResults = await KakaoLocalService.shared.searchPlaces(query: searchQuery, near: center)
            isSearching = false
        }
    }

    func selectPlace(_ place: KakaoPlace) {
        guard let coord = place.coordinate else { return }
        center = coord
        lastTapName = place.place_name
        searchQuery = ""
        searchResults = []
    }
}

struct KakaoMapTestView: View {
    @StateObject private var vm = KakaoMapTestViewModel()
    @StateObject private var searchVM = PlaceSearchViewModel()
    @State private var showSearch = false

    var body: some View {
        ZStack(alignment: .top) {
            // MARK: Map
            KakaoTappableMapView(
                center: vm.center,
                title: vm.lastTapName,
                zoomInTrigger: vm.zoomInTrigger,
                zoomOutTrigger: vm.zoomOutTrigger,
                onTap: { coord, zoom, isDirectPOITap in
                    Task { await vm.handleTap(coord, zoom: zoom, isDirectPOITap: isDirectPOITap, search: searchVM) }
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: Status bar
                statusBar

                Spacer()

                // MARK: Tap result
                if let name = vm.lastTapName {
                    tapResultBanner(name: name)
                } else if vm.isGeocoding {
                    geocodingBanner
                }

                // MARK: Search results
                if !vm.searchResults.isEmpty {
                    searchResultsList
                }

                // MARK: Bottom controls
                bottomControls
            }
        }
        .navigationTitle("Kakao Map Test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            searchVM.setProvider(isoCountryCode: "KR")
            searchVM.setBiasLocation(vm.center)
        }
        .onChange(of: vm.center.latitude) { _, _ in
            searchVM.setBiasLocation(vm.center)
        }
        .onChange(of: vm.center.longitude) { _, _ in
            searchVM.setBiasLocation(vm.center)
        }
    }

    // MARK: - Subviews

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Native key: \(vm.nativeKeyStatus)", systemImage: "key")
            Label("REST key:   \(vm.restKeyStatus)", systemImage: "network")
        }
        .font(.caption.monospaced())
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func tapResultBanner(name: String) -> some View {
        HStack {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.red)
            Text(name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private var geocodingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Reverse geocoding…")
                .font(.subheadline)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private var searchResultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(vm.searchResults, id: \.id) { place in
                    Button {
                        vm.selectPlace(place)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.place_name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(place.displaySubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(place.category_group_code)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    Divider().padding(.leading, 16)
                }
            }
        }
        .frame(maxHeight: 220)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private var bottomControls: some View {
        VStack(spacing: 8) {
            // Search field
            HStack(spacing: 8) {
                TextField("Search in Korean (e.g. 경복궁)", text: $vm.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { vm.search() }

                Button {
                    vm.search()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 36, height: 36)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(vm.isSearching)
            }

            // Zoom buttons
            HStack(spacing: 12) {
                Button {
                    vm.zoomInTrigger += 1
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    vm.zoomOutTrigger += 1
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            // Reset pin to Seoul center
            Button("Reset to Gyeongbokgung") {
                vm.center = CLLocationCoordinate2D(latitude: 37.5796, longitude: 126.9770)
                vm.lastTapName = "경복궁 (Gyeongbokgung Palace)"
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 16)
    }
}

#Preview {
    NavigationStack {
        KakaoMapTestView()
    }
}
