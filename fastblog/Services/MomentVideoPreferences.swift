// fastblog/Services/MomentVideoPreferences.swift
import Foundation

/// User preference for the maximum length of in-app **Reel** clips (`moment_video.mov` after capture).
enum MomentVideoPreferences {
    static let userDefaultsKey = "bloggo.camera.momentVideoMaxDurationSeconds"
    static let defaultDurationSeconds: TimeInterval = 5

    /// Allowed reel lengths (seconds). Shown in Settings and enforced at record time.
    static let choices: [TimeInterval] = [5, 10, 15, 30]

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

/// Whether the Reel shutter auto-stops at the max duration, or records until the user taps stop
/// (keeping only the last `maxDurationSeconds` of footage).
enum ReelStopMode: String, CaseIterable {
    case auto    // stops automatically when max duration is reached
    case manual  // records indefinitely; last maxDurationSeconds is trimmed and saved

    static let userDefaultsKey = "bloggo.camera.reelStopMode"

    static var current: ReelStopMode {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
        return ReelStopMode(rawValue: raw) ?? .auto
    }

    static func setCurrent(_ mode: ReelStopMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: userDefaultsKey)
    }

    var label: String {
        switch self {
        case .auto: return "Auto Stop"
        case .manual: return "Manual Stop"
        }
    }

    var systemImage: String {
        switch self {
        case .auto: return "timer"
        case .manual: return "infinity"
        }
    }
}
