import Foundation

final class AppAnalytics {
    static let shared = AppAnalytics()

    private let countersKey = "bloggo.analytics.eventCounters.v1"
    private let queue = DispatchQueue(label: "bloggo.analytics.queue")

    private init() {}

    static func trackEvent(name: String, properties: [String: Any] = [:]) {
        shared.trackEvent(name: name, properties: properties)
    }

    func trackEvent(name: String, properties: [String: Any] = [:]) {
        incrementCounter(name)

        #if DEBUG
        if properties.isEmpty {
            print("📊 \(name)")
        } else {
            print("📊 \(name) \(properties)")
        }
        #endif
    }
    
    func trackCaptionWritten(type: String) {
        trackEvent(name: type)
        let firstCaptionKey = "bloggo.analytics.has_written_first_caption"
        if !UserDefaults.standard.bool(forKey: firstCaptionKey) {
            UserDefaults.standard.set(true, forKey: firstCaptionKey)
            trackEvent(name: "first_caption_written")
        }
    }

    func incrementCounter(_ name: String, by amount: Int = 1) {
        queue.sync {
            var counters = loadCounters()
            counters[name, default: 0] += amount
            saveCounters(counters)
        }
    }

    func countersSnapshot() -> [String: Int] {
        queue.sync { loadCounters() }
    }

    func resetCounters() {
        queue.sync {
            UserDefaults.standard.removeObject(forKey: countersKey)
        }
    }

    private func loadCounters() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: countersKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func saveCounters(_ counters: [String: Int]) {
        guard let data = try? JSONEncoder().encode(counters) else { return }
        UserDefaults.standard.set(data, forKey: countersKey)
    }
}
