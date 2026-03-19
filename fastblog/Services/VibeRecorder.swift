//
//  VibeRecorder.swift
//  fastblog
//
//  Records ambient audio via AVAudioRecorder and trims the final clip to the
//  last 10 seconds when a photo is captured. One recorder per camera session.
//

import AVFoundation
import Foundation

/// Records ambient audio and produces a trimmed m4a clip of at most 10 seconds.
final class VibeRecorder: NSObject, ObservableObject {

    // MARK: - Private state

    private var recorder: AVAudioRecorder?
    private var sessionTempURL: URL?

    // MARK: - Public API

    /// Returns true when recording is actively in progress.
    var isRecording: Bool { recorder?.isRecording == true }

    /// Requests microphone access and begins continuous recording.
    /// No-op if already recording. Silently skips if permission is denied.
    func start() {
        guard recorder == nil else { return }
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.beginRecording() }
        }
    }

    /// Stops the recorder, trims to the last 10 seconds, and returns the
    /// trimmed file URL. Returns nil if nothing was recorded or trimming fails.
    func stopAndTrimLast10Seconds() async -> URL? {
        guard let rec = recorder, rec.isRecording else {
            cancelAndDelete()
            return nil
        }
        let sourceURL = rec.url
        let duration = rec.currentTime
        rec.stop()
        recorder = nil
        // Ensure the shared audio session is not left in record mode.
        try? AVAudioSession.sharedInstance().setActive(false)
        return await trim(sourceURL: sourceURL, totalDuration: duration, maxSeconds: 10)
    }

    /// Stops recording and deletes any temp file.
    /// Call when the camera is dismissed without taking a photo.
    func cancelAndDelete() {
        let url = recorder?.url ?? sessionTempURL
        recorder?.stop()
        recorder = nil
        // Ensure the shared audio session is not left in record mode.
        try? AVAudioSession.sharedInstance().setActive(false)
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        sessionTempURL = nil
    }

    // MARK: - Private

    private func beginRecording() {
        guard recorder == nil else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }

        let url = makeTempURL()
        sessionTempURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            rec.record()
            recorder = rec
        } catch {
            try? FileManager.default.removeItem(at: url)
            sessionTempURL = nil
        }
    }

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vibe_\(UUID().uuidString).m4a")
    }

    /// Trims `sourceURL` so only the last `maxSeconds` are kept.
    private func trim(sourceURL: URL, totalDuration: TimeInterval, maxSeconds: TimeInterval) async -> URL? {
        let asset = AVURLAsset(url: sourceURL)

        let startSeconds = max(0, totalDuration - maxSeconds)
        let startTime = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let endTime   = CMTime(seconds: totalDuration, preferredTimescale: 600)
        let range     = CMTimeRange(start: startTime, end: endTime)

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            try? FileManager.default.removeItem(at: sourceURL)
            return nil
        }

        let outputURL = makeTempURL()
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.timeRange = range
        // Ensure the export fully completes before we return/copy the file.
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }

        // Clean up source regardless of result
        try? FileManager.default.removeItem(at: sourceURL)
        sessionTempURL = nil

        if exporter.status == .completed {
            return outputURL
        } else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension VibeRecorder: AVAudioRecorderDelegate {
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        cancelAndDelete()
    }
}
