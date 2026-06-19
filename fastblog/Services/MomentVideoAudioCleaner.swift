//
//  MomentVideoAudioCleaner.swift
//  fastblog
//
//  On-device reel audio cleanup using RNNoise, then remuxes with the original video track.
//

import AVFoundation

enum MomentVideoAudioCleaner {
    enum CleanError: LocalizedError {
        case missingAudioTrack
        case readerSetupFailed
        case writerSetupFailed
        case exportFailed(String)
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .missingAudioTrack: return "This clip has no audio to clean."
            case .readerSetupFailed: return "Couldn’t read the clip audio."
            case .writerSetupFailed: return "Couldn’t write cleaned audio."
            case .exportFailed(let detail): return detail
            case .emptyAudio: return "Audio in this clip is too short to process."
            }
        }
    }

    private static let rnnoiseSampleRate: Double = 48_000

    /// Reduces steady background noise (wind, traffic) on a local reel file. Video is copied; only audio is re-encoded.
    static func cleanVideo(at sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CleanError.missingAudioTrack
        }

        let timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        let samples = try await readMonoSamples(from: asset, track: audioTrack, timeRange: timeRange)
        guard !samples.isEmpty else { throw CleanError.emptyAudio }

        let cleaned = RNNoiseSampleProcessor.denoise(samples: samples)
        let cleanedAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("moment_clean_audio_\(UUID().uuidString).caf")
        try? FileManager.default.removeItem(at: cleanedAudioURL)
        try writePCM(from: cleaned, to: cleanedAudioURL)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("moment_clean_video_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)
        try await muxVideo(from: sourceURL, cleanedAudioURL: cleanedAudioURL, to: outputURL)
        try? FileManager.default.removeItem(at: cleanedAudioURL)
        return outputURL
    }

    // MARK: - Read

    private static func readMonoSamples(from asset: AVAsset, track: AVAssetTrack, timeRange: CMTimeRange) async throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: rnnoiseSampleRate,
            AVNumberOfChannelsKey: 1
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw CleanError.readerSetupFailed }
        reader.add(output)
        guard reader.startReading() else {
            throw CleanError.readerSetupFailed
        }

        var samples: [Float] = []
        samples.reserveCapacity(48_000 * 30)

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { break }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            ) == kCMBlockBufferNoErr, let dataPointer else { continue }

            let floatCount = length / MemoryLayout<Float>.size
            dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { ptr in
                samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: floatCount))
            }
        }

        if reader.status == .failed {
            throw reader.error ?? CleanError.readerSetupFailed
        }
        return samples
    }

    // MARK: - Write PCM

    private static func writePCM(from samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rnnoiseSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw CleanError.writerSetupFailed
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw CleanError.writerSetupFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let dst = buffer.floatChannelData?[0] else {
            throw CleanError.writerSetupFailed
        }
        samples.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            dst.update(from: base, count: samples.count)
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: true
        )
        try file.write(from: buffer)
    }

    // MARK: - Mux

    private static func muxVideo(from sourceURL: URL, cleanedAudioURL: URL, to outputURL: URL) async throws {
        let videoAsset = AVURLAsset(url: sourceURL)
        let audioAsset = AVURLAsset(url: cleanedAudioURL)
        let duration = try await videoAsset.load(.duration)

        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let cleanedAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw CleanError.missingAudioTrack
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw CleanError.exportFailed("Couldn’t compose cleaned clip.")
        }

        let fullRange = CMTimeRange(start: .zero, duration: duration)
        try videoTrack.insertTimeRange(fullRange, of: sourceVideoTrack, at: .zero)
        let cleanedDuration = try await audioAsset.load(.duration)
        let audioRange = CMTimeRange(start: .zero, duration: min(cleanedDuration, duration))
        try audioTrack.insertTimeRange(audioRange, of: cleanedAudioTrack, at: .zero)
        videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw CleanError.exportFailed("Couldn’t start export.")
        }
        export.outputURL = outputURL
        export.outputFileType = .mov
        export.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously {
                continuation.resume()
            }
        }

        guard export.status == .completed else {
            throw CleanError.exportFailed(export.error?.localizedDescription ?? "Export failed.")
        }
    }
}

// MARK: - RNNoise

enum RNNoiseSampleProcessor {
    static func denoise(samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        guard let state = rnnoise_create(nil) else { return samples }
        defer { rnnoise_destroy(state) }

        let frameSize = Int(rnnoise_get_frame_size())
        guard frameSize > 0 else { return samples }

        var output = samples
        var frameIn = [Float](repeating: 0, count: frameSize)
        var frameOut = [Float](repeating: 0, count: frameSize)

        var index = 0
        while index < output.count {
            let remaining = output.count - index
            let count = min(frameSize, remaining)
            for i in 0..<frameSize {
                frameIn[i] = i < count ? output[index + i] : 0
            }
            rnnoise_process_frame(state, &frameOut, frameIn)
            for i in 0..<count {
                output[index + i] = frameOut[i]
            }
            index += frameSize
        }
        return output
    }
}
