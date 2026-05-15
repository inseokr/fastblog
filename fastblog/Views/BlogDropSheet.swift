//
//  BlogDropSheet.swift
//  fastblog
//
//  Sender sheet: prepares a cloud drop from a saved blog and shows a shareable link.
//  Receiver sheet: accepts a drop URL and imports the blog with all stories intact.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Send Drop

@MainActor
final class BlogDropSendViewModel: ObservableObject {
    enum Phase {
        case idle
        case working(message: String, progress: Double)
        case ready(url: URL)
        case failed(String)
    }

    @Published var phase: Phase = .idle

    func startDrop(from detail: RecapBlogDetail) {
        phase = .working(message: "Preparing drop…", progress: 0)
        Task {
            do {
                let url = try await BlogDropService.shared.createDrop(from: detail) { [weak self] prog in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch prog.phase {
                        case .uploadingPhotos(let done, let total):
                            let frac = total > 0 ? Double(done) / Double(total) * 0.85 : 0
                            self.phase = .working(
                                message: "Uploading photos (\(done)/\(total))…",
                                progress: frac
                            )
                        case .uploadingManifest:
                            self.phase = .working(message: "Finishing drop…", progress: 0.95)
                        default:
                            break
                        }
                    }
                }
                phase = .ready(url: url)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

struct BlogDropSendSheet: View {
    let detail: RecapBlogDetail
    @StateObject private var vm = BlogDropSendViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var didCopy = false
    @State private var shareURL: URL? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                content
            }
            .navigationTitle("Blog Drop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let u = shareURL { ShareSheet(items: [u]) }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { vm.startDrop(from: detail) }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .idle:
            EmptyView()

        case .working(let message, let progress):
            VStack(spacing: 24) {
                ProgressView(value: progress, total: 1)
                    .tint(.white)
                    .frame(maxWidth: 280)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(32)

        case .ready(let url):
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                        Text("Drop Ready")
                            .font(.title2.bold())
                        Text("Share this link with another Bloggo user. They'll get a full copy of \"\(detail.title)\" — including all stories.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 24)

                    if let qr = qrImage(for: url.absoluteString) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(spacing: 12) {
                        Text(url.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = url.absoluteString
                                didCopy = true
                                Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    didCopy = false
                                }
                            } label: {
                                Label(didCopy ? "Copied!" : "Copy Link", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(white: 0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            Button {
                                shareURL = url
                                showShareSheet = true
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(red: 0.04, green: 0.52, blue: 1.0))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
            }

        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("Drop Failed")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Retry") { vm.startDrop(from: detail) }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
            .padding(32)
        }
    }

    private func qrImage(for string: String) -> UIImage? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Receive Drop

@MainActor
final class BlogDropReceiveViewModel: ObservableObject {
    enum Phase {
        case idle
        case working(message: String, progress: Double)
        case success(RecapBlogDetail)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var inputURL: String = ""

    func importDrop(store: CreatedRecapBlogStore) {
        let raw = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw) else {
            phase = .failed("Enter a valid Blog Drop link.")
            return
        }
        phase = .working(message: "Downloading drop…", progress: 0)
        Task {
            do {
                let detail = try await BlogDropService.shared.importDrop(from: url) { [weak self] prog in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch prog.phase {
                        case .downloadingManifest:
                            self.phase = .working(message: "Reading drop…", progress: 0.05)
                        case .downloadingPhotos(let done, let total):
                            let frac = total > 0 ? 0.1 + Double(done) / Double(total) * 0.9 : 0.1
                            self.phase = .working(
                                message: "Downloading photos (\(done)/\(total))…",
                                progress: frac
                            )
                        default:
                            break
                        }
                    }
                }
                store.importBlogDrop(detail)
                phase = .success(detail)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

struct BlogDropReceiveSheet: View {
    @StateObject private var vm = BlogDropReceiveViewModel()
    @EnvironmentObject private var store: CreatedRecapBlogStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                content
            }
            .navigationTitle("Receive a Drop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .idle, .failed:
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                    Text("Paste a Drop Link")
                        .font(.title2.bold())
                    Text("Ask the sender to share their Blog Drop link with you, then paste it below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 48)

                TextField("https://…", text: $vm.inputURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($urlFocused)
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                if case .failed(let msg) = vm.phase {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    urlFocused = false
                    vm.importDrop(store: store)
                } label: {
                    Text("Import Blog")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            vm.inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color(white: 0.25)
                                : Color(red: 0.04, green: 0.52, blue: 1.0)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(vm.inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 16)

        case .working(let message, let progress):
            VStack(spacing: 24) {
                ProgressView(value: progress, total: 1)
                    .tint(.white)
                    .frame(maxWidth: 280)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(32)

        case .success(let detail):
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(red: 0.65, green: 0.95, blue: 0.72))
                Text("Blog Imported!")
                    .font(.title2.bold())
                Text("\"\(detail.title)\" has been added to your blogs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Done") { dismiss() }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.04, green: 0.52, blue: 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            .padding(.top, 80)
        }
    }
}
