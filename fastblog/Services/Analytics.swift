import Foundation

// MARK: - Wire-format for a single event sent to the backend

private struct AnalyticsEventPayload: Encodable {
    let eventName: String
    let anonymousId: String
    let userId: String?
    let platform: String
    let appVersion: String
    let properties: [String: String]
    let timestamp: String   // ISO 8601
}

private struct AnalyticsBatch: Encodable {
    let events: [AnalyticsEventPayload]
}

// MARK: - AppAnalytics

final class AppAnalytics {
    static let shared = AppAnalytics()

    // -----------------------------------------------------------------------
    // Set this from AuthService when the user logs in / out.
    // -----------------------------------------------------------------------
    var currentUserId: String?

    // -----------------------------------------------------------------------
    // Internal state
    // -----------------------------------------------------------------------
    private let countersKey  = "bloggo.analytics.eventCounters.v1"
    private let queue        = DispatchQueue(label: "bloggo.analytics.queue")
    private var eventBuffer: [AnalyticsEventPayload] = []

    /// Flush when the buffer reaches this size or when the app backgrounds.
    private let flushThreshold = 10

    private let backendURL   = URL(string: "https://pocketverse.herokuapp.com/LS_API/analytics/events")!
    private let isoFormatter = ISO8601DateFormatter()

    private init() {}

    // -----------------------------------------------------------------------
    // MARK: Public API
    // -----------------------------------------------------------------------

    static func trackEvent(name: String, properties: [String: Any] = [:]) {
        shared.trackEvent(name: name, properties: properties)
    }

    func trackEvent(name: String, properties: [String: Any] = [:]) {
        incrementCounter(name)
        enqueueEvent(name: name, properties: properties)

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

    /// Call this from the app delegate / scene delegate when the app moves to background.
    func flushOnBackground() {
        queue.async { self.flush() }
    }

    // -----------------------------------------------------------------------
    // MARK: Local counters (unchanged behaviour)
    // -----------------------------------------------------------------------

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

    // -----------------------------------------------------------------------
    // MARK: Private — queuing & flushing
    // -----------------------------------------------------------------------

    private func enqueueEvent(name: String, properties: [String: Any]) {
        let stringProps = properties.reduce(into: [String: String]()) { dict, pair in
            dict[pair.key] = "\(pair.value)"
        }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let payload = AnalyticsEventPayload(
            eventName:   name,
            anonymousId: AnalyticsIdentity.shared.anonymousId,
            userId:      currentUserId,
            platform:    "ios",
            appVersion:  appVersion,
            properties:  stringProps,
            timestamp:   isoFormatter.string(from: Date())
        )

        queue.async {
            self.eventBuffer.append(payload)
            if self.eventBuffer.count >= self.flushThreshold {
                self.flush()
            }
        }
    }

    /// Must be called from within `queue`.
    private func flush() {
        guard !eventBuffer.isEmpty else { return }
        let batch = eventBuffer
        eventBuffer = []
        sendBatch(batch)
    }

    private func sendBatch(_ events: [AnalyticsEventPayload]) {
        guard let body = try? JSONEncoder().encode(AnalyticsBatch(events: events)) else { return }

        var request = URLRequest(url: backendURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { _, response, error in
            #if DEBUG
            if let error {
                print("📊 flush error: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("📊 flush HTTP \(http.statusCode)")
            } else {
                print("📊 flushed \(events.count) event(s)")
            }
            #endif
        }.resume()
    }

    // -----------------------------------------------------------------------
    // MARK: Private — UserDefaults helpers
    // -----------------------------------------------------------------------

    private func loadCounters() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: countersKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func saveCounters(_ counters: [String: Int]) {
        guard let data = try? JSONEncoder().encode(counters) else { return }
        UserDefaults.standard.set(data, forKey: countersKey)
    }
}
