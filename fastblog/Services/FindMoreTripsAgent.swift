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
        
        // 1. Deterministic Parsing: "last year"
        if normalized == "last year" {
            return NLPParseResult(
                intent: .set_range,
                startYear: lastYear, startMonth: 1,
                endYear: lastYear, endMonth: 12,
                placeQuery: nil,
                answerText: "Got it. Scanning last year (\(lastYear)).",
                confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
            )
        }
        
        // 2. Deterministic Parsing: "this year"
        if normalized == "this year" || normalized == "current year" {
            return NLPParseResult(
                intent: .set_range,
                startYear: currentYear, startMonth: 1,
                endYear: currentYear, endMonth: 12,
                placeQuery: nil,
                answerText: "Got it. Scanning this year (\(currentYear)).",
                confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
            )
        }
        
        // 3. Deterministic Parsing: "last [season]"
        let seasons = ["spring", "summer", "fall", "winter"]
        for seasonStr in seasons {
            if normalized == "last \(seasonStr)" {
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
                    placeQuery: nil,
                    answerText: "Got it. Scanning last \(seasonStr.capitalized) (\(sYear)).",
                    confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
                )
            }
        }
        
        // 4. Deterministic Parsing: "[Season] [Year]"
        let seasonYearRegex = try? NSRegularExpression(pattern: "^(spring|summer|fall|winter)\\s+(\\d{4})$", options: .caseInsensitive)
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
                    placeQuery: nil,
                    answerText: "Got it. Scanning \(confText).",
                    confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
                )
            }
        }
        
        // 5. Deterministic Parsing: "[Month] [Year]"
        let monthsDict = ["january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12]
        
        let parts = normalized.components(separatedBy: .whitespaces)
        if parts.count == 2, let mName = parts.first, let monthNum = monthsDict[mName], let year = Int(parts[1]) {
            return NLPParseResult(
                intent: .set_range,
                startYear: year, startMonth: monthNum,
                endYear: year, endMonth: monthNum,
                placeQuery: nil,
                answerText: "Got it. Scanning \(mName.capitalized) \(year).",
                confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
            )
        }
        
        // 6. Deterministic Parsing: Year Only
        if let year = Int(normalized), year > 2000 && year <= currentYear + 1 {
            return NLPParseResult(
                intent: .set_range,
                startYear: year, startMonth: 1,
                endYear: year, endMonth: 12,
                placeQuery: nil,
                answerText: "Got it. Scanning the year \(year).",
                confidence: 1.0, needsConfirmation: false, clarificationQuestion: nil
            )
        }
        
        // 7. Fallback to LLM
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
