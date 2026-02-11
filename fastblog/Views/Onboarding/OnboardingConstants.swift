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
        /// Deep navy background (matches landing page).
        static let background = Color(red: 5/255, green: 10/255, blue: 48/255)
        static let backgroundGradientTop = Color(red: 5/255, green: 10/255, blue: 48/255)
        static let backgroundGradientBottom = Color(red: 8/255, green: 14/255, blue: 56/255)
        static let mapBackground = Color(white: 0.92)
        static let searchBackground = Color.white
        static let selectButtonBackground = Color(white: 0.25)
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
        static let titleTopPadding: CGFloat = 16
        static let spacingBetweenTitleAndSearch: CGFloat = 12
        static let searchCornerRadius: CGFloat = 12
        static let selectButtonCornerRadius: CGFloat = 25
        static let selectButtonVerticalPadding: CGFloat = 14
    }
}
