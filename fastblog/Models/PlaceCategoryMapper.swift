//
//  PlaceCategoryMapper.swift
//  fastblog
//

import Foundation

enum BloggoCategoryGroup: String, CaseIterable, Codable, Sendable {
    case foodAndDrink       = "food_and_drink"
    case coffeeAndCasual    = "coffee_and_casual"
    case winery             = "winery"
    case nightlife          = "nightlife"
    case lodging            = "lodging"
    case transportation     = "transportation"
    case parking            = "parking"
    case automotive         = "automotive"
    case shopping           = "shopping"
    case retailSpecialty    = "retail_specialty"
    case entertainment      = "entertainment"
    case sportsAndFitness   = "sports_and_fitness"
    case golf               = "golf"
    case beach              = "beach"
    case nature             = "nature"
    case outdoorActivities  = "outdoor_activities"
    case viewpoints         = "viewpoints"
    case hotSprings         = "hot_springs"
    case artsAndCulture     = "arts_and_culture"
    case attractions        = "attractions"
    case health             = "health"
    case personalCare       = "personal_care"
    case education          = "education"
    case government         = "government"
    case financial          = "financial"
    case other              = "other"

    var displayName: String {
        switch self {
        case .foodAndDrink:      return "Food & Drink"
        case .coffeeAndCasual:   return "Coffee & Casual"
        case .winery:            return "Wineries"
        case .nightlife:         return "Nightlife"
        case .lodging:           return "Lodging"
        case .transportation:    return "Transportation"
        case .parking:           return "Parking"
        case .automotive:        return "Automotive"
        case .shopping:          return "Shopping"
        case .retailSpecialty:   return "Retail & Specialty"
        case .entertainment:     return "Entertainment"
        case .sportsAndFitness:  return "Sports & Fitness"
        case .golf:              return "Golf"
        case .beach:             return "Beaches"
        case .nature:            return "Nature"
        case .outdoorActivities: return "Outdoor Activities"
        case .viewpoints:        return "Viewpoints"
        case .hotSprings:        return "Hot Springs"
        case .artsAndCulture:    return "Arts & Culture"
        case .attractions:       return "Attractions"
        case .health:            return "Health"
        case .personalCare:      return "Personal Care"
        case .education:         return "Education"
        case .government:        return "Government"
        case .financial:         return "Financial"
        case .other:             return "Other"
        }
    }

    var icon: String {
        switch self {
        case .foodAndDrink:      return "fork.knife"
        case .coffeeAndCasual:   return "cup.and.saucer.fill"
        case .winery:            return "wineglass.fill"
        case .nightlife:         return "moon.stars.fill"
        case .lodging:           return "bed.double.fill"
        case .transportation:    return "car.fill"
        case .parking:           return "parkingsign"
        case .automotive:        return "fuelpump.fill"
        case .shopping:          return "bag.fill"
        case .retailSpecialty:   return "tag.fill"
        case .entertainment:     return "theatermasks.fill"
        case .sportsAndFitness:  return "dumbbell.fill"
        case .golf:              return "figure.golf"
        case .beach:             return "beach.umbrella.fill"
        case .nature:            return "leaf.fill"
        case .outdoorActivities: return "figure.hiking"
        case .viewpoints:        return "binoculars.fill"
        case .hotSprings:        return "flame.fill"
        case .artsAndCulture:    return "building.columns.fill"
        case .attractions:       return "star.fill"
        case .health:            return "cross.fill"
        case .personalCare:      return "scissors"
        case .education:         return "graduationcap.fill"
        case .government:        return "building.2.fill"
        case .financial:         return "banknote.fill"
        case .other:             return "mappin"
        }
    }
}

enum BloggoCategoryMapper {
    private static let appleToGroup: [String: BloggoCategoryGroup] = [
        // Food & Drink
        "MKPOICategoryRestaurant":       .foodAndDrink,
        "MKPOICategoryCafe":             .coffeeAndCasual,
        "MKPOICategoryBakery":           .foodAndDrink,
        "MKPOICategoryWinery":           .winery,
        "MKPOICategoryBrewery":          .foodAndDrink,
        "MKPOICategoryDistillery":       .foodAndDrink,
        // Shopping
        "MKPOICategoryFoodMarket":       .shopping,
        "MKPOICategoryStore":            .shopping,
        // Nightlife
        "MKPOICategoryNightlife":        .nightlife,
        // Entertainment
        "MKPOICategoryMovieTheater":     .entertainment,
        "MKPOICategoryTheater":          .entertainment,
        "MKPOICategoryCasino":           .entertainment,
        "MKPOICategoryFairground":       .entertainment,
        "MKPOICategoryConventionCenter": .entertainment,
        // Lodging
        "MKPOICategoryHotel":            .lodging,
        "MKPOICategoryCampground":       .lodging,
        // Arts & Culture
        "MKPOICategoryMuseum":           .artsAndCulture,
        "MKPOICategoryReligiousSite":    .artsAndCulture,
        // Attractions
        "MKPOICategoryAmusementPark":    .attractions,
        "MKPOICategoryZoo":              .attractions,
        "MKPOICategoryAquarium":         .attractions,
        // Beach
        "MKPOICategoryBeach":            .beach,
        // Nature
        "MKPOICategoryPark":             .nature,
        "MKPOICategoryNationalPark":     .nature,
        // Transportation
        "MKPOICategoryAirport":          .transportation,
        "MKPOICategoryPublicTransport":  .transportation,
        "MKPOICategoryCarRental":        .transportation,
        "MKPOICategoryParking":          .parking,
        "MKPOICategoryRestStop":         .transportation,
        // Automotive
        "MKPOICategoryGasStation":       .automotive,
        "MKPOICategoryCarWash":          .automotive,
        "MKPOICategoryEVCharger":        .automotive,
        // Health
        "MKPOICategoryHospital":         .health,
        "MKPOICategoryPharmacy":         .health,
        // Sports & Fitness
        "MKPOICategoryFitnessCenter":    .sportsAndFitness,
        "MKPOICategoryStadium":          .sportsAndFitness,
        "MKPOICategoryGolf":             .golf,
        // Outdoor Activities
        "MKPOICategoryMarina":           .outdoorActivities,
        // Personal Care
        "MKPOICategorySpa":              .personalCare,
        "MKPOICategoryLaundry":          .personalCare,
        // Education
        "MKPOICategoryLibrary":          .education,
        "MKPOICategorySchool":           .education,
        "MKPOICategoryUniversity":       .education,
        // Government
        "MKPOICategoryPolice":           .government,
        "MKPOICategoryPostOffice":       .government,
        "MKPOICategoryFireStation":      .government,
        // Financial
        "MKPOICategoryBank":             .financial,
        "MKPOICategoryATM":              .financial,
    ]

    // MARK: - Name-based inference token sets
    //
    // Matching uses whole-word tokenization (split on non-alphanumeric) + naive plural
    // stemming (drop trailing 's' for words >3 chars). This prevents substring false-positives
    // like "Lakewood" matching "lake" or "Trails End Café" matching "trail" as a restaurant.
    //
    // Priority order reflects specificity — more specific groups checked first.
    // e.g. "Bondi Beach Viewpoint" → viewpoints (not beach), "Angel Falls Trail" → outdoorActivities (not nature).

    /// Dedicated scenic overlooks and observation points.
    private static let viewpointTokens: Set<String> = [
        "overlook", "viewpoint", "vista", "lookout",
        "panorama", "belvedere", "observation",
    ]

    /// Beaches and seaside destinations.
    private static let beachTokens: Set<String> = [
        "beach", "seaside", "beachfront", "strand", "sandbar",
    ]

    /// Natural hot springs, geothermal pools, and mineral baths.
    private static let hotSpringTokens: Set<String> = [
        "hotspring", "onsen", "geothermal pool", "mineral spring",
        "sulfur spring", "thermal pool", "thermal bath",
    ]

    /// Wineries, vineyards, and wine-tasting experiences.
    private static let wineryTokens: Set<String> = [
        "winery", "vineyard", "wine", "tasting room",
        "cellar", "chateau", "château", "domaine", "estate",
    ]

    /// Bars, clubs, and after-dark venues.
    private static let nightlifeTokens: Set<String> = [
        "bar", "nightclub", "club", "lounge", "disco",
        "karaoke", "speakeasy", "cocktail",
    ]

    /// Trails, snow sports, water sports, climbing — things you *do* outdoors.
    private static let outdoorTokens: Set<String> = [
        // Trails & paths
        "trail", "trailhead", "path", "walkway", "footpath", "track", "route",
        // Peaks & passes
        "summit", "peak", "pass", "col", "saddle",
        // Snow sports
        "ski", "skiing", "snowboard", "slope", "piste", "chairlift", "gondola",
        // Water sports
        "surf", "surfing", "kayak", "kayaking", "canoe", "canoeing",
        "paddling", "rafting", "snorkeling", "diving",
        // Fishing & equestrian
        "fishing", "angling", "horseback", "equestrian", "stables",
        // Climbing
        "climbing", "bouldering", "ferrata",
        // Other recreation
        "zipline", "paragliding", "cycling", "biking", "camping",
    ]

    /// Natural landforms, bodies of water, and ecosystems.
    private static let natureTokens: Set<String> = [
        // Lakes & still water
        "lake", "pond", "loch", "tarn", "lagoon", "reservoir",
        // Rivers & flowing water
        "river", "creek", "stream", "brook", "tributary",
        // Waterfalls
        "waterfall", "fall", "cascade", "rapid",
        // Coastal (broad geography — specific beach names use beachTokens)
        "bay", "cove", "inlet", "sound", "strait", "channel",
        "fjord", "estuary", "delta", "gulf", "ocean", "sea",
        "coast", "shore", "shoreline", "coastline", "atoll", "reef",
        // Springs & geothermal (broad — specific hot springs use hotSpringTokens)
        "spring", "geyser", "thermal", "geothermal", "lava",
        // Mountains & landforms
        "mountain", "hill", "ridge", "valley", "canyon", "gorge",
        "ravine", "gulch", "glen", "dale", "mesa", "plateau",
        "butte", "bluff", "cliff", "escarpment",
        "volcano", "crater", "caldera", "arch",
        // Gardens & botanical
        "garden", "botanical", "arboretum", "conservatory",
        // Vegetation
        "forest", "wood", "woodland", "grove", "meadow", "prairie",
        "grassland", "plain", "jungle", "rainforest", "mangrove", "savanna",
        // Desert & dunes
        "desert", "dune",
        // Wetlands
        "wetland", "marsh", "swamp", "bog", "moor", "fen",
        // Ice & snow
        "glacier", "icefield", "snowfield", "tundra",
        // Underground
        "cave", "cavern", "grotto",
        // Islands & coastal geography
        "island", "isle", "islet", "peninsula", "cape", "headland",
        // Protected & wild areas
        "wilderness", "reserve", "wildlife",
    ]

    /// Ruins, memorials, religious sites, burial grounds, and historic districts.
    private static let artsCultureTokens: Set<String> = [
        // Ruins & archaeology
        "ruin", "archaeological", "archaeology", "excavation", "ancient",
        // History
        "historic", "heritage", "battlefield", "memorial", "monument",
        "medieval", "colonial",
        // Street art
        "mural", "graffiti",
        // Religious
        "temple", "shrine", "cathedral", "mosque", "pagoda",
        "abbey", "monastery", "convent", "basilica", "chapel",
        "synagogue", "mausoleum", "church",
        // Burial
        "cemetery", "graveyard", "necropoli",
    ]

    /// Famous built structures, public spaces, and landmark destinations.
    private static let attractionTokens: Set<String> = [
        // Defensive & royal structures
        "castle", "palace", "fortress", "fort", "citadel", "rampart",
        // Civic landmarks
        "lighthouse", "tower", "dam", "bridge", "pier",
        "boardwalk", "promenade", "esplanade",
        // Public spaces
        "plaza", "square", "piazza",
        // Harbors & waterfronts
        "harbour", "harbor", "wharf", "waterfront", "marina",
        // Transport hubs as destinations
        "terminal", "station",
        // Other landmarks
        "statue", "landmark", "sculpture", "rooftop",
    ]

    /// Golf courses and related venues.
    private static let golfTokens: Set<String> = [
        "golf", "links", "clubhouse",
    ]

    /// Coffee shops and casual drink spots.
    private static let coffeeTokens: Set<String> = [
        "coffee", "cafe", "café", "espresso", "roaster", "roastery",
        "coffeehouse", "teahouse", "tearoom", "boba", "matcha",
    ]

    /// Food & drink venues Apple misses by name.
    private static let foodDrinkTokens: Set<String> = [
        "distillery", "cidery", "taproom", "pub", "tavern", "bistro", "eatery",
    ]

    /// Shopping venues Apple misses by name.
    private static let shoppingTokens: Set<String> = [
        "market", "bazaar", "souk", "bazar", "flea",
        "mall", "outlet", "arcade",
    ]

    /// Wellness & personal care venues Apple misses by name.
    private static let personalCareTokens: Set<String> = [
        "spa", "hammam", "sauna", "bathhouse",
    ]

    /// Lodging types Apple misses by name.
    private static let lodgingTokens: Set<String> = [
        "hostel", "inn", "resort", "villa", "chalet",
        "ryokan", "motel", "guesthouse",
    ]

    /// Parking lots, garages, and structures.
    private static let parkingTokens: Set<String> = [
        "parking", "garage", "carpark", "park and ride",
    ]

    /// Entertainment venues Apple misses by name.
    private static let entertainmentTokens: Set<String> = [
        "amphitheater", "amphitheatre", "concert", "fairground", "carnival",
    ]

    // MARK: - Tokenizer

    /// Splits a place name into lowercase word tokens and includes naive de-pluraled forms.
    /// "Angel Falls" → {"angel", "fall", "falls"}
    private static func nameTokens(_ name: String) -> Set<String> {
        let words = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        var result = Set(words)
        for word in words where word.hasSuffix("s") && word.count > 3 {
            result.insert(String(word.dropLast()))
        }
        return result
    }

    /// Infers a `BloggoCategoryGroup` from a place name using whole-word keyword matching.
    /// Returns `nil` if no keyword matches — caller decides the fallback.
    static func inferGroup(fromName name: String) -> BloggoCategoryGroup? {
        guard !name.isEmpty else { return nil }
        let t = nameTokens(name)
        if !t.isDisjoint(with: viewpointTokens)    { return .viewpoints }
        if !t.isDisjoint(with: beachTokens)        { return .beach }
        if !t.isDisjoint(with: hotSpringTokens)    { return .hotSprings }
        if !t.isDisjoint(with: wineryTokens)       { return .winery }
        if !t.isDisjoint(with: nightlifeTokens)    { return .nightlife }
        if !t.isDisjoint(with: outdoorTokens)      { return .outdoorActivities }
        if !t.isDisjoint(with: natureTokens)       { return .nature }
        if !t.isDisjoint(with: artsCultureTokens)  { return .artsAndCulture }
        if !t.isDisjoint(with: attractionTokens)   { return .attractions }
        if !t.isDisjoint(with: coffeeTokens)       { return .coffeeAndCasual }
        if !t.isDisjoint(with: golfTokens)         { return .golf }
        if !t.isDisjoint(with: foodDrinkTokens)    { return .foodAndDrink }
        if !t.isDisjoint(with: shoppingTokens)     { return .shopping }
        if !t.isDisjoint(with: personalCareTokens) { return .personalCare }
        if !t.isDisjoint(with: lodgingTokens)      { return .lodging }
        if !t.isDisjoint(with: parkingTokens)      { return .parking }
        if !t.isDisjoint(with: entertainmentTokens){ return .entertainment }
        return nil
    }

    /// Converts an Apple `MKPointOfInterestCategory` raw value to a Bloggo universal group raw value string.
    /// Returns `"other"` for unmapped or nil inputs.
    static func bloggoCategoryRawValue(forAppleRawValue raw: String?) -> String {
        guard let raw = raw, !raw.isEmpty else { return BloggoCategoryGroup.other.rawValue }
        return (appleToGroup[raw] ?? .other).rawValue
    }

    /// Returns the `BloggoCategoryGroup` for a stored category string.
    /// Handles both new Bloggo universal values and old Apple raw values gracefully.
    static func displayGroup(forStoredValue stored: String?) -> BloggoCategoryGroup {
        guard let stored = stored, !stored.isEmpty else { return .other }
        if let group = BloggoCategoryGroup(rawValue: stored) { return group }
        return appleToGroup[stored] ?? .other
    }
}
