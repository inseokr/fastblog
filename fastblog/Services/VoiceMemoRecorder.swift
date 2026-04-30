//
//  VoiceMemoRecorder.swift
//  fastblog
//
//  Records an explicit user voice memo (mic narration attached to a single in-app
//  camera capture). Distinct from `VibeRecorder`: Vibe is passive ambient audio
//  trimmed to the last 10 seconds; a voice memo is an intentional recording with
//  start / stop / cancel controls and a 120-second hard cap.
//

import AVFAudio
import AVFoundation
import Foundation
import UIKit

@MainActor
final class VoiceMemoRecorder: NSObject, ObservableObject {

    /// Hard cap on a single voice memo. Enforced via timer auto-stop.
    static let maxDuration: TimeInterval = 120

    // MARK: - Published state (for SwiftUI)

    /// True while actively capturing audio.
    @Published private(set) var isRecording = false
    /// Seconds elapsed since recording began (updated ~10 Hz).
    @Published private(set) var elapsed: TimeInterval = 0
    /// Most-recent normalized audio level [0…1] from the recorder's average + peak envelope.
    /// See `meterTick`: bars should advance every meter poll even if this value repeats.
    @Published private(set) var meterLevel: Float = 0
    /// Incremented once per metering interval while recording — bind this to waveform views so SwiftUI redraws reliably.
    @Published private(set) var meterTick: UInt = 0
    /// Set after a successful `stop()` (file URL of the saved m4a in the temp directory).
    @Published private(set) var lastRecordingURL: URL?
    /// True when the user has been blocked because microphone access is denied.
    @Published private(set) var permissionDenied = false

    // MARK: - Private

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startedAt: Date?

    // MARK: - Permission

    /// Syncs `permissionDenied` from `AVAudioSession` (`AVAudioApplication` requests align with this state).
    /// Call when the voice-memo sheet appears and when returning from Settings / foreground.
    func refreshMicrophoneAuthorizationState() {
        permissionDenied = (AVAudioSession.sharedInstance().recordPermission == .denied)
    }

    /// Presents the system microphone alert when authorization is `.undetermined`.
    /// After `.denied`, iOS will not show the prompt again — send the user to Settings instead.
    private func requestRecordPermissionPrompt() async -> Bool {
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { ok in
                continuation.resume(returning: ok)
            }
        }
        permissionDenied = !granted
        return granted
    }

    // MARK: - Lifecycle

    /// Resolves microphone authorization (`undetermined` → system prompt → record), configures the session, and starts metering.
    /// Call from an explicit user action (tap). Returns whether recording actually started.
    @discardableResult
    func attemptStartRecording() async -> Bool {
        guard !isRecording else { return true }
        refreshMicrophoneAuthorizationState()

        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            permissionDenied = false
            beginRecording()
            return isRecording

        case .denied:
            permissionDenied = true
            return false

        case .undetermined:
            permissionDenied = false
            let granted = await requestRecordPermissionPrompt()
            guard granted else { return false }
            beginRecording()
            return isRecording

        @unknown default:
            permissionDenied = false
            let granted = await requestRecordPermissionPrompt()
            guard granted else { return false }
            beginRecording()
            return isRecording
        }
    }

    /// Legacy fire-and-forget entry point. Prefer `await attemptStartRecording()` from SwiftUI.
    func start() {
        Task { await attemptStartRecording() }
    }

    /// Stops recording and exposes the resulting file via `lastRecordingURL` for the sheet to save or discard.
    func stop() {
        guard let rec = recorder, rec.isRecording else {
            tearDownTimer()
            return
        }
        let url = rec.url
        rec.stop()
        recorder = nil
        tearDownTimer()
        isRecording = false
        meterLevel = 0
        // The recorder writes header metadata on stop; the file is now usable.
        if FileManager.default.fileExists(atPath: url.path) {
            lastRecordingURL = url
        } else {
            lastRecordingURL = nil
        }
    }

    /// Stops (if recording) and deletes any saved file. Use when the user cancels the sheet
    /// without saving, or after `lastRecordingURL` has been copied into permanent storage.
    func cancelAndDelete() {
        if let rec = recorder {
            let url = rec.url
            if rec.isRecording { rec.stop() }
            recorder = nil
            try? FileManager.default.removeItem(at: url)
        }
        if let saved = lastRecordingURL {
            try? FileManager.default.removeItem(at: saved)
        }
        lastRecordingURL = nil
        tearDownTimer()
        isRecording = false
        elapsed = 0
        meterLevel = 0
        meterTick = 0
    }

    /// Releases the saved file reference without deleting (caller has copied it elsewhere).
    func clearSavedReference() {
        lastRecordingURL = nil
    }

    // MARK: - Internal

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true)
        } catch {
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_memo_\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            rec.isMeteringEnabled = true
            guard rec.record() else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            recorder = rec
            startedAt = Date()
            elapsed = 0
            meterLevel = 0
            meterTick = 0
            isRecording = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            startMeterTimer()
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func startMeterTimer() {
        meterTimer?.invalidate()
        // 10 Hz polling for meters + elapsed; cheap enough and smooth enough for the waveform.
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickMeter()
            }
        }
        if let t = meterTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func tickMeter() {
        guard let rec = recorder, rec.isRecording, let startedAt else { return }
        rec.updateMeters()
        meterTick += 1
        let avgRaw = rec.averagePower(forChannel: 0)
        let peakRaw = rec.peakPower(forChannel: 0)

        func normalizedDb(_ db: Float) -> Float {
            // `-160` = silence/disabled metering; `-50…0` = typical speech band for UI.
            if db <= -160 { return 0.05 }
            let clamped = max(-55, min(db, 0))
            let n = Double(clamped + 55) / 55.0
            return Float(max(0.08, min(1, pow(n, 1.25)))) // perceptual bump so quiet speech still reads
        }

        let avgN = normalizedDb(avgRaw)
        let peakN = normalizedDb(peakRaw)
        // Peak drives syllable edges; average backs sustained vowels — reads better than average alone.
        meterLevel = min(1, avgN * 0.45 + peakN * 0.65)

        elapsed = Date().timeIntervalSince(startedAt)
        if elapsed >= Self.maxDuration {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            stop()
        }
    }

    private func tearDownTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
        startedAt = nil
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceMemoRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.cancelAndDelete()
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // No-op: we trigger publication from `stop()` so the URL is exposed deterministically.
    }
}
