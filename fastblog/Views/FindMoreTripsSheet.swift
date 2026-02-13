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
    
    @State private var chatInput: String = ""
    @FocusState private var isInputFocused: Bool
    
    // Auto-scroll to bottom of chat
    @Namespace private var bottomID

    var body: some View {
        ZStack {
            sheetBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                
                // Main Content (Manual Controls)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        titleSection
                        yearSection
                        monthRangeSection
                        citiesVisitedSection
                        emptyResultSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                
                // Chat Interface
                VStack(spacing: 0) {
                    Divider().background(Color.white.opacity(0.1))
                    
                    if !viewModel.chatMessages.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(viewModel.chatMessages) { msg in
                                        ChatBubble(message: msg) { chip in
                                            submitSuggestion(chip)
                                        }
                                    }
                                    Spacer().frame(height: 1).id(bottomID)
                                }
                                .padding(16)
                            }
                            .frame(maxHeight: 250) // Limit chat height so controls stay visible
                            .onChange(of: viewModel.chatMessages) { _ in
                                withAnimation {
                                    proxy.scrollTo(bottomID, anchor: .bottom)
                                }
                            }
                        }
                    } else {
                        // Empty state hints
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                suggestionChip("Show trips from March 2025")
                                suggestionChip("My Korea trip")
                                suggestionChip("Last Summer")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    
                    
                    
                    // Scan Button (Fixed above input)
                    Button {
                        viewModel.scanFindMoreTripsInRange()
                    } label: {
                        Text("Scan Trips from Range")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .background(Color(red: 0, green: 122/255, blue: 1))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    
                    // Input Bar
                    HStack(spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            TextField("Ask questions to find your trips", text: $chatInput)
                                .focused($isInputFocused)
                                .submitLabel(.send)
                                .onSubmit {
                                    submit()
                                }
                                .foregroundColor(.black)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color.white)
                        .cornerRadius(20)
                        
                        Button {
                            submit()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(chatInput.isEmpty ? .gray : .blue)
                        }
                        .disabled(chatInput.isEmpty)
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.2))
                }
            }

            if viewModel.isFindMoreScanning || viewModel.isAgentScanning {
                loadingOverlay
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.findMoreScanResult) { _, result in
            if case .success = result {
                viewModel.dismissFindMoreSheet()
            }
        }
        .onChange(of: viewModel.findMoreYear) { _, _ in viewModel.loadFindMoreCities() }
        .onChange(of: viewModel.findMoreStartMonth) { _, _ in viewModel.loadFindMoreCities() }
        .onChange(of: viewModel.findMoreEndMonth) { _, _ in viewModel.loadFindMoreCities() }
    }
    
    private func submit() {
        guard !chatInput.isEmpty else { return }
        viewModel.submitChatMessage(chatInput)
        chatInput = ""
        isInputFocused = false
    }
    
    private func submitSuggestion(_ text: String) {
        viewModel.submitChatMessage(text)
    }
    
    private func suggestionChip(_ text: String) -> some View {
        Button {
            submitSuggestion(text)
        } label: {
            Text(text)
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .cornerRadius(16)
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
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
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
                Text("No photos with location in this range.")
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
            Text("Month range")
                .font(.subheadline)
                .foregroundColor(.white)
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

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Text(viewModel.isAgentScanning ? "Analyzing Library..." : "Scanning Photos...")
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

// MARK: - Chat Components

struct ChatBubble: View {
    let message: TripsViewModel.ChatMessage
    let onChipTap: (String) -> Void
    
    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
            HStack {
                if message.isUser { Spacer() }
                
                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(message.isUser ? .black : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(message.isUser ? Color.white : Color.white.opacity(0.15))
                    .cornerRadius(16)
                    .cornerRadius(message.isUser ? 2 : 16, corners: .bottomRight)
                    .cornerRadius(!message.isUser ? 2 : 16, corners: .bottomLeft)
                
                if !message.isUser { Spacer() }
            }
            
            if !message.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(message.suggestions, id: \.self) { chip in
                            Button {
                                onChipTap(chip)
                            } label: {
                                Text(chip)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.6))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

#Preview {
    FindMoreTripsSheet(viewModel: TripsViewModel(createdRecapStore: CreatedRecapBlogStore.shared))
}
