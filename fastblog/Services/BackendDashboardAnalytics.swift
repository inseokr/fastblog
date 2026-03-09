import Foundation

struct BackendDashboardAnalytics: Decodable {
    let overview: BackendOverview
    let poiAccuracy: BackendPoiAccuracy?
    let geography: BackendGeography?
    let categories: [BackendCategory]?
    let topActiveUsers: [BackendTopActiveUser]?
    let engagement: BackendEngagement?
    let blogMetrics: BackendBlogMetrics?
    let activationFunnel: BackendActivationFunnel?
    let retention: BackendRetention?
    let stickiness: BackendStickiness?
    let timeToFirstBlog: BackendTimeToFirstBlog?
    let engagementQuality: BackendEngagementQuality?
    let featureUsage: BackendFeatureUsage?
    let apiCosts: BackendApiCosts?

    enum CodingKeys: String, CodingKey {
        case overview, poiAccuracy, geography, categories, topActiveUsers
        case engagement, blogMetrics, activationFunnel, retention, stickiness, timeToFirstBlog, engagementQuality, featureUsage, apiCosts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = (try? container.decode(BackendOverview.self, forKey: .overview)) ?? BackendOverview.empty
        poiAccuracy = try? container.decode(BackendPoiAccuracy.self, forKey: .poiAccuracy)
        geography = try? container.decode(BackendGeography.self, forKey: .geography)
        categories = try? container.decode([BackendCategory].self, forKey: .categories)
        topActiveUsers = try? container.decode([BackendTopActiveUser].self, forKey: .topActiveUsers)
        engagement = try? container.decode(BackendEngagement.self, forKey: .engagement)
        blogMetrics = try? container.decode(BackendBlogMetrics.self, forKey: .blogMetrics)
        activationFunnel = try? container.decode(BackendActivationFunnel.self, forKey: .activationFunnel)
        retention = try? container.decode(BackendRetention.self, forKey: .retention)
        stickiness = try? container.decode(BackendStickiness.self, forKey: .stickiness)
        timeToFirstBlog = try? container.decode(BackendTimeToFirstBlog.self, forKey: .timeToFirstBlog)
        engagementQuality = try? container.decode(BackendEngagementQuality.self, forKey: .engagementQuality)
        featureUsage = try? container.decode(BackendFeatureUsage.self, forKey: .featureUsage)
        apiCosts = try? container.decode(BackendApiCosts.self, forKey: .apiCosts)
    }
}

struct BackendApiCosts: Decodable {
    let awsMonthlyCost: String
    let awsDailyCost: String
    let awsStorageGB: String
    let awsPutsTotal: String

    enum CodingKeys: String, CodingKey {
        case awsMonthlyCost, awsDailyCost, awsStorageGB, awsPutsTotal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        awsMonthlyCost = (try? container.decode(String.self, forKey: .awsMonthlyCost)) ?? "$0.00"
        awsDailyCost = (try? container.decode(String.self, forKey: .awsDailyCost)) ?? "$0.00"
        awsStorageGB = (try? container.decode(String.self, forKey: .awsStorageGB)) ?? "0.0 GB"
        awsPutsTotal = (try? container.decode(String.self, forKey: .awsPutsTotal)) ?? "0 uploads"
    }
}

struct BackendOverview: Decodable {
    let totalUsers: Int
    let totalPlaces: Int
    let totalPhotos: Int
    let totalComments: Int
    let newUsersLast30Days: Int
    let avgPlacesPerUser: String
    let avgPhotosPerPlace: String

    static let empty = BackendOverview(
        totalUsers: 0, totalPlaces: 0, totalPhotos: 0, totalComments: 0,
        newUsersLast30Days: 0, avgPlacesPerUser: "0", avgPhotosPerPlace: "0"
    )

    enum CodingKeys: String, CodingKey {
        case totalUsers, totalPlaces, totalPhotos, totalComments, newUsersLast30Days
        case avgPlacesPerUser = "averagePlacesPerUser"
        case avgPhotosPerPlace = "averagePhotosPerPlace"
    }

    init(totalUsers: Int, totalPlaces: Int, totalPhotos: Int, totalComments: Int,
         newUsersLast30Days: Int, avgPlacesPerUser: String, avgPhotosPerPlace: String) {
        self.totalUsers = totalUsers
        self.totalPlaces = totalPlaces
        self.totalPhotos = totalPhotos
        self.totalComments = totalComments
        self.newUsersLast30Days = newUsersLast30Days
        self.avgPlacesPerUser = avgPlacesPerUser
        self.avgPhotosPerPlace = avgPhotosPerPlace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalUsers = (try? container.decode(Int.self, forKey: .totalUsers)) ?? 0
        totalPlaces = (try? container.decode(Int.self, forKey: .totalPlaces)) ?? 0
        totalPhotos = (try? container.decode(Int.self, forKey: .totalPhotos)) ?? 0
        totalComments = (try? container.decode(Int.self, forKey: .totalComments)) ?? 0
        newUsersLast30Days = (try? container.decode(Int.self, forKey: .newUsersLast30Days)) ?? 0
        if let s = try? container.decode(String.self, forKey: .avgPlacesPerUser) {
            avgPlacesPerUser = s
        } else if let n = try? container.decode(Double.self, forKey: .avgPlacesPerUser) {
            avgPlacesPerUser = String(format: "%.1f", n)
        } else {
            avgPlacesPerUser = "0"
        }
        if let s = try? container.decode(String.self, forKey: .avgPhotosPerPlace) {
            avgPhotosPerPlace = s
        } else if let n = try? container.decode(Double.self, forKey: .avgPhotosPerPlace) {
            avgPhotosPerPlace = String(format: "%.1f", n)
        } else {
            avgPhotosPerPlace = "0"
        }
    }
}

struct BackendPoiAccuracy: Decodable {
    let topThreeAccuracy: String
    let topTenAccuracy: String
    let topFortyAccuracy: String
    let totalSelections: Int

    enum CodingKeys: String, CodingKey {
        case topThreeAccuracy = "top3AccuracyPct"
        case topTenAccuracy = "top10AccuracyPct"
        case topFortyAccuracy = "top40AccuracyPct"
        case totalSelections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decodeStringOrNumber(_ key: CodingKeys) -> String {
            if let s = try? container.decode(String.self, forKey: key) { return s }
            if let n = try? container.decode(Double.self, forKey: key) { return String(format: "%.1f", n) }
            return "0"
        }
        topThreeAccuracy = decodeStringOrNumber(.topThreeAccuracy)
        topTenAccuracy = decodeStringOrNumber(.topTenAccuracy)
        topFortyAccuracy = decodeStringOrNumber(.topFortyAccuracy)
        totalSelections = (try? container.decode(Int.self, forKey: .totalSelections)) ?? 0
    }
}

struct BackendGeography: Decodable {
    let placesByCountry: [[AnyDecodable]]?
    let placesByCity: [[AnyDecodable]]?
}

struct BackendCategory: Decodable {
    let category: String
    let count: Int
    let percentage: String

    enum CodingKeys: String, CodingKey {
        case category, count, percentage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = (try? container.decode(String.self, forKey: .category)) ?? "unknown"
        count = (try? container.decode(Int.self, forKey: .count)) ?? 0
        if let s = try? container.decode(String.self, forKey: .percentage) {
            percentage = s
        } else if let n = try? container.decode(Double.self, forKey: .percentage) {
            percentage = String(format: "%.1f%%", n)
        } else {
            percentage = "0%"
        }
    }
}

struct BackendTopActiveUser: Decodable {
    let username: String
    let placesAdded: Int
    let photosAdded: Int
    let joinedDate: String

    enum CodingKeys: String, CodingKey {
        case username, placesAdded, photosAdded, joinedDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = (try? container.decode(String.self, forKey: .username)) ?? "unknown"
        placesAdded = (try? container.decode(Int.self, forKey: .placesAdded)) ?? 0
        photosAdded = (try? container.decode(Int.self, forKey: .photosAdded)) ?? 0
        joinedDate = (try? container.decode(String.self, forKey: .joinedDate)) ?? ""
    }
}

struct BackendEngagement: Decodable {
    let photosWithStoryPercentage: String
    let audioCaptionPercentage: String
    let totalStories: Int
    let totalAudioCaptions: Int

    enum CodingKeys: String, CodingKey {
        case photosWithStoryPercentage = "photosWithStoryPct"
        case audioCaptionPercentage = "photosWithAudioPct"
        case totalStories, totalAudioCaptions
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
    }
}

struct BackendEngagementQuality: Decodable {
    let photosWithStoryPct: String
    let photosWithAudioPct: String
    let placeStoryRate: String
    let placesWithStory: Int
    let placeRenameRate: String
    let placesRenamed: Int
    let avgRenamedPlacesPerUser: String
    let avgStoryLengthChars: String

    enum CodingKeys: String, CodingKey {
        case photosWithStoryPct, photosWithAudioPct, placeStoryRate
        case placesWithStory, placeRenameRate, placesRenamed, avgRenamedPlacesPerUser, avgStoryLengthChars
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decodeStringOrNumber(_ key: CodingKeys) -> String {
            if let s = try? container.decode(String.self, forKey: key) { return s }
            if let n = try? container.decode(Double.self, forKey: key) { return String(format: "%.1f", n) }
            return "0"
        }
        photosWithStoryPct = decodeStringOrNumber(.photosWithStoryPct)
        photosWithAudioPct = decodeStringOrNumber(.photosWithAudioPct)
        placeStoryRate = decodeStringOrNumber(.placeStoryRate)
        placesWithStory = (try? container.decode(Int.self, forKey: .placesWithStory)) ?? 0
        placeRenameRate = decodeStringOrNumber(.placeRenameRate)
        placesRenamed = (try? container.decode(Int.self, forKey: .placesRenamed)) ?? 0
        avgRenamedPlacesPerUser = decodeStringOrNumber(.avgRenamedPlacesPerUser)
        avgStoryLengthChars = decodeStringOrNumber(.avgStoryLengthChars)
    }
}

struct BackendBlogMetrics: Decodable {
    let totalBlogs: Int
    let usersWithBlogs: Int
    let blogPublishRate: String
    let avgPhotosPerBlog: String
    let avgPlacesPerBlog: String
    let avgDaysPerBlog: String

    enum CodingKeys: String, CodingKey {
        case totalBlogs, usersWithBlogs, blogPublishRate
        case avgPhotosPerBlog, avgPlacesPerBlog, avgDaysPerBlog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalBlogs = (try? container.decode(Int.self, forKey: .totalBlogs)) ?? 0
        usersWithBlogs = (try? container.decode(Int.self, forKey: .usersWithBlogs)) ?? 0
        func decodeStringOrNumber(_ key: CodingKeys) -> String {
            if let s = try? container.decode(String.self, forKey: key) { return s }
            if let n = try? container.decode(Double.self, forKey: key) { return String(format: "%.1f", n) }
            return "0"
        }
        blogPublishRate = decodeStringOrNumber(.blogPublishRate)
        avgPhotosPerBlog = decodeStringOrNumber(.avgPhotosPerBlog)
        avgPlacesPerBlog = decodeStringOrNumber(.avgPlacesPerBlog)
        avgDaysPerBlog = decodeStringOrNumber(.avgDaysPerBlog)
    }
}

struct BackendActivationFunnel: Decodable {
    let totalUsers: Int
    let usersWithPlaces: Int
    let usersWithBlogs: Int
    let usersWhoPublished: Int
    let totalBlogs: Int
    let avgBlogsPerUser: String
    let placesConversionPct: String
    let blogsConversionPct: String
    let publishedConversionPct: String

    enum CodingKeys: String, CodingKey {
        case totalUsers, usersWithPlaces, usersWithBlogs, usersWhoPublished
        case totalBlogs, avgBlogsPerUser
        case placesConversionPct, blogsConversionPct, publishedConversionPct
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalUsers = (try? container.decode(Int.self, forKey: .totalUsers)) ?? 0
        usersWithPlaces = (try? container.decode(Int.self, forKey: .usersWithPlaces)) ?? 0
        usersWithBlogs = (try? container.decode(Int.self, forKey: .usersWithBlogs)) ?? 0
        usersWhoPublished = (try? container.decode(Int.self, forKey: .usersWhoPublished)) ?? 0
        totalBlogs = (try? container.decode(Int.self, forKey: .totalBlogs)) ?? 0
        func decodeStringOrNumber(_ key: CodingKeys) -> String {
            if let s = try? container.decode(String.self, forKey: key) { return s }
            if let n = try? container.decode(Double.self, forKey: key) { return String(format: "%.1f", n) }
            return "0"
        }
        avgBlogsPerUser = decodeStringOrNumber(.avgBlogsPerUser)
        placesConversionPct = decodeStringOrNumber(.placesConversionPct)
        blogsConversionPct = decodeStringOrNumber(.blogsConversionPct)
        publishedConversionPct = decodeStringOrNumber(.publishedConversionPct)
    }
}

struct BackendRetention: Decodable {
    let d1Pct: String
    let d7Pct: String
    let d30Pct: String

    enum CodingKeys: String, CodingKey {
        case d1Pct, d7Pct, d30Pct
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
    }
}

struct BackendStickiness: Decodable {
    let secondBlogPct: String
    let avgDaysSinceLastActive: String
    let usersWithActivitySignal: Int?

    enum CodingKeys: String, CodingKey {
        case secondBlogPct, avgDaysSinceLastActive, usersWithActivitySignal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decodeStringOrNumber(_ key: CodingKeys) -> String {
            if let s = try? container.decode(String.self, forKey: key) { return s }
            if let n = try? container.decode(Double.self, forKey: key) { return String(format: "%.1f", n) }
            return "0"
        }
        secondBlogPct = decodeStringOrNumber(.secondBlogPct)
        avgDaysSinceLastActive = decodeStringOrNumber(.avgDaysSinceLastActive)
        usersWithActivitySignal = try? container.decode(Int.self, forKey: .usersWithActivitySignal)
    }
}

struct BackendTimeToFirstBlog: Decodable {
    let avgMinutes: String
    let medianMinutes: String
    let usersInSample: Int

    enum CodingKeys: String, CodingKey {
        case avgMinutes, medianMinutes, usersInSample
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usersInSample = (try? container.decode(Int.self, forKey: .usersInSample)) ?? 0
        func decodeStringOrNumber(_ key: CodingKeys) -> String {
            if let s = try? container.decode(String.self, forKey: key) { return s }
            if let n = try? container.decode(Double.self, forKey: key) { return String(format: "%.1f", n) }
            return "0"
        }
        avgMinutes = decodeStringOrNumber(.avgMinutes)
        medianMinutes = decodeStringOrNumber(.medianMinutes)
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

// Helper for parsing loosely typed arrays from JSON
struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyDecodable value cannot be decoded")
        }
    }
}
