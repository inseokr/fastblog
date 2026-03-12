//
//  EarlyAccessManager.swift
//  fastblog
//
//  Tracks users who join the early access waitlist for cloud publishing.
//  Stores signups as a JSON array in the app's Documents directory.
//

import Foundation

struct EarlyAccessSignup: Codable {
    let username: String
    let email: String
    let signedUpAt: Date
}

final class EarlyAccessManager {
    static let shared = EarlyAccessManager()

    private let fileName = "early_access_signups.json"

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    private init() {}

    func recordSignup(username: String, email: String) {
        var signups = getSignups()
        // Avoid duplicate entries for the same email
        guard !signups.contains(where: { $0.email == email }) else { return }
        let entry = EarlyAccessSignup(username: username, email: email, signedUpAt: Date())
        signups.append(entry)
        save(signups)
    }

    func getSignups() -> [EarlyAccessSignup] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([EarlyAccessSignup].self, from: data)
        } catch {
            print("⚠️ EarlyAccessManager: failed to read signups – \(error.localizedDescription)")
            return []
        }
    }

    private func save(_ signups: [EarlyAccessSignup]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(signups)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("⚠️ EarlyAccessManager: failed to save signups – \(error.localizedDescription)")
        }
    }
}
