//
//  MomentVideoVolumeAdjuster.swift
//  fastblog
//
//  Exports a reel with scaled audio volume while leaving the video track unchanged.
//

import AVFoundation

enum MomentVideoVolumeAdjuster {
    /// Returns `sourceURL` unchanged at full (original) volume.
    static func export(at sourceURL: URL, volume: Float) async -> URL? {
        guard volume < 0.999 else { return sourceURL }
        guard volume >= 0 else { return nil }

        let asset = AVURLAsset(url: sourceURL)

        let duration: CMTime
        let videoTrack: AVAssetTrack
        do {
            duration = try await asset.load(.duration)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
            videoTrack = track
        } catch {
            return nil
        }

        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard !audioTracks.isEmpty else { return sourceURL }

        let composition = AVMutableComposition()
        let fullRange = CMTimeRange(start: .zero, duration: duration)

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }

        do {
            try compositionVideoTrack.insertTimeRange(fullRange, of: videoTrack, at: .zero)
            compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)
        } catch {
            return nil
        }

        var compositionAudioTracks: [AVCompositionTrack] = []
        for audioTrack in audioTracks {
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            do {
                try compositionAudioTrack.insertTimeRange(fullRange, of: audioTrack, at: .zero)
                compositionAudioTracks.append(compositionAudioTrack)
            } catch {
                continue
            }
        }

        guard !compositionAudioTracks.isEmpty else { return sourceURL }

        let audioMix = audioMix(for: compositionAudioTracks, volume: volume, duration: duration)

        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            return nil
        }

        export.audioMix = audioMix
        export.outputFileType = .mov
        export.shouldOptimizeForNetworkUse = true

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("moment_volume_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outURL)
        export.outputURL = outURL

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously {
                continuation.resume()
            }
        }

        if export.status == .completed {
            return outURL
        }
        try? FileManager.default.removeItem(at: outURL)
        return nil
    }

    /// Applies a constant gain to asset audio tracks during playback preview.
    static func makePreviewMix(for asset: AVAsset, volume: Float) async -> AVAudioMix? {
        guard volume < 0.999 else { return nil }
        guard volume >= 0 else { return nil }

        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard !audioTracks.isEmpty else { return nil }

        let duration = (try? await asset.load(.duration)) ?? .zero
        return audioMix(for: audioTracks, volume: volume, duration: duration)
    }

    private static func audioMix(
        for tracks: [AVAssetTrack],
        volume: Float,
        duration: CMTime
    ) -> AVMutableAudioMix {
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(volume, at: .zero)
            if duration.isValid, duration.seconds > 0 {
                parameters.setVolume(volume, at: duration)
            }
            return parameters
        }
        return mix
    }
}
