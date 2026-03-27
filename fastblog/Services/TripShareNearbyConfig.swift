//
//  TripShareNearbyConfig.swift
//  fastblog
//
//  Discovery strategy for “share trip with someone nearby” (Bloggo).
//

import Foundation

/// How two devices find each other for trip transfer. Only `qrInviteMultipeer` is implemented today.
enum TripShareDiscoveryStrategy: String, Codable, CaseIterable, Sendable {
    /// QR / universal link opens the receive flow; MultipeerConnectivity transfers payload on LAN/BT.
    case qrInviteMultipeer = "qr_multipeer"
    /// Reserved: server-mediated coarse location match (not implemented).
    case serverGeofence = "server_geofence"
    /// Reserved: BLE beacon discovery (not implemented).
    case bleProximity = "ble_proximity"
}

/// Constants for nearby trip sharing.
enum TripShareNearbyConfig {
    /// Multipeer service id (≤15 chars, letters, numbers, hyphens only).
    static let multipeerServiceType = "bloggo-trip"
    /// Wire format version embedded in manifests.
    static let schemaVersion = 1
    /// Default product choice: QR invite + local P2P (matches feasibility plan).
    static let defaultDiscoveryStrategy: TripShareDiscoveryStrategy = .qrInviteMultipeer
    /// Discovery dictionary keys (host → guest).
    static let discoverySessionCodeKey = "code"
    static let discoveryRoleKey = "role"
    static let discoveryRoleHost = "host"
    /// Bonjour service type entry expected in `NSBonjourServices`.
    static let bonjourServiceEntry = "_\(multipeerServiceType)._tcp"

    /// Returns configuration warnings that can make nearby share silently fail at runtime.
    static func runtimeConfigWarnings(infoDictionary: [String: Any]) -> [String] {
        var warnings: [String] = []

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let hasOnlyAllowed = multipeerServiceType.unicodeScalars.allSatisfy(allowed.contains)
        if multipeerServiceType.count > 15 || multipeerServiceType.count < 1 || !hasOnlyAllowed {
            warnings.append("Invalid service type '\(multipeerServiceType)'. Must be 1-15 chars: lowercase letters, digits, hyphen.")
        }

        let localUsage = (infoDictionary["NSLocalNetworkUsageDescription"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if localUsage.isEmpty {
            warnings.append("Missing NSLocalNetworkUsageDescription in Info.plist.")
        }

        let bonjour = infoDictionary["NSBonjourServices"] as? [String] ?? []
        if !bonjour.contains(bonjourServiceEntry) {
            warnings.append("NSBonjourServices missing \(bonjourServiceEntry).")
        }

        return warnings
    }
}
