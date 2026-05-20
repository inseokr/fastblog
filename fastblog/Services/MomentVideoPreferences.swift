// fastblog/Services/MomentVideoPreferences.swift
import Foundation

/// User preference for the maximum length of in-app **Reel** clips (`moment_video.mov` after capture).
enum MomentVideoPreferences {
    static let userDefaultsKey = "bloggo.camera.momentVideoMaxDurationSeconds"
    static let defaultDurationSeconds: TimeInterval = 5

    /// Allowed reel lengths (seconds). Shown in Settings and enforced at record time.
    static let choices: [TimeInterval] = [3, 5, 7, 10]

    static var maxDurationSeconds: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: userDefaultsKey)
        if stored > 0, choices.contains(stored) { return stored }
        return defaultDurationSeconds
    }

    static func setMaxDurationSeconds(_ seconds: TimeInterval) {
        let resolved = choices.contains(seconds) ? seconds : defaultDurationSeconds
        UserDefaults.standard.set(resolved, forKey: userDefaultsKey)
    }

    static func label(for seconds: TimeInterval) -> String {
        "\(Int(seconds)) sec"
    }
}
