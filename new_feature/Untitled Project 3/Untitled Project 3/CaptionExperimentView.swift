//
//  CaptionExperimentView.swift
//  KS2-13 standalone experiment — minimal SwiftUI harness (with metadata)
//
//  Self-contained UI to run CaptionExperiment.swift. No Bloggo/Capper dependency.
//  Picks photos via the Photos library so it can read capture time + GPS (PhotosPicker's Data
//  path strips location, so we resolve each pick to a PHAsset via its localIdentifier).
//
//  Info.plist REQUIRED: add `NSPhotoLibraryUsageDescription` (any string) or the picker/asset
//  fetch will fail. First run will prompt for Photos access.
//

import SwiftUI
import PhotosUI
import Photos

struct CaptionExperimentView: View {
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var samples: [PhotoSample] = []
    @State private var rows: [CaptionExperimentRunner.Row] = []
    @State private var isRunning = false
    @State private var isLoading = false
    @State private var repeats = 5
    @State private var status = ""
    @State private var selected: Set<Int> = []   // indices of samples chosen to run
    // Which caption paths to run (⑤ off by default — needs PCC entitlement).
    @State private var enabledPaths: Set<CaptionPath> = [.existing, .existingImproved, .newTech, .mapRich]
    @State private var dnaSource: CaptionPath = .newTech   // which path's captions feed Travel DNA

    var body: some View {
        NavigationStack {
            Form {
                Section("1. Photo set") {
                    // Option B (recommended for a fixed experiment set): load the 19 photos you
                    // added as a "TestPhotos" folder reference in the project bundle. EXIF/GPS kept.
                    Button {
                        Task { await loadBundledSamples() }
                    } label: {
                        Label("Load bundled TestPhotos", systemImage: "folder")
                    }

                    // Option A: pick from the device Photos library (reads time + GPS via PHAsset).
                    // photoLibrary: .shared() makes item.itemIdentifier == PHAsset localIdentifier.
                    PhotosPicker(selection: $pickerItems,
                                 maxSelectionCount: 20,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        Label("…or pick from Photos library", systemImage: "photo.on.rectangle")
                    }
                    if isLoading { ProgressView("Reading metadata…") }
                    if !status.isEmpty {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                    if !samples.isEmpty {
                        HStack {
                            Text("Selected \(selected.count) / \(samples.count)")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("All") { selected = Set(samples.indices) }.font(.caption)
                            Button("None") { selected.removeAll() }.font(.caption)
                        }
                    }
                    ForEach(Array(samples.enumerated()), id: \.offset) { idx, s in
                        Button {
                            if selected.contains(idx) { selected.remove(idx) } else { selected.insert(idx) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selected.contains(idx) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(idx) ? Color.accentColor : Color.secondary)
                                Image(uiImage: s.image).resizable().scaledToFill()
                                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.meta.placeName ?? "No location").font(.caption)
                                    Text(s.meta.promptContext().isEmpty ? "No metadata" : s.meta.promptContext())
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("2. Paths to run") {
                    ForEach(CaptionPath.allCases, id: \.self) { p in
                        Toggle(p.label, isOn: Binding(
                            get: { enabledPaths.contains(p) },
                            set: { on in if on { enabledPaths.insert(p) } else { enabledPaths.remove(p) } }
                        ))
                        .font(.subheadline)
                    }
                    Text("⑤ PCC needs the private-cloud-compute entitlement; leave off unless enabled.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("3. Repeats per image (time averaging)") {
                    Stepper("Repeats: \(repeats)", value: $repeats, in: 1...20)
                }

                Section {
                    Button {
                        Task { await run() }
                    } label: {
                        HStack {
                            Text(isRunning ? "Running…" : "Run (\(runCount) photos × \(enabledPaths.count) paths)")
                            if isRunning { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(samples.isEmpty || isRunning || enabledPaths.isEmpty)
                }

                if !rows.isEmpty {
                    Section("4. Travel DNA") {
                        Picker("Source captions", selection: $dnaSource) {
                            ForEach(Array(enabledPaths).sorted { $0.rawValue < $1.rawValue }, id: \.self) { p in
                                Text(p.label).tag(p)
                            }
                        }
                        NavigationLink {
                            TravelDNAView(captions: dnaCaptions, useLLM: true)
                        } label: {
                            Label("Build Travel DNA from \(dnaSource.label)", systemImage: "person.text.rectangle")
                        }
                        .disabled(dnaCaptions.isEmpty)
                    }

                    Section("5. Results") {
                        ForEach(rows, id: \.index) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Photo #\(r.index)").font(.headline)
                                labelRow("① Existing", r.existing)
                                labelRow("② Improved", r.improved)
                                labelRow("③ New (iOS 27)", r.newTech)
                                labelRow("④ Map + Photo", r.mapRich)
                                labelRow("⑤ PCC + lat/lng", r.pcc)
                            }
                            .padding(.vertical, 4)
                        }
                        let eAvg = rows.map { $0.existing.elapsedMs }.reduce(0,+)/Double(rows.count)
                        let iAvg = rows.map { $0.improved.elapsedMs }.reduce(0,+)/Double(rows.count)
                        let nAvg = rows.map { $0.newTech.elapsedMs }.reduce(0,+)/Double(rows.count)
                        let mAvg = rows.map { $0.mapRich.elapsedMs }.reduce(0,+)/Double(rows.count)
                        let pAvg = rows.map { $0.pcc.elapsedMs }.reduce(0,+)/Double(rows.count)
                        Text(String(format: "AVG — ① %.0f · ② %.0f · ③ %.0f · ④ %.0f · ⑤ %.0f ms", eAvg, iAvg, nAvg, mAvg, pAvg))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Caption Experiment")
            .onChange(of: pickerItems) { _, items in
                Task { await loadSamples(items) }
            }
        }
    }

    @ViewBuilder
    private func labelRow(_ name: String, _ r: CaptionResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(name) · \(String(format: "%.1f ms", r.elapsedMs))")
                .font(.caption).foregroundStyle(.secondary)
            Text(r.caption.isEmpty ? "— (\(r.detail))" : r.caption)
                .font(.callout)
        }
    }

    /// Resolve each picked item to a PHAsset → load image + read time/GPS → build PhotoSample.
    private func loadSamples(_ items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }
        rows = []

        // Ensure Photos permission (needed to fetch PHAsset + location).
        let status = await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { cont.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else {
            samples = []
            return
        }

        var loaded: [PhotoSample] = []
        for item in items {
            guard let localId = item.itemIdentifier,
                  let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil).firstObject
            else { continue }

            guard let image = await requestImage(for: asset) else { continue }
            let meta = await PhotoMetadataService.extract(from: asset, reverseGeocode: true)
            loaded.append(PhotoSample(image: image, meta: meta))
        }
        samples = loaded
        selected = Set(loaded.indices)   // default: all selected (tap to deselect)
    }

    /// Option B: load a fixed photo set from a "TestPhotos" folder reference in the app bundle.
    /// EXIF/GPS is read from each file (Asset Catalog would strip it — use a FOLDER REFERENCE).
    private func loadBundledSamples(folder: String = "TestPhotos") async {
        isLoading = true
        defer { isLoading = false }
        rows = []

        let exts = Set(["jpg", "jpeg", "png", "heic"])
        var urls: [URL] = []

        // Case 1: a named folder reference (blue), e.g. "TestPhotos" or "Archive".
        for e in exts {
            urls += Bundle.main.urls(forResourcesWithExtension: e, subdirectory: folder) ?? []
        }
        // Case 2 (robust): scan the WHOLE app bundle recursively — works for ANY folder name
        // (Archive, TestPhotos, …) and for flattened groups. Ignores case on the extension.
        if urls.isEmpty, let resourceURL = Bundle.main.resourceURL,
           let en = FileManager.default.enumerator(at: resourceURL,
                                                    includingPropertiesForKeys: nil) {
            for case let f as URL in en where exts.contains(f.pathExtension.lowercased()) {
                urls.append(f)
            }
        }
        // De-duplicate and sort by filename.
        urls = Array(Set(urls))
        urls.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        print("[CaptionLab] bundled URLs found: \(urls.count)")
        if urls.isEmpty {
            status = "0 photos in bundle — check the folder is in the app target (Copy Bundle Resources)."
            samples = []
            return
        }

        var loaded: [PhotoSample] = []
        for url in urls {
            guard let img = UIImage(contentsOfFile: url.path) else { continue }
            let meta = await PhotoMetadataService.extract(fromFileURL: url, reverseGeocode: true)
            loaded.append(PhotoSample(image: img, meta: meta))
        }
        samples = loaded
        selected = Set(loaded.indices)   // default: all selected (tap to deselect)
        status = "Loaded \(loaded.count) photos from bundle"
    }

    private func requestImage(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        return await withCheckedContinuation { cont in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 1024, height: 1024),
                contentMode: .aspectFit, options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                if !resumed { resumed = true; cont.resume(returning: image) }
            }
        }
    }

    /// How many photos the Run button will process (selected, or all if none selected).
    private var runCount: Int { selected.isEmpty ? samples.count : selected.count }

    /// Captions from the chosen path, for Travel DNA (non-empty only).
    private var dnaCaptions: [String] {
        rows.compactMap { row in
            let c = caption(row, dnaSource)
            return c.isEmpty ? nil : c
        }
    }

    private func caption(_ row: CaptionExperimentRunner.Row, _ p: CaptionPath) -> String {
        switch p {
        case .existing:         return row.existing.caption
        case .existingImproved: return row.improved.caption
        case .newTech:          return row.newTech.caption
        case .mapRich:          return row.mapRich.caption
        case .pcc:              return row.pcc.caption
        }
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        // Run only the selected photos; if none are selected, run all.
        let chosen = samples.enumerated()
            .filter { selected.contains($0.offset) }
            .map { $0.element }
        let toRun = chosen.isEmpty ? samples : chosen
        // Make sure the DNA source is one of the paths we actually ran.
        if !enabledPaths.contains(dnaSource), let first = enabledPaths.sorted(by: { $0.rawValue < $1.rawValue }).first {
            dnaSource = first
        }
        rows = await CaptionExperimentRunner.run(samples: toRun, repeats: repeats, paths: enabledPaths)
    }
}

#Preview {
    CaptionExperimentView()
}
