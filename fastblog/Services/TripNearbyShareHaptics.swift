//
//  TripNearbyShareHaptics.swift
//  fastblog
//
//  Haptic feedback for QR + Multipeer nearby trip sharing (host and guest).
//

import UIKit

enum TripNearbyShareHaptics {
    /// Plays feedback when `TripNearbyShareSessionController.phase` changes.
    /// Skips redundant updates while `.transferring` counts photos so each side feels one “pipeline” pulse, not one per file.
    static func playForPhaseTransition(
        from oldPhase: TripNearbyShareSessionController.Phase,
        to newPhase: TripNearbyShareSessionController.Phase
    ) {
        if oldPhase == newPhase { return }
        if case (.transferring, .transferring) = (oldPhase, newPhase) { return }

        switch newPhase {
        case .hostingPreparing:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .hostingAdvertising, .receivingBrowsing:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .hostingConnected, .receivingConnected:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .transferring:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
        case .succeeded:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        default:
            break
        }
    }
}
