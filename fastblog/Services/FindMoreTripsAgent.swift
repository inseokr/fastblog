//
//  FindMoreTripsAgent.swift
//  Capper
//
//

import Foundation

/// Actions the agent can propose to the view
enum AgentAction: Equatable {
    case search(year: Int, startMonth: Int, endMonth: Int, location: String?)
    case insight(InsightType)
    case scanLibrary
    case none
}

enum InsightType: Equatable {
    case busiestSeason
    case bestTrip // Interpreted as "most active month/time"
}

/// A structured response from the agent
struct AgentResponse {
    let text: String
    let action: AgentAction
}

/// Agent that interprets user input for the Find More Trips feature.
struct FindMoreTripsAgent {
    
    enum Season: String {
        case spring, summer, fall, winter, autumn
        
        var months: (start: Int, end: Int) {
            switch self {
            case .spring: return (3, 5)   // March - May
            case .summer: return (6, 8)   // June - August
            case .fall, .autumn: return (9, 11) // Sept - Nov
            case .winter: return (1, 2)   // Jan - Feb (Simpler than wrapping Dec)
            }
        }
    }

    /// Processes user input and returns an action and response.
    static func process(input: String) -> AgentResponse {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 1. Check for Scan Intent
        if normalized == "scan" || normalized.contains("scan my library") {
            return AgentResponse(
                text: "Scanning your library for trips...",
                action: .scanLibrary
            )
        }
        
        // 2. Check for Insight Intents
        if normalized.contains("busiest") || normalized.contains("most active") {
            if normalized.contains("season") {
                return AgentResponse(
                    text: "Checking your library for your busiest season...",
                    action: .insight(.busiestSeason)
                )
            }
        }
        
        if normalized.contains("best trip") || normalized.contains("best") || normalized.contains("favorite") {
            return AgentResponse(
                text: "Looking for your most memorable trips...",
                action: .insight(.bestTrip)
            )
        }
        
        var dateIntent: (year: Int, start: Int, end: Int, label: String)? = nil
        
        let currentYear = Calendar.current.component(.year, from: Date())
        
        // 3. Determine Date Context
        if normalized.contains("last year") {
            let targetYear = currentYear - 1
            dateIntent = (targetYear, 1, 12, "\(targetYear)")
        }
        else if let yearOnly = parseYearOnly(from: normalized), !containsMonth(normalized) && !containsSeason(normalized) {
            dateIntent = (yearOnly, 1, 12, "\(yearOnly)")
        }
        else if let (season, year) = parseSeasonYear(from: normalized) {
            let (start, end) = season.months
            dateIntent = (year, start, end, "\(season.rawValue) \(year)")
        }
        else if let (year, month) = parseYearMonth(from: normalized) {
            let monthName = DateFormatter().monthSymbols[month - 1]
            dateIntent = (year, month, month, "\(monthName) \(year)")
        }
        
        // 4. Construct Response
        if let intent = dateIntent {
            let location = extractLocation(from: normalized)
            
            var responseText = "Showing trips from \(intent.label)."
            if let loc = location {
                responseText = "Checking for trips to \(loc.capitalized) in \(intent.label)."
            }
            
            return AgentResponse(
                text: responseText,
                action: .search(year: intent.year, startMonth: intent.start, endMonth: intent.end, location: location)
            )
        }
        
        return AgentResponse(
            text: "I can help you find trips. Try 'Show trips from last summer', 'When was my busiest season?', or 'Which was my best trip?'.",
            action: .none
        )
    }
    
    // MARK: - Extraction Helpers
    
    private static func extractLocation(from text: String) -> String? {
        var clean = text
        
        // Remove date-related words to isolate the location
        let dateWords = [
            "last year", "last", "year", "trips", "show", "me", "find", "search", "did", "i", "go", "to", "visit", "in", "from", "my", "travel", "ever",
            "january", "jan", "february", "feb", "march", "mar", "april", "apr", "may", "june", "jun", "july", "jul",
            "august", "aug", "september", "sep", "sept", "october", "oct", "november", "nov", "december", "dec",
            "spring", "summer", "fall", "autumn", "winter"
        ]
        
        // Remove known years (19xx, 20xx)
        if let range = clean.range(of: "\\b(19|20)\\d{2}\\b", options: .regularExpression) {
            clean.removeSubrange(range)
        }
        
        // Remove punctuation
        let punctuation = CharacterSet.punctuationCharacters
        clean = clean.components(separatedBy: punctuation).joined(separator: "")
        
        let words = clean.components(separatedBy: .whitespacesAndNewlines)
            .filter { !dateWords.contains($0) }
            .filter { !$0.isEmpty }
        
        guard !words.isEmpty else { return nil }
        
        // Rejoin remaining words (e.g. "south korea", "paris")
        return words.joined(separator: " ")
    }
    
    // MARK: - Date Parsing Helpers
    
    private static func containsMonth(_ text: String) -> Bool {
        let months = [
            "january", "jan", "february", "feb", "march", "mar", "april", "apr", "may",
            "june", "jun", "july", "jul", "august", "aug", "september", "sep", "sept",
            "october", "oct", "november", "nov", "december", "dec"
        ]
        return months.contains { text.contains($0) }
    }
    
    private static func containsSeason(_ text: String) -> Bool {
        let seasons = ["spring", "summer", "fall", "autumn", "winter"]
        return seasons.contains { text.contains($0) }
    }
    
    private static func parseYearOnly(from text: String) -> Int? {
        if let range = text.range(of: "\\b(19|20)\\d{2}\\b", options: .regularExpression) {
            return Int(text[range])
        }
        return nil
    }

    private static func parseSeasonYear(from text: String) -> (Season, Int)? {
        let seasons: [String: Season] = [
            "spring": .spring,
            "summer": .summer,
            "fall": .fall,
            "autumn": .fall,
            "winter": .winter
        ]
        
        var foundSeason: Season?
        for (key, value) in seasons {
            if text.contains(key) {
                foundSeason = value
                break
            }
        }
        guard let season = foundSeason else { return nil }
        
        let currentYear = Calendar.current.component(.year, from: Date())
        var year = currentYear
        
        if let parsedYear = parseYearOnly(from: text) {
            year = parsedYear
        } else if text.contains("last \(season.rawValue)") || text.contains("last") {
             year = currentYear - 1
        }
        
        return (season, year)
    }
    
    private static func parseYearMonth(from text: String) -> (Int, Int)? {
        let currentYear = Calendar.current.component(.year, from: Date())
        
        let months = [
            "january": 1, "jan": 1,
            "february": 2, "feb": 2,
            "march": 3, "mar": 3,
            "april": 4, "apr": 4,
            "may": 5,
            "june": 6, "jun": 6,
            "july": 7, "jul": 7,
            "august": 8, "aug": 8,
            "september": 9, "sep": 9, "sept": 9,
            "october": 10, "oct": 10,
            "november": 11, "nov": 11,
            "december": 12, "dec": 12
        ]
        
        var foundYear: Int?
        if let range = text.range(of: "\\b(19|20)\\d{2}\\b", options: .regularExpression) {
            foundYear = Int(text[range])
        }
        
        var foundMonth: Int?
        for (name, index) in months {
            if text.range(of: "\\b\(name)\\b", options: .regularExpression) != nil {
                foundMonth = index
                break
            }
        }
        
        if let y = foundYear, let m = foundMonth {
            return (y, m)
        }
        
        if let m = foundMonth, text.contains("last") {
            return (currentYear - 1, m)
        }
        
        if let m = foundMonth, foundYear == nil {
             return (currentYear, m)
        }
        
        return nil
    }
}
