//
//  FindMoreTripsSheet.swift
//  Capper
//
//  Flow: Year first, then month range. Country summary updates on year change (instant mock).
//  Scan only when user taps "Scan For New Blogs"; loading shown in sheet; empty result stays in sheet.
//

import SwiftUI

private let sheetBackground = Color(red: 5/255, green: 10/255, blue: 48/255)

struct FindMoreTripsSheet: View {
    @ObservedObject var viewModel: TripsViewModel
    @Environment(\.dismiss) private var dismiss

    private let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private let years: [Int] = (2022...2027).reversed()

    var body: some View {
        ZStack {
            sheetBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                content
                Spacer(minLength: 20)
                ctaSection
            }
            .padding(.horizontal, 20)

            if viewModel.isFindMoreScanning {
                loadingOverlay
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.findMoreScanResult) { _, result in
            if case .success = result {
                viewModel.dismissFindMoreSheet()
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                viewModel.dismissFindMoreSheet()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body)
                    .foregroundColor(Color(white: 0.7))
            }
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                titleSection
                yearSection
                monthRangeSection
                citiesVisitedSection
                emptyResultSection
            }
        }
        .onChange(of: viewModel.findMoreYear) { _, _ in viewModel.loadFindMoreCities() }
        .onChange(of: viewModel.findMoreStartMonth) { _, _ in viewModel.loadFindMoreCities() }
        .onChange(of: viewModel.findMoreEndMonth) { _, _ in viewModel.loadFindMoreCities() }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find your blogs!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text("Where would you like to go?")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.bottom, 8)
    }

    private var yearSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Year")
                .font(.subheadline)
                .foregroundColor(.white)
            Picker("Year", selection: $viewModel.findMoreYear) {
                ForEach(years, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .padding()
            .background(Color.white.opacity(0.12))
            .cornerRadius(12)
        }
    }

    /// Cities visited in the selected year and month range. Updates when year or month range changes.
    private var citiesVisitedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cities Visited")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            if viewModel.findMoreCitiesLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Loading cities…")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.vertical, 12)
            } else if viewModel.findMoreCities.isEmpty {
                Text("No photos with location in this range, or set your neighborhood in Settings to filter local photos.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                Text(viewModel.findMoreCities.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }

    private var monthRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Picker("Start", selection: $viewModel.findMoreStartMonth) {
                        ForEach(1...12, id: \.self) { m in
                            Text(monthNames[m - 1]).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(12)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("End")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Picker("End", selection: $viewModel.findMoreEndMonth) {
                        ForEach(1...12, id: \.self) { m in
                            Text(monthNames[m - 1]).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(12)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyResultSection: some View {
        if viewModel.findMoreScanResult == .empty {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                Text("No new trips found for this range.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.1))
            .cornerRadius(10)
            .padding(.top, 16)
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.scanFindMoreTripsInRange()
            } label: {
                Text("Scan For New Blogs")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .background(Color(red: 0, green: 122/255, blue: 1))
            .cornerRadius(12)
            .disabled(viewModel.isFindMoreScanning)
        }
        .padding(.bottom, 28)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Scanning Photos...")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Image("ScanIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
            }
        }
    }
}

#Preview {
    FindMoreTripsSheet(viewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared))
}
