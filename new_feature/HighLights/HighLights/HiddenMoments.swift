import Foundation

/// Feature ⑤: hidden-moment discovery — "a pattern only the AI noticed".
/// Implements Prof. Kim ⑦. The corrupted loop from the source doc (`for i in 0.. 720`) is fixed here.
/// Tone guide: observational phrasing, not verdicts ("you're the type who…") — reduces the creepy risk.
enum HiddenMoments {

    static func detect(photos: [PhotoItem], clusters: [PlaceCluster]) -> [HiddenMoment] {
        var moments: [HiddenMoment] = []
        let calendar = Calendar.current
        let sorted = photos.sorted { $0.timestamp < $1.timestamp }

        // 1. Revisited place — POI sequence duplication
        let names = clusters.map(\.name)
        for name in Set(names) where names.filter({ $0 == name }).count > 1 {
            let visits = clusters.filter { $0.name == name }
            if let first = visits.first, let last = visits.last {
                let gap = Int(last.arrival.timeIntervalSince(first.departure) / 3600)
                moments.append(HiddenMoment(
                    title: "Same place, twice",
                    body: "You visited \(name) twice, \(gap) hours apart. When the light changes, the same place tells an entirely different story.",
                    source: "POI sequence analysis"))
            }
        }

        // 2. 12+ min shooting gap — "time spent just watching"
        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp)
            let samePlace = sorted[i].placeName == sorted[i - 1].placeName
            if samePlace && gap > 720 {
                moments.append(HiddenMoment(
                    title: "\(Int(gap / 60)) minutes of silence",
                    body: "There are no photos for \(Int(gap / 60)) minutes before this shot at \(sorted[i].placeName). Some moments you take in with your eyes before the lens.",
                    source: "EXIF timestamp gaps"))
                break
            }
        }

        // 3. Meal timing — average time of the first "lunch-window" shot (12–15h) per day
        let lunchTimes: [Double] = Dictionary(grouping: sorted) {
            calendar.startOfDay(for: $0.timestamp)
        }.compactMap { _, day in
            day.first {
                let h = calendar.component(.hour, from: $0.timestamp)
                return (12...15).contains(h)
            }.map {
                Double(calendar.component(.hour, from: $0.timestamp))
                + Double(calendar.component(.minute, from: $0.timestamp)) / 60
            }
        }
        if !lunchTimes.isEmpty {
            let avg = lunchTimes.reduce(0, +) / Double(lunchTimes.count)
            if avg >= 13.5 {
                let h = Int(avg), m = Int((avg - Double(h)) * 60)
                moments.append(HiddenMoment(
                    title: "Lunch was always after 1 PM",
                    body: "Your first lunch-window shot averaged \(h):\(String(format: "%02d", m)) this trip. Looks like the kind of trip where you forget to feel hungry while exploring.",
                    source: "EXIF meal-time distribution"))
            }
        }

        // 4. Longest stay = most-photographed place?
        if let longest = clusters.max(by: { $0.dwellMinutes < $1.dwellMinutes }),
           let most = clusters.max(by: { $0.photos.count < $1.photos.count }),
           longest.id == most.id {
            moments.append(HiddenMoment(
                title: "Where your pace slowed",
                body: "You stayed longest at \(longest.name) (\(longest.dwellMinutes) min) and took the most photos there (\(longest.photos.count)). Your body noticed the place before you did.",
                source: "Dwell time × photo density"))
        }

        // 5. Day 1 vs last day shooting style (simple photo-count comparison)
        let byDay = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.timestamp) }
        let days = byDay.keys.sorted()
        if let firstDay = days.first, let lastDay = days.last, firstDay != lastDay,
           let f = byDay[firstDay]?.count, let l = byDay[lastDay]?.count, f > 0 {
            let diff = Double(l) / Double(f)
            if diff < 0.7 {
                moments.append(HiddenMoment(
                    title: "The trip deepened",
                    body: "Day 1: \(f) photos → last day: \(l). Fewer shutter clicks often means more time spent just looking.",
                    source: "Per-day photo density"))
            }
        }

        return moments
    }
}
