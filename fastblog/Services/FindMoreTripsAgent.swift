//
//  FindMoreTripsAgent.swift
//  Capper
//
//

import Foundation

// MARK: - NLP Models

struct NLPParseResult: Codable, Equatable {
    enum IntentType: String, Codable, Equatable {
        case set_range
        case query_place_presence
        case ask_clarification
        case unsupported
    }
    
    let intent: IntentType
    let startYear: Int?
    let startMonth: Int?
    let endYear: Int?
    let endMonth: Int?
    let placeQuery: String?
    let answerText: String
    let confidence: Double
    let needsConfirmation: Bool
    let clarificationQuestion: String?
}

// MARK: - LLM Provider Protocol

protocol TripScannerLLMProvider {
    func parse(prompt: String) async throws -> NLPParseResult
}

// MOCK Provider for testing before actual local LLM is integrated
class MockTripScannerLLM: TripScannerLLMProvider {
    func parse(prompt: String) async throws -> NLPParseResult {
        let text = prompt.lowercased()
        
        // Wait 1 second to simulate LLM thinking
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Mock QA Test cases from prompt
        if text.contains("did i go") && text.contains("korea") && text.contains("last year") {
            return NLPParseResult(intent: .query_place_presence, startYear: 2025, startMonth: 1, endYear: 2025, endMonth: 12, placeQuery: "Korea", answerText: "Let me check if you went to Korea last year...", confidence: 0.9, needsConfirmation: false, clarificationQuestion: nil)
        } else if text.contains("korea") && text.contains("last year") {
            return NLPParseResult(intent: .set_range, startYear: 2025, startMonth: 1, endYear: 2025, endMonth: 12, placeQuery: "korea", answerText: "Searching for your Korea trips from last year.", confidence: 0.85, needsConfirmation: false, clarificationQuestion: nil)
        } else if text.contains("korea trip") {
            return NLPParseResult(intent: .ask_clarification, startYear: nil, startMonth: nil, endYear: nil, endMonth: nil, placeQuery: "Korea", answerText: "Which year should I check for Korea?", confidence: 0.4, needsConfirmation: false, clarificationQuestion: "Which year should I check for Korea?")
        } else if text.contains("japan") && text.contains("2022") {
            return NLPParseResult(intent: .set_range, startYear: 2022, startMonth: 1, endYear: 2022, endMonth: 12, placeQuery: "japan", answerText: "Searching for trips in Japan in 2022.", confidence: 0.9, needsConfirmation: false, clarificationQuestion: nil)
        }
        
        // Default Mock Fallback
        return NLPParseResult(intent: .unsupported, startYear: nil, startMonth: nil, endYear: nil, endMonth: nil, placeQuery: nil, answerText: "I couldn't quite understand that date range. Try 'last summer' or 'Spring 2024'.", confidence: 0.1, needsConfirmation: false, clarificationQuestion: nil)
    }
}

// MARK: - Agent Logic

struct FindMoreTripsAgent {
    
    static var llmProvider: TripScannerLLMProvider = MockTripScannerLLM()
    
    enum Season: String {
        case spring, summer, fall, winter
        var months: (start: Int, end: Int) {
            switch self {
            case .spring: return (3, 5)   // March - May
            case .summer: return (6, 8)   // June - August
            case .fall: return (9, 11)    // Sept - Nov
            case .winter: return (12, 2)  // Dec - Feb (crosses year)
            }
        }
    }

    /// Processes user input deterministically first, then falls back to LLM.
    static func process(
        input: String,
        currentStart: (year: Int, month: Int),
        currentEnd: (year: Int, month: Int)
    ) async -> NLPParseResult {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        let today = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: today) // Given the prompt, if today is 2026-02-25, currentYear = 2026.
        let lastYear = currentYear - 1 // 2025
        
        let popularPlacesMapping: [String: String] = [
            "south korea": "South Korea", "korea": "South Korea", "republic of korea": "South Korea", "seoul": "Seoul, South Korea",
            "japan": "Japan", "tokyo": "Tokyo, Japan", "kyoto": "Kyoto, Japan", "osaka": "Osaka, Japan",
            "france": "France", "paris": "Paris, France",
            "italy": "Italy", "rome": "Rome, Italy", "milan": "Milan, Italy", "venice": "Venice, Italy",
            "mexico": "Mexico", "cancun": "Cancun, Mexico", "mexico city": "Mexico City",
            "canada": "Canada", "toronto": "Toronto, Canada", "vancouver": "Vancouver, Canada",
            "spain": "Spain", "madrid": "Madrid, Spain", "barcelona": "Barcelona, Spain",
            "uk": "UK", "united kingdom": "UK", "great britain": "UK", "london": "London, UK", "england": "England",
            "us": "USA", "usa": "USA", "united states": "USA", "america": "USA", "nyc": "New York", "new york": "New York", "la": "Los Angeles", "los angeles": "Los Angeles", "hawaii": "Hawaii", "chicago": "Chicago", "miami": "Miami", "las vegas": "Las Vegas",
            "china": "China", "beijing": "Beijing, China", "shanghai": "Shanghai, China", "hong kong": "Hong Kong",
            "taiwan": "Taiwan", "taipei": "Taipei, Taiwan",
            "thailand": "Thailand", "bangkok": "Bangkok, Thailand", "phuket": "Phuket, Thailand",
            "vietnam": "Vietnam", "ho chi minh": "Ho Chi Minh, Vietnam", "hanoi": "Hanoi, Vietnam",
            "indonesia": "Indonesia", "bali": "Bali, Indonesia",
            "australia": "Australia", "sydney": "Sydney, Australia", "melbourne": "Melbourne, Australia",
            "germany": "Germany", "berlin": "Berlin, Germany", "munich": "Munich, Germany",
            "india": "India", "delhi": "Delhi, India", "mumbai": "Mumbai, India",
            "brazil": "Brazil", "rio": "Rio de Janeiro, Brazil", "são paulo": "São Paulo, Brazil", "sao paulo": "São Paulo, Brazil",
            "argentina": "Argentina", "buenos aires": "Buenos Aires, Argentina",
            "switzerland": "Switzerland", "zurich": "Zurich, Switzerland", "geneva": "Geneva, Switzerland",
            "netherlands": "Netherlands", "amsterdam": "Amsterdam, Netherlands",
            "greece": "Greece", "athens": "Athens, Greece", "santorini": "Santorini, Greece",
            "turkey": "Turkey", "istanbul": "Istanbul, Turkey",
            "egypt": "Egypt", "cairo": "Cairo, Egypt",
            "uae": "UAE", "united arab emirates": "UAE", "dubai": "Dubai, UAE",
            "philippines": "Philippines", "manila": "Manila, Philippines", "palawan": "Palawan, Philippines",
            "malaysia": "Malaysia", "kuala lumpur": "Kuala Lumpur, Malaysia",
            "singapore": "Singapore"
        ]

        var extractedPlace: String? = nil
        let sortedPlaceKeys = popularPlacesMapping.keys.sorted { $0.count > $1.count }
        for key in sortedPlaceKeys {
            if normalized.range(of: "\\b\(key)\\b", options: .regularExpression) != nil {
                extractedPlace = popularPlacesMapping[key]
                break
            }
        }

        // 1. Deterministic Parsing: "last year"
        if normalized.contains("last year") {
            return NLPParseResult(
                intent: .set_range,
                startYear: lastYear, startMonth: 1,
                endYear: lastYear, endMonth: 12,
                placeQuery: extractedPlace,
                answerText: "Got it. Scanning last year (\(lastYear))\(extractedPlace != nil ? " for " + extractedPlace! : "").",
                confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
            )
        }
        
        // 2. Deterministic Parsing: "this year"
        if normalized.contains("this year") || normalized.contains("current year") {
            return NLPParseResult(
                intent: .set_range,
                startYear: currentYear, startMonth: 1,
                endYear: currentYear, endMonth: 12,
                placeQuery: extractedPlace,
                answerText: "Got it. Scanning this year (\(currentYear))\(extractedPlace != nil ? " for " + extractedPlace! : "").",
                confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
            )
        }
        
        // 3. Deterministic Parsing: "last [season]"
        let seasons = ["spring", "summer", "fall", "winter"]
        for seasonStr in seasons {
            if normalized.contains("last \(seasonStr)") {
                guard let season = Season(rawValue: seasonStr) else { continue }
                let (sMonth, eMonth) = season.months
                var sYear = lastYear
                var eYear = lastYear
                
                if season == .winter {
                    sYear = lastYear - 1
                    eYear = lastYear
                }
                
                return NLPParseResult(
                    intent: .set_range,
                    startYear: sYear, startMonth: sMonth,
                    endYear: eYear, endMonth: eMonth,
                    placeQuery: extractedPlace,
                    answerText: "Got it. Scanning last \(seasonStr.capitalized) (\(sYear))\(extractedPlace != nil ? " for " + extractedPlace! : "").",
                    confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
                )
            }
        }
        
        // 4. Deterministic Parsing: "[Season] [Year]"
        let seasonYearRegex = try? NSRegularExpression(pattern: "\\b(spring|summer|fall|winter)\\s+(\\d{4})\\b", options: .caseInsensitive)
        if let match = seasonYearRegex?.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
            if let seasonRange = Range(match.range(at: 1), in: normalized),
               let yearRange = Range(match.range(at: 2), in: normalized),
               let year = Int(normalized[yearRange]),
               let season = Season(rawValue: String(normalized[seasonRange]).lowercased()) {
                
                let (sMonth, eMonth) = season.months
                let sYear = year
                let eYear = season == .winter ? year + 1 : year
                
                let confText = season == .winter ? "Winter \(year) (Dec \(year) to Feb \(eYear))" : "\(season.rawValue.capitalized) \(year)"
                
                return NLPParseResult(
                    intent: .set_range,
                    startYear: sYear, startMonth: sMonth,
                    endYear: eYear, endMonth: eMonth,
                    placeQuery: extractedPlace,
                    answerText: "Got it. Scanning \(confText)\(extractedPlace != nil ? " for " + extractedPlace! : "").",
                    confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
                )
            }
        }
        
        // 5. Deterministic Parsing: "[Month] [Year]"
        let monthsDict = ["january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12]
        let monthNamesPattern = monthsDict.keys.joined(separator: "|")
        let monthYearRegex = try? NSRegularExpression(pattern: "\\b(\(monthNamesPattern))\\s+(\\d{4})\\b", options: .caseInsensitive)
        
        if let match = monthYearRegex?.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
            if let mRange = Range(match.range(at: 1), in: normalized),
               let yRange = Range(match.range(at: 2), in: normalized),
               let mNum = monthsDict[String(normalized[mRange]).lowercased()],
               let year = Int(normalized[yRange]) {
                let mName = String(normalized[mRange]).capitalized
                return NLPParseResult(
                    intent: .set_range,
                    startYear: year, startMonth: mNum,
                    endYear: year, endMonth: mNum,
                    placeQuery: extractedPlace,
                    answerText: "Got it. Scanning \(mName) \(year)\(extractedPlace != nil ? " for " + extractedPlace! : "").",
                    confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
                )
            }
        }
        
        // 6. Deterministic Parsing: Year Only
        let yearRegex = try? NSRegularExpression(pattern: "\\b(20\\d{2})\\b")
        if let match = yearRegex?.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
            if let yearRange = Range(match.range(at: 1), in: normalized),
               let year = Int(normalized[yearRange]), year > 2000 && year <= currentYear + 1 {
                return NLPParseResult(
                    intent: .set_range,
                    startYear: year, startMonth: 1,
                    endYear: year, endMonth: 12,
                    placeQuery: extractedPlace,
                    answerText: "Got it. Scanning the year \(year)\(extractedPlace != nil ? " for " + extractedPlace! : "").",
                    confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
                )
            }
        }
        
        // 7. Deterministic Parsing: Place ONLY fallback (if no date was found above)
        // Ask the user for a date/year rather than scanning a massive 8-year range automatically.
        if let extractedPlace = extractedPlace {
            return NLPParseResult(
                intent: .ask_clarification,
                startYear: nil, startMonth: nil,
                endYear: nil, endMonth: nil,
                placeQuery: extractedPlace,
                answerText: "I found \(extractedPlace)! Which year or time period should I search? (e.g. \"last year\", \"2024\", \"last summer\")",
                confidence: 0.7, needsConfirmation: false,
                clarificationQuestion: "Which year or time period should I search for \(extractedPlace)?"
            )
        }
        
        // 8. Fallback to LLM
        // Build prompt context
        let prompt = """
        todayISO: \(ISO8601DateFormatter().string(from: today))
        timezone: \(TimeZone.current.identifier)
        currentStart: { "year": \(currentStart.year), "month": \(currentStart.month) }
        currentEnd: { "year": \(currentEnd.year), "month": \(currentEnd.month) }
        userText: "\(input)"
        """
        
        do {
            let result = try await llmProvider.parse(prompt: prompt)
            return result
        } catch {
            return NLPParseResult(
                intent: .unsupported,
                startYear: nil, startMonth: nil, endYear: nil, endMonth: nil,
                placeQuery: nil,
                answerText: "I'm having trouble understanding. Please try again or select dates manually.",
                confidence: 0.0, needsConfirmation: false, clarificationQuestion: nil
            )
        }
    }
}
