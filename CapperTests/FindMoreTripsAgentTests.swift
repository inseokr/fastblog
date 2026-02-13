
import XCTest
@testable import Capper

final class FindMoreTripsAgentTests: XCTestCase {

    func testInsightParsing() {
        // Busiest Season
        let busiestInputs = [
            "Which season was the busiest?",
            "What is my busiest season",
            "Show me my most active season"
        ]
        
        for input in busiestInputs {
            let response = FindMoreTripsAgent.process(input: input)
            if case .insight(let type) = response.action {
                XCTAssertEqual(type, .busiestSeason, "Failed to parse busiest season from: \(input)")
            } else {
                XCTFail("Expected .insight(.busiestSeason) for: \(input), got \(response.action)")
            }
        }
        
        // Best Trip
        let bestTripInputs = [
            "Which is my best trip",
            "Show my best trip",
            "What was my most active month",
            "Show favorites" // "favorite" maps to best trip
        ]
        
        for input in bestTripInputs {
            let response = FindMoreTripsAgent.process(input: input)
            if case .insight(let type) = response.action {
                XCTAssertEqual(type, .bestTrip, "Failed to parse best trip from: \(input)")
            } else {
                XCTFail("Expected .insight(.bestTrip) for: \(input), got \(response.action)")
            }
        }
    }
    
    func testDateParsingRemainsIntact() {
        // Last Summer
        let response = FindMoreTripsAgent.process(input: "Show trips from last summer")
        if case .search(let year, let start, let end, _) = response.action {
            let currentYear = Calendar.current.component(.year, from: Date())
            XCTAssertEqual(year, currentYear - 1)
            XCTAssertEqual(start, 6)
            XCTAssertEqual(end, 8)
        } else {
            XCTFail("Expected search action for last summer")
        }
    }
}
