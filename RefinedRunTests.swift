import Foundation

















    
    
    
    
    
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
                action: .scanLibrary
                action: .updateDateRange(year: targetYear, startMonth: 1, endMonth: 12)
                action: .updateDateRange(year: year, startMonth: month, endMonth: month)
                action: .updateDateRange(year: year, startMonth: start, endMonth: end)
                action: .updateDateRange(year: yearOnly, startMonth: 1, endMonth: 12)
                break
                break
                foundMonth = index
                foundSeason = value
                text: "Scanning your library for trips...",
                text: "Showing \(season.rawValue) \(year).",
                text: "Showing trips from \(monthName) \(year).",
                text: "Showing trips from \(targetYear).",
                text: "Showing trips from \(yearOnly).",
             // "Last Spring" usually means previous year if we are currently in or past spring?
             // But "Last Summer" in 2026 is Summer 2025.
             // But standard is "March" = This year's March (past or future).
             // If month is in future relative to now, maybe user means last year?
             // Or just previous occurrence. For simplicity, if "last", prioritize previous year.
             return (currentYear, m)
             return AgentResponse(
             year = currentYear - 1
            "april": 4, "apr": 4,
            "august": 8, "aug": 8,
            "autumn": .fall,
            "december": 12, "dec": 12
            "fall": .fall,
            "february": 2, "feb": 2,
            "january", "jan", "february", "feb", "march", "mar", "april", "apr", "may",
            "january": 1, "jan": 1,
            "july": 7, "jul": 7,
            "june", "jun", "july", "jul", "august", "aug", "september", "sep", "sept",
            "june": 6, "jun": 6,
            "march": 3, "mar": 3,
            "may": 5,
            "november": 11, "nov": 11,
            "october", "oct", "november", "nov", "december", "dec"
            "october": 10, "oct": 10,
            "september": 9, "sep": 9, "sept": 9,
            "spring": .spring,
            "summer": .summer,
            "winter": .winter
            )
            )
            )
            )
            )
            }
            }
            }
            // checking word boundary to avoid "august" inside "augustus" etc? simpler check:
            action: .none
            case .fall, .autumn: return (9, 11) // Sept - Nov
            case .spring: return (3, 5)   // March - May
            case .summer: return (6, 8)   // June - August
            case .winter: return (1, 2)   // Jan - Feb (Simpler than wrapping Dec)
            foundYear = Int(text[range])
            if text.contains(key) {
            if text.range(of: "\\b\(name)\\b", options: .regularExpression) != nil {
            let (start, end) = season.months
            let monthName = DateFormatter().monthSymbols[month - 1]
            let targetYear = currentYear - 1
            return (currentYear - 1, m)
            return (y, m)
            return AgentResponse(
            return AgentResponse(
            return AgentResponse(
            return AgentResponse(
            return Int(text[range])
            switch self {
            text: "I can help you find trips by date. Try 'Show trips from last summer' or 'Trips from 2023'.",
            year = parsedYear
        )
        ]
        ]
        ]
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        }
        } else if text.contains("last \(season.rawValue)") || text.contains("last") { // simplistic "last" check
        // "Last March" -> Previous year March
        // "March" -> Assume this year? or recent past?
        // 1. Check for Scan Intent
        // 2. Check for "Last Year" or specific year only
        // 3. Check for specific year alone (e.g. "2023")
        // 4. Check for Season + Year (e.g. "Summer 2023", "Last Summer")
        // 5. Check for Month + Year (e.g. "March 2024", "Last March")
        case spring, summer, fall, winter, autumn
        for (key, value) in seasons {
        for (name, index) in months {
        guard let season = foundSeason else { return nil }
        if let (season, year) = parseSeasonYear(from: normalized) {
        if let (year, month) = parseYearMonth(from: normalized) {
        if let m = foundMonth, foundYear == nil {
        if let m = foundMonth, text.contains("last") {
        if let parsedYear = parseYearOnly(from: text) {
        if let range = text.range(of: "\\b(19|20)\\d{2}\\b", options: .regularExpression) {
        if let range = text.range(of: "\\b(19|20)\\d{2}\\b", options: .regularExpression) {
        if let y = foundYear, let m = foundMonth {
        if let yearOnly = parseYearOnly(from: normalized), !containsMonth(normalized) && !containsSeason(normalized) {
        if normalized == "scan" || normalized.contains("scan my library") {
        if normalized.contains("last year") {
        let currentYear = Calendar.current.component(.year, from: Date())
        let currentYear = Calendar.current.component(.year, from: Date())
        let currentYear = Calendar.current.component(.year, from: Date())
        let months = [
        let months = [
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let seasons = ["spring", "summer", "fall", "autumn", "winter"]
        let seasons: [String: Season] = [
        print("❌ FAIL: \(message) - Expected \(sb), got \(sa)")
        print("✅ PASS: \(message)")
        return (season, year)
        return AgentResponse(
        return months.contains { text.contains($0) }
        return nil
        return nil
        return seasons.contains { text.contains($0) }
        var foundMonth: Int?
        var foundSeason: Season?
        var foundYear: Int?
        var months: (start: Int, end: Int) {
        var year = currentYear
    }
    }
    }
    }
    }
    }
    }
    }
    } else {
    /// Processes user input and returns an action and response.
    assertEqual(end, 12, "2023 End")
    assertEqual(end, 12, "Last Year End")
    assertEqual(end, 3, "March 2025 End")
    assertEqual(end, 5, "Last Spring End")
    assertEqual(end, 8, "Summer 2024 End")
    assertEqual(start, 1, "2023 Start")
    assertEqual(start, 1, "Last Year Start")
    assertEqual(start, 3, "Last Spring Start")
    assertEqual(start, 3, "March 2025 Start")
    assertEqual(start, 6, "Summer 2024 Start")
    assertEqual(year, 2023, "2023 Year")
    assertEqual(year, 2024, "Summer 2024 Year")
    assertEqual(year, 2025, "March 2025 Year")
    assertEqual(year, currentYear - 1, "Last Spring Year")
    assertEqual(year, currentYear - 1, "Last Year Year")
    case none
    case scanLibrary
    case updateDateRange(year: Int, startMonth: Int, endMonth: Int)
    enum Season: String {
    if sa != sb {
    let action: AgentAction
    let sa = "\(a)"
    let sb = "\(b)"
    let text: String
    print("❌ FAIL: 2023 command action type")
    print("❌ FAIL: last spring command action type")
    print("❌ FAIL: last year command action type")
    print("❌ FAIL: March 2025 command action type")
    print("❌ FAIL: scan command")
    print("❌ FAIL: summer 2024 command action type")
    print("✅ PASS: scan command")
    private static func containsMonth(_ text: String) -> Bool {
    private static func containsSeason(_ text: String) -> Bool {
    private static func parseSeasonYear(from text: String) -> (Season, Int)? {
    private static func parseYearMonth(from text: String) -> (Int, Int)? {
    private static func parseYearOnly(from text: String) -> Int? {
    static func process(input: String) -> AgentResponse {
}
}
}
}
}
}
}
}
}
}
} else {
} else {
} else {
} else {
} else {
} else {
//
//
//
//  Capper
//  FindMoreTripsAgent.swift
// Last Spring = (CurrentYear - 1)
// Spring = March(3) - May(5)
// Summer = June(6) - August(8)
// Test 1: Scan
// Test 2: Last Year
// Test 3: Specific Year "2023"
// Test 4: "Last Spring"
// Test 5: "Summer 2024"
// Test 6: Month Year "March 2025"
/// A structured response from the agent
/// Actions the agent can propose to the view
/// Agent that interprets user input for the Find More Trips feature.
enum AgentAction: Equatable {
func assertEqual(_ a: Any, _ b: Any, _ message: String = "") {
if case .scanLibrary = scanRes.action {
if case .updateDateRange(let year, let start, let end) = lastYearRes.action {
if case .updateDateRange(let year, let start, let end) = marchRes.action {
if case .updateDateRange(let year, let start, let end) = springRes.action {
if case .updateDateRange(let year, let start, let end) = summerRes.action {
if case .updateDateRange(let year, let start, let end) = yearRes.action {
let currentYear = Calendar.current.component(.year, from: Date())
let lastYearRes = FindMoreTripsAgent.process(input: "show trips from last year")
let marchRes = FindMoreTripsAgent.process(input: "March 2025")
let scanRes = FindMoreTripsAgent.process(input: "scan")
let springRes = FindMoreTripsAgent.process(input: "show me last spring")
let summerRes = FindMoreTripsAgent.process(input: "summer 2024")
let yearRes = FindMoreTripsAgent.process(input: "2023")
print("Running FindMoreTripsAgent Tests...")
print("Tests Completed")
struct AgentResponse {
struct FindMoreTripsAgent {
