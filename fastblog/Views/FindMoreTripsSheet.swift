//
//  FindMoreTripsSheet.swift
//  Capper
//
//  Layout: Start (Month | Year) and End (Month | Year) in a 2-column grid.
//  If End is before Start within the same year, Start month is auto-clamped to End month.
//

import Photos
import SwiftUI

private let sheetBackground = Color(red: 5/255, green: 10/255, blue: 48/255)
private let chatInputBackground = Color(red: 30/255, green: 35/255, blue: 73/255) // 10% lighter than sheetBackground

struct FindMoreTripsSheet: View {
    @ObservedObject var viewModel: TripsViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var photoAuth = PhotosAuthorizationManager()

    private let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private let years: [Int] = (2018...2027).reversed()
    
    // Chat Placeholders
    @State private var placeholderIndex = 0
    private let chatPlaceholders = ["\"last summer\"", "\"Spring 2024\"", "\"Korea trip last year\"", "\"Did I go to Korea last year?\""]
    let timer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

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
                LoadingScanView(
                    message: "Finding trips…",
                    isOverlay: true,
                    progress: viewModel.findMoreScanProgress,
                    onCancel: { viewModel.cancelFindMoreScan() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.isFindMoreScanning)
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.findMoreScanResult) { _, result in
            if case .success = result {
                viewModel.dismissFindMoreSheet()
            }
        }
    }

    // MARK: – Header

    private var header: some View {
        HStack {
            Button {
                viewModel.dismissFindMoreSheet()
                dismiss()
            } label: {
                Text("Close")
                    .font(.body.weight(.bold))
                    .foregroundColor(Color(white: 0.7))
            }
            Spacer()
        }
        .padding(.top, 36)
        .padding(.bottom, 24)
    }

    // MARK: – Main content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                titleSection
                limitedWarningSection  // Trigger 2: shown only when status is .limited
                dateRangeSection
                emptyResultSection
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find your trips!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }

    // MARK: – Limited Access Warning (Trigger 2)

    @ViewBuilder
    private var limitedWarningSection: some View {
        if photoAuth.status == .limited {
            HStack(spacing: 12) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title3)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text(photoAuth.selectedPhotoCount > 0
                         ? "Only \(photoAuth.selectedPhotoCount) photos available"
                         : "Limited photo access")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("Scans are limited to your selected photos.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer()

                Button {
                    presentLimitedPickerFromSheet()
                } label: {
                    Text("Add Photos")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(chatInputBackground)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1))
            )
        }
    }

    private func presentLimitedPickerFromSheet() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else { return }
        let photoCountBeforePicker = photoAuth.selectedPhotoCount
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController) { _ in
            DispatchQueue.main.async {
                photoAuth.refreshStatus()
                guard photoAuth.selectedPhotoCount != photoCountBeforePicker else { return }
                viewModel.scanFindMoreTripsInRange()
            }
        }
    }

    // MARK: – Chat Section
    
    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundColor(Color(red: 0, green: 122/255, blue: 1)) // App Blue
                    .font(.body.weight(.semibold))
                
                TextField(chatPlaceholders[placeholderIndex], text: $viewModel.findMoreChatInput)
                    .font(.body)
                    .foregroundColor(.white)
                    .submitLabel(.search)
                    .onSubmit {
                        viewModel.submitFindMoreChat()
                    }
                
                if viewModel.isParsingChat {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if !viewModel.findMoreChatInput.isEmpty {
                    Button {
                        viewModel.findMoreChatInput = ""
                        viewModel.cancelPendingParse()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding()
            .background(chatInputBackground)
            .cornerRadius(12)
            .onReceive(timer) { _ in
                if viewModel.findMoreChatInput.isEmpty {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        placeholderIndex = (placeholderIndex + 1) % chatPlaceholders.count
                    }
                }
            }
            
            if let response = viewModel.findMoreChatResponse {
                HStack(alignment: .top) {
                    Text(response)
                        .font(.footnote)
                        .foregroundColor(Color(red: 0, green: 122/255, blue: 1)) // Blue text for AI response
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                    
                    if viewModel.needsConfirmationForParse {
                        Button("Confirm") {
                            viewModel.confirmPendingParse()
                        }
                        .font(.footnote.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0, green: 122/255, blue: 1))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
    }

    // MARK: – Start / End pickers

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            dateBlock(label: "Start",
                      month: $viewModel.findMoreStartMonth,
                      year: $viewModel.findMoreStartYear)
            dateBlock(label: "End",
                      month: $viewModel.findMoreEndMonth,
                      year: $viewModel.findMoreEndYear)

            if !viewModel.isDateRangeValid {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.footnote)
                    Text("End cannot be before Start.")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    /// Full-width date block: label on top, Month and Year pickers side-by-side on one row.
    private func dateBlock(label: String, month: Binding<Int>, year: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.7))
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 12) {
                Picker("Year", selection: year) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

                Picker("Month", selection: month) {
                    ForEach(1...12, id: \.self) { m in
                        Text(monthNames[m - 1]).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }


    // MARK: – Empty result

    @ViewBuilder
    private var emptyResultSection: some View {
        if viewModel.findMoreScanResult == .empty {
            VStack(spacing: 16) {
                Image(systemName: "map")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.35))

                Text("No trips found in this range")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Try scanning a different date range")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    // MARK: – CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                AppAnalytics.track(.blogScan)
                viewModel.scanFindMoreTripsInRange()
            } label: {
                Text("Find Trips")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .background(Color(red: 0, green: 122/255, blue: 1)
                .opacity(viewModel.isDateRangeValid ? 1 : 0.4))
            .cornerRadius(12)
            .disabled(viewModel.isFindMoreScanning || !viewModel.isDateRangeValid)
        }
        .padding(.bottom, 28)
    }

}

#Preview {
    FindMoreTripsSheet(viewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared))
}
