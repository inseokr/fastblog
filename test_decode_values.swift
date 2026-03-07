import Foundation

let jsonString = """
{
  "result": "OK",
  "accountType": "all",
  "data": {
    "activationFunnel": {
      "totalUsers": 12,
      "usersWithPlaces": 10,
      "usersWithBlogs": 8,
      "usersWhoPublished": 5,
      "placesConversionPct": 83.3,
      "blogsConversionPct": 80.0,
      "publishedConversionPct": 62.5
    },
    "retention": {
      "d1Pct": 50.0,
      "d7Pct": 25.0,
      "d30Pct": 10.0,
      "eligibleUsers": { "d1": 100, "d7": 100, "d30": 100 }
    },
    "stickiness": {
      "secondBlogPct": 15.0,
      "avgDaysSinceLastActive": 2.5,
      "usersWithActivitySignal": 40
    },
    "featureUsage": {
      "captionWritingPct": 30.5,
      "audioRecordingPct": 5.0,
      "placeRenamePct": 12.0,
      "placeCaptionPct": 2.2
    }
  }
}
"""

struct BackendDashboardAnalytics: Decodable {
    let activationFunnel: BackendActivationFunnel?
    let retention: BackendRetention?
    let featureUsage: BackendFeatureUsage?

    enum CodingKeys: String, CodingKey {
        case activationFunnel, retention, featureUsage
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activationFunnel = try? container.decode(BackendActivationFunnel.self, forKey: .activationFunnel)
        retention = try? container.decode(BackendRetention.self, forKey: .retention)
        featureUsage = try? container.decode(BackendFeatureUsage.self, forKey: .featureUsage)
    }
}

struct BackendActivationFunnel: Decodable {
    let totalUsers: Int
    let usersWithPlaces: Int
    let usersWithBlogs: Int
    let usersWhoPublished: Int
    let placesConversionPct: String
    let blogsConversionPct: String
    let publishedConversionPct: String

    enum CodingKeys: String, CodingKey {
        case totalUsers, usersWithPlaces, usersWithBlogs, usersWhoPublished
        case placesConversionPct, blogsConversionPct, publishedConversionPct
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalUsers = (try? container.decode(Int.self, forKey: .totalUsers)) ?? 0
        usersWithPlaces = (try? container.decode(Int.self, forKey: .usersWithPlaces)) ?? 0
        usersWithBlogs = (try? container.decode(Int.self, forKey: .usersWithBlogs)) ?? 0
        usersWhoPublished = (try? container.decode(Int.self, forKey: .usersWhoPublished)) ?? 0
        func decodeStringOrNumber(_ key: CodingKeys) -> String {
            if let s = try? container.decode(String.self, forKey: key) { return s }
            if let n = try? container.decode(Double.self, forKey: key) { return String(format: "%.1f", n) }
            return "0"
        }
        placesConversionPct = decodeStringOrNumber(.placesConversionPct)
        blogsConversionPct = decodeStringOrNumber(.blogsConversionPct)
        publishedConversionPct = decodeStringOrNumber(.publishedConversionPct)
    }
}

struct BackendRetention: Decodable {
    let d1Pct: String
    let d7Pct: String
    let d30Pct: String
    let secondBlogPct: String
    let avgDaysSinceLastActive: String

    enum CodingKeys: String, CodingKey {
        case d1Pct, d7Pct, d30Pct, secondBlogPct, avgDaysSinceLastActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decodeStringOrNumber(_ key: CodingKeys) -> String {
            if let s = try? container.decode(String.self, forKey: key) { return s }
            if let n = try? container.decode(Double.self, forKey: key) { return String(format: "%.1f", n) }
            return "0"
        }
        d1Pct = decodeStringOrNumber(.d1Pct)
        d7Pct = decodeStringOrNumber(.d7Pct)
        d30Pct = decodeStringOrNumber(.d30Pct)
        secondBlogPct = decodeStringOrNumber(.secondBlogPct)
        avgDaysSinceLastActive = decodeStringOrNumber(.avgDaysSinceLastActive)
    }
}

struct BackendFeatureUsage: Decodable {
    let captionWritingPct: String
    let audioRecordingPct: String
    let placeRenamePct: String
    let placeCaptionPct: String

    enum CodingKeys: String, CodingKey {
        case captionWritingPct, audioRecordingPct, placeRenamePct, placeCaptionPct
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decodeStringOrNumber(_ key: CodingKeys) -> String {
            if let s = try? container.decode(String.self, forKey: key) { return s }
            if let n = try? container.decode(Double.self, forKey: key) { return String(format: "%.1f", n) }
            return "0"
        }
        captionWritingPct = decodeStringOrNumber(.captionWritingPct)
        audioRecordingPct = decodeStringOrNumber(.audioRecordingPct)
        placeRenamePct = decodeStringOrNumber(.placeRenamePct)
        placeCaptionPct = decodeStringOrNumber(.placeCaptionPct)
    }
}

struct WrappedResponse: Decodable {
    let result: String?
    let data: BackendDashboardAnalytics?
}

let data = jsonString.data(using: .utf8)!
do {
    let wrapped = try JSONDecoder().decode(WrappedResponse.self, from: data)
    print("Funnel: totalUsers=", wrapped.data?.activationFunnel?.totalUsers ?? -1)
    print("Retention: d1Pct=", wrapped.data?.retention?.d1Pct ?? "nil")
    print("Feature: audioRecordingPct=", wrapped.data?.featureUsage?.audioRecordingPct ?? "nil")
} catch {
    print("Top level error: \(error)")
}
