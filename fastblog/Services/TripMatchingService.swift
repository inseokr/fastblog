//
//  TripMatchingService.swift
//  Capper
//
//  Strict matching logic to filter out detected trips that are already saved as blogs.
//

import Foundation

struct TripMatchingService {
    /// Overlap percentage threshold (80%) to consider a trip as saved.
    private static let highOverlapThreshold: Double = 0.80
    /// Overlap percentage threshold (30%) when location also matches.
    private static let locationMatchOverlapThreshold: Double = 0.30

    /// Returns true if the detected trip is considered "Already Saved" based on existing blogs.
    static func isTripSaved(draft: TripDraft, against savedBlogs: [CreatedRecapBlog]) -> Bool {
        // 1. Match by stable identifier if available
        if savedBlogs.contains(where: { $0.sourceTripId == draft.id }) {
            return true
        }

        guard let draftStart = draft.earliestDate,
              let draftEnd = draft.latestDate else {
            return false
        }

        let draftDuration = draftEnd.timeIntervalSince(draftStart)
        guard draftDuration > 0 else {
            // Single day trip, check for exact date matches or location matches
            return isSingleDayTripSaved(draft: draft, draftDate: draftStart, against: savedBlogs)
        }

        for blog in savedBlogs {
            guard let blogStart = blog.tripStartDate,
                  let blogEnd = blog.tripEndDate else { continue }

            let overlap = dateOverlap(start1: draftStart, end1: draftEnd, start2: blogStart, end2: blogEnd)
            let overlapPercentage = overlap / draftDuration

            // 2. High overlap rule
            if overlapPercentage >= highOverlapThreshold {
                return true
            }

            // 3. Location + Moderate overlap rule
            if overlapPercentage >= locationMatchOverlapThreshold {
                if let draftCountry = draft.primaryCountryDisplayName,
                   let blogCountry = blog.countryName,
                   !draftCountry.isEmpty,
                   !blogCountry.isEmpty,
                   draftCountry.lowercased() == blogCountry.lowercased() {
                    return true
                }
            }
        }

        return false
    }

    private static func isSingleDayTripSaved(draft: TripDraft, draftDate: Date, against savedBlogs: [CreatedRecapBlog]) -> Bool {
        let calendar = Calendar.current
        for blog in savedBlogs {
            guard let blogStart = blog.tripStartDate,
                  let blogEnd = blog.tripEndDate else { continue }

            // If the blog covers the draft's single day
            if draftDate >= blogStart && draftDate <= blogEnd {
                // If it's the same day and same country, it's likely the same
                if let draftCountry = draft.primaryCountryDisplayName,
                   let blogCountry = blog.countryName,
                   !draftCountry.isEmpty,
                   !blogCountry.isEmpty,
                   draftCountry.lowercased() == blogCountry.lowercased() {
                    return true
                }
                
                // If the overlap is effectively 100% (since single day falls within blog range)
                // and it's a very short blog, we might want higher confidence.
                // But generally, if a blog exists for that date and we have a country match, it's a duplicate.
            }
            
            // Exact same single day
            if calendar.isDate(draftDate, inSameDayAs: blogStart) && calendar.isDate(draftDate, inSameDayAs: blogEnd) {
                 return true
            }
        }
        return false
    }

    /// Returns the overlap duration in seconds between two date ranges.
    private static func dateOverlap(start1: Date, end1: Date, start2: Date, end2: Date) -> TimeInterval {
        let latestStart = max(start1, start2)
        let earliestEnd = min(end1, end2)
        let duration = earliestEnd.timeIntervalSince(latestStart)
        return max(0, duration)
    }
}
