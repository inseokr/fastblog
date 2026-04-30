//
//  VoiceMemoRecorderSheet.swift
//  fastblog
//
//  Half-sheet that lets the user record, review, and save a single voice memo
//  for the in-app camera capture currently shown in the post-capture preview.
//
//  Three internal states drive the UI:
//    .idle      – no recording yet, big record button.
//    .recording – live waveform + counter; tap to stop.
//    .preview   – playback of just-recorded clip, with Re-record / Save / Cancel.
//
//  When `existingMemoURL` is non-nil the sheet starts in .preview so the user
//  can play, replace, or delete an existing memo.
//

import AVFoundation
import SwiftUI
import UIKit

struct VoiceMemoRecorderSheet: View {
    /// File URL of an existing voice memo for this capture, if any. When non-nil the sheet
    /// starts in `.preview` mode and `Save` will replace the existing memo.
    let existingMemoURL: URL?
    /// Called with the temp file URL of the recording to persist. The sheet copies the
    /// file out before dismissing so the recorder may delete its temp afterward.
    var onSave: (URL) -> Void
    /// Called when the user explicitly removes a previously-saved memo.
    var onDelete: () -> Void
    /// Called when the user dismisses without committing changes (drag, Cancel, swipe-down).
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var recorder = VoiceMemoRecorder()
    @StateObject private var player = VibePlayer()

    private enum Mode { case idle, recording, preview }
    @State private var mode: Mode = .idle
    @State private var stagedURL: URL?
    @State private var didCommit = false
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 18)
                .padding(.bottom, 8)

            ZStack {
                switch mode {
                case .idle:
                    idleContent
                case .recording:
                    recordingContent
                case .preview:
                    previewContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            recorder.refreshMicrophoneAuthorizationState()
            if let url = existingMemoURL {
                stagedURL = url
                mode = .preview
            } else {
                mode = .idle
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // User may have toggled microphone access in Settings.
            recorder.refreshMicrophoneAuthorizationState()
        }
        .onDisappear {
            // Ensure we don't leave a recorder running or a player attached if the user swipes away.
            if recorder.isRecording { recorder.stop() }
            player.stop()
            if !didCommit, let url = stagedURL, url != existingMemoURL {
                try? FileManager.default.removeItem(at: url)
            }
            if !didCommit {
                onCancel()
            }
        }
        .alert("Delete this voice memo?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                player.stop()
                didCommit = true
                onDelete()
                dismiss()
            }
        } message: {
            Text("The recording will be removed from this photo.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 4)
                .padding(.bottom, 10)
            Text(headerTitle)
                .font(.headline)
                .foregroundColor(.white)
            Text(headerSubtitle)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var headerTitle: String {
        switch mode {
        case .idle:      return "Voice Memo"
        case .recording: return "Recording…"
        case .preview:   return "Voice Memo"
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .idle:      return "Record a short story for this photo. Up to \(Int(VoiceMemoRecorder.maxDuration))s."
        case .recording: return "Tap stop when you're done."
        case .preview:   return "Play to review, or save to attach it to this photo."
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: 24) {
            counterText("00:00 / \(format(VoiceMemoRecorder.maxDuration))")
                .opacity(0.45)

            recordToggleButton(isRecording: false)
            Text("Tap to start")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))

            if recorder.permissionDenied {
                VStack(spacing: 12) {
                    Text("Microphone access is turned off for Bloggo. Turn it on in Settings to record a voice memo.")
                        .font(.footnote)
                        .foregroundColor(.orange.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    Button {
                        openAppSettingsForMicrophone()
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Recording

    private var recordingContent: some View {
        VStack(spacing: 22) {
            counterText("\(format(recorder.elapsed)) / \(format(VoiceMemoRecorder.maxDuration))")

            if recorder.isRecording {
                // Matches in-app camera Vibe — visibly “recording” whenever audio is actually capturing.
                AtmosphericWaveformView(isActive: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityHidden(true)
            } else if !recorder.permissionDenied {
                ProgressView()
                    .tint(.cyan)
                    .scaleEffect(1.05)
                    .padding(.vertical, 14)
                    .accessibilityLabel("Preparing microphone")
            }

            if recorder.isRecording {
                LiveMeterWaveformView(level: recorder.meterLevel, meterTick: recorder.meterTick)
                    .frame(height: 76)
                    .padding(.horizontal, 18)
            }

            if recorder.permissionDenied {
                VStack(spacing: 10) {
                    Text("Microphone access is turned off. Enable it for Bloggo in Settings, then tap record again.")
                        .font(.footnote)
                        .foregroundColor(.orange.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    Button {
                        openAppSettingsForMicrophone()
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.92), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            recordToggleButton(isRecording: true)
            Text("Tap to stop")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .animation(.easeInOut(duration: 0.2), value: recorder.meterTick)
        .onChange(of: recorder.permissionDenied) { _, denied in
            // e.g. user denied the system prompt while this sheet showed the “recording” chrome.
            guard denied, mode == .recording else { return }
            mode = .idle
        }
    }

    // MARK: - Preview

    private var previewContent: some View {
        VStack(spacing: 22) {
            counterText(stagedURL.flatMap(durationLabel) ?? "—")

            HStack(spacing: 28) {
                Button {
                    if player.isPlaying {
                        player.stop()
                    } else if let url = stagedURL {
                        player.play(url: url)
                    }
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, Color.white.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        )
                }
                .accessibilityLabel(player.isPlaying ? "Pause voice memo" : "Play voice memo")
            }

            HStack(spacing: 14) {
                Button {
                    player.stop()
                    if let url = stagedURL, url != existingMemoURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                    stagedURL = nil
                    mode = .idle
                } label: {
                    Label("Re-record", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                if existingMemoURL != nil {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Footer (Cancel / Save)

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                player.stop()
                if recorder.isRecording { recorder.stop() }
                if let url = stagedURL, url != existingMemoURL {
                    try? FileManager.default.removeItem(at: url)
                }
                onCancel()
                didCommit = true
                dismiss()
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button {
                guard let url = stagedURL else { return }
                player.stop()
                didCommit = true
                onSave(url)
                dismiss()
            } label: {
                Text(existingMemoURL != nil ? "Replace" : "Save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(stagedURL == nil ? Color.blue.opacity(0.4) : Color.blue, in: RoundedRectangle(cornerRadius: 12))
            .disabled(stagedURL == nil)
        }
    }

    // MARK: - Components

    private func recordToggleButton(isRecording: Bool) -> some View {
        Button {
            if isRecording {
                recorder.stop()
                if let url = recorder.lastRecordingURL {
                    stagedURL = url
                    recorder.clearSavedReference()
                    mode = .preview
                } else {
                    mode = .idle
                }
            } else {
                stagedURL = nil
                Task { @MainActor in
                    let began = await recorder.attemptStartRecording()
                    if began {
                        mode = .recording
                    }
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 96, height: 96)
                if isRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red)
                        .frame(width: 36, height: 36)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)
                }
            }
        }
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }

    private func counterText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundColor(.white)
    }

    // MARK: - Helpers

    private func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func durationLabel(for url: URL) -> String? {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else { return nil }
        return format(duration)
    }

    private func openAppSettingsForMicrophone() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Live waveform meter

/// Tiny rolling-bars waveform driven by the recorder's normalized average power level.
/// Keeps a short history so the bars feel alive even when the voice goes quiet.
private struct LiveMeterWaveformView: View {
    let level: Float
    let meterTick: UInt

    /// Rolling bar peaks — CGFloat so layout math stays in one numeric type.
    @State private var samples: [CGFloat] = Array(repeating: 0.14, count: 36)

    var body: some View {
        GeometryReader { geo in
            let slot = max(3, (geo.size.width - CGFloat(samples.count - 1) * 4) / CGFloat(samples.count))

            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.06))

                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [.cyan, .green],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: slot, height: barHeight(for: value, geo: geo))
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        /// `meterTick` advances every metering interval (~10 Hz) regardless of whether `level` repeats,
        /// so scrolling bars never “freeze” during silence (the old `onChange(level)`‑only wiring did).
        .onChange(of: meterTick) { _, _ in
            pushSample()
        }
        .onAppear {
            pushSample()
        }
    }

    private func pushSample() {
        guard samples.count >= 4 else { return }
        samples.removeFirst()
        // Perceptual boost for quiet speech; minimum travel keeps scrolling visible.
        let n = CGFloat(max(0, min(1, level)))
        let shaped = sqrt(n) // lift low RMS values without blowing out loud passages
        // Gentle traveling modulation so visually active during sustained silence (no metering change).
        let phase = CGFloat(meterTick % 240)
        let ripple = CGFloat(1 + 0.1 * sin(Double(phase) * 0.35))
        let next = max(0.09, shaped * ripple)
        samples.append(min(1, next))
    }

    private func barHeight(for value: CGFloat, geo: GeometryProxy) -> CGFloat {
        max(6, min(geo.size.height * 0.96, geo.size.height * value))
    }
}
