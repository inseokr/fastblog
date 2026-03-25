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
}
