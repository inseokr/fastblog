import Foundation

let jsonStr = """
{
    "result": "OK",
    "data": {
        "overview": {
            "totalUsers": 1500,
            "totalPlaces": 300,
            "totalPhotos": 1000,
            "totalComments": 5,
            "newUsersLast30Days": 10,
            "averagePlacesPerUser": 0.2,
            "averagePhotosPerPlace": 3.33
        },
        "activationFunnel": {
            "totalUsers": 1500,
            "usersWithPlaces": 100,
            "usersWithBlogs": 50,
            "usersWhoPublished": 10,
            "placesConversionPct": 6.67,
            "blogsConversionPct": 50,
            "publishedConversionPct": 20
        },
        "retention": {
            "d1Pct": 10.5,
            "d7Pct": 5.2,
            "d30Pct": 2.1,
            "secondBlogPct": 1.5,
            "avgDaysSinceLastActive": 14.5
        },
        "engagement": {
            "photosWithStoryPct": 10,
            "photosWithAudioPct": 5,
            "totalStories": 100,
            "totalAudioCaptions": 50,
            "placesWithStory": 20,
            "placeStoryRate": 6.67,
            "placesRenamed": 30,
            "placeRenameRate": 10,
            "avgStoryLengthChars": 150
        },
        "featureUsage": {
            "captionWritingPct": 10,
            "audioRecordingPct": 5,
            "placeRenamePct": 10,
            "placeCaptionPct": 6.67
        }
    }
}
"""

struct WrappedResponse: Decodable {
    let result: String?
    let data: BackendDashboardAnalytics?
}

// Copy the BackendDashboardAnalytics structs up to featureUsage
struct BackendDashboardAnalytics: Decodable {
    let overview: BackendOverview
    let activationFunnel: BackendActivationFunnel?
    let retention: BackendRetention?
    let engagement: BackendEngagement?
    let featureUsage: BackendFeatureUsage?

    enum CodingKeys: String, CodingKey {
        case overview, activationFunnel, retention, engagement, featureUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = (try? container.decode(BackendOverview.self, forKey: .overview)) ?? BackendOverview.empty
        do {
            activationFunnel = try container.decodeIfPresent(BackendActivationFunnel.self, forKey: .activationFunnel)
        } catch {
            print("activationFunnel error: \(error)")
            activationFunnel = nil
        }
        do {
            retention = try container.decodeIfPresent(BackendRetention.self, forKey: .retention)
        } catch {
            print("retention error: \(error)")
            retention = nil
        }
        do {
            engagement = try container.decodeIfPresent(BackendEngagement.self, forKey: .engagement)
        } catch {
            print("engagement error: \(error)")
            engagement = nil
        }
        do {
            featureUsage = try container.decodeIfPresent(BackendFeatureUsage.self, forKey: .featureUsage)
        } catch {
            print("featureUsage error: \(error)")
            featureUsage = nil
        }
    }
}

struct BackendOverview: Decodable {
    static let empty = BackendOverview()
    init() {}
    init(from decoder: Decoder) throws {}
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

struct BackendEngagement: Decodable {
    let photosWithStoryPercentage: String
    let audioCaptionPercentage: String
    let totalStories: Int
    let totalAudioCaptions: Int
    let placesWithStory: Int
    let placeStoryRate: String
    let placesRenamed: Int
    let placeRenameRate: String
    let avgStoryLengthChars: String

    enum CodingKeys: String, CodingKey {
        case photosWithStoryPercentage = "photosWithStoryPct"
        case audioCaptionPercentage = "photosWithAudioPct"
        case totalStories, totalAudioCaptions
        case placesWithStory, placeStoryRate
        case placesRenamed, placeRenameRate
        case avgStoryLengthChars
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decodeStringOrNumber(_ key: CodingKeys) -> String {
            if let s = try? container.decode(String.self, forKey: key) { return s }
            if let n = try? container.decode(Double.self, forKey: key) { return String(format: "%.1f", n) }
            return "0"
        }
        photosWithStoryPercentage = decodeStringOrNumber(.photosWithStoryPercentage)
        audioCaptionPercentage = decodeStringOrNumber(.audioCaptionPercentage)
        totalStories = (try? container.decode(Int.self, forKey: .totalStories)) ?? 0
        totalAudioCaptions = (try? container.decode(Int.self, forKey: .totalAudioCaptions)) ?? 0
        placesWithStory = (try? container.decode(Int.self, forKey: .placesWithStory)) ?? 0
        placeStoryRate = decodeStringOrNumber(.placeStoryRate)
        placesRenamed = (try? container.decode(Int.self, forKey: .placesRenamed)) ?? 0
        placeRenameRate = decodeStringOrNumber(.placeRenameRate)
        avgStoryLengthChars = decodeStringOrNumber(.avgStoryLengthChars)
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

let data = jsonStr.data(using: .utf8)!
do {
    let decoded = try JSONDecoder().decode(WrappedResponse.self, from: data)
    print("Decoded activationFunnel: \(String(describing: decoded.data?.activationFunnel))")
    print("Decoded retention: \(String(describing: decoded.data?.retention))")
    print("Decoded engagement: \(String(describing: decoded.data?.engagement))")
    print("Decoded featureUsage: \(String(describing: decoded.data?.featureUsage))")
} catch {
    print("Outer error: \(error)")
}
