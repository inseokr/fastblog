//
//  AuthUser.swift
//  Capper
//

import Foundation

enum AuthProvider: String, Codable, Sendable {
    case apple
    case google
    case email
}

struct AuthUser: Codable, Equatable, Sendable {
    let id: String
    let email: String?
    let displayName: String?
    let username: String?
    let provider: AuthProvider

    var initials: String {
        // Priority: username → displayName → first letter of email → "?"
        let source = username ?? displayName
        if let name = source, !name.isEmpty {
            let parts = name.split(separator: " ")
            let first = parts.first.map { String($0.prefix(1)) } ?? ""
            let last = parts.count > 1 ? (parts.last.map { String($0.prefix(1)) } ?? "") : ""
            return (first + last).uppercased()
        }
        return email.flatMap { String($0.prefix(1)) }?.uppercased() ?? "?"
    }
}
