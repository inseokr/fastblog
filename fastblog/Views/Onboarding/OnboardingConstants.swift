//
//  OnboardingConstants.swift
//  Capper
//

import CoreLocation
import SwiftUI

enum OnboardingConstants {
    enum Splash {
        static let autoAdvanceInterval: TimeInterval = 1.2
        static let fadeInDuration: TimeInterval = 0.5
        static let fadeInDelay: TimeInterval = 0.2
        /// Logo size to match mock: substantial, balanced with title (mock shows large block-style icon).
        static let logoSize: CGFloat = 200
        static let titleFontSize: CGFloat = 34
    }

    enum Colors {
        /// Cream off-white onboarding background.
        static let background = Color(red: 250/255, green: 247/255, blue: 239/255)
        static let backgroundGradientTop = Color(red: 255/255, green: 252/255, blue: 245/255)
        static let backgroundGradientBottom = Color(red: 244/255, green: 238/255, blue: 226/255)
        static let primaryText = Color(red: 32/255, green: 35/255, blue: 42/255)
        static let secondaryText = Color(red: 75/255, green: 79/255, blue: 88/255)
        static let tertiaryText = Color(red: 112/255, green: 114/255, blue: 120/255)
        static let hairline = Color.black.opacity(0.12)
        static let controlBackground = Color.white.opacity(0.78)
        static let mapBackground = Color(white: 0.92)
        static let searchBackground = Color.white
        static let selectButtonBackground = primaryText
        /// Bright blue for primary actions (e.g. Done after neighborhood select). #007AFF.
        static let doneButtonBlue = Color(red: 0, green: 122/255, blue: 1)
        /// Center circle on neighborhood map (same blue as Done; opacity range applied in view).
        static let centerCircleBlue = doneButtonBlue
    }

    enum Map {
        static let defaultLatitude = 37.7749
        static let defaultLongitude = -122.4194
        static var defaultCenter: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: defaultLatitude, longitude: defaultLongitude)
        }
        static let defaultSpanLat: CLLocationDegrees = 0.05
        static let defaultSpanLon: CLLocationDegrees = 0.05
        static let centerCirclePulseDuration: TimeInterval = 1.8
        static let centerCircleScaleRange: (min: CGFloat, max: CGFloat) = (1.0, 1.08)
        static let centerCircleOpacityRange: (min: Double, max: Double) = (0.6, 0.75)
        /// Diameter of the center selection circle (larger = bigger hitbox / selection area).
        static let centerCircleDiameter: CGFloat = 220
        /// Padding between the center circle and the Select button (so they don’t touch).
        static let selectButtonSpacingBelowCircle: CGFloat = 16
    }

    enum Search {
        static let debounceInterval: TimeInterval = 0.25
    }

    enum Layout {
        static let horizontalPadding: CGFloat = 20
        static let titleTopPadding: CGFloat = 8
        static let spacingBetweenTitleAndSearch: CGFloat = 24
        static let searchCornerRadius: CGFloat = 12
        static let selectButtonCornerRadius: CGFloat = 25
        static let selectButtonVerticalPadding: CGFloat = 14
    }
}
