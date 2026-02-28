//
//  SplashStateManager.swift
//  fastblog
//

import SwiftUI

/// Drives the three-phase splash → home logo transition.
/// Injected as an @EnvironmentObject so both the top-level overlay and
/// deep views like LandingView can react directly to phase changes.
class SplashStateManager: ObservableObject {
    enum Phase: Equatable { case splash, animating, done }

    @Published var phase: Phase = .splash
}
