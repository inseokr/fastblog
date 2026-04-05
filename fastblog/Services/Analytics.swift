import Foundation

// MARK: - Wire format

private struct AnalyticsEventPayload: Codable {
    let eventId:     String       // client-generated UUID — enables backend dedup on retry
    let eventName:   String
    let anonymousId: String
    let userId:      String?
    let sessionId:   String
    let platform:    String
    let appVersion:  String
    let context:     AnalyticsContext
    let properties:  [String: String]
    let timestamp:   String       // ISO 8601
}

struct AnalyticsContext: Codable {
    var blogId:   String?
    var placeId:  String?
    var dayIndex: Int?
    var photoId:  String?

    static let empty = AnalyticsContext()
}

private struct AnalyticsBatch: Encodable {
    let events: [AnalyticsEventPayload]
}

// MARK: - AppAnalytics

final class AppAnalytics {
    static let shared = AppAnalytics()

    // Set from AuthService on login / logout.
    var currentUserId: String?

    // -----------------------------------------------------------------------
    // MARK: Private state
    // -----------------------------------------------------------------------

    private let queue        = DispatchQueue(label: "bloggo.analytics.queue")
    private let flushThreshold = 10
    private let maxRetries     = 3
    private let backendURL     = URL(string: "https://pocketverse.herokuapp.com/LS_API/analytics/events")!
    private let isoFormatter   = ISO8601DateFormatter()

    /// Stable per-session UUID, reset on every cold launch.
    private let sessionId = UUID().uuidString

    /// Persistent queue — survives crashes and restarts.
    private var pendingEvents: [AnalyticsEventPayload] = []
    private let queueFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("bloggo_analytics_queue.json")
    }()

    private let countersKey = "bloggo.analytics.eventCounters.v1"

    private init() {
        pendingEvents = loadQueueFromDisk()
        // Drain any leftover events from the previous session.
        if !pendingEvents.isEmpty {
            queue.async { self.flush() }
        }
    }

    // -----------------------------------------------------------------------
    // MARK: Public API
    // -----------------------------------------------------------------------

    static func track(_ event: AnalyticsEventType) {
        shared.track(event)
    }

    func track(_ event: AnalyticsEventType) {
        let name       = event.eventName
        let context    = event.context
        let properties = event.properties

        incrementCounter(name)
        enqueueEvent(name: name, context: context, properties: properties)

        #if DEBUG
        print("📊 \(name)\(context.blogId != nil ? " blog=\(context.blogId!)" : "")")
        #endif
    }

    /// Legacy string-based entry point — kept for call sites not yet migrated.
    static func trackEvent(name: String, properties: [String: Any] = [:]) {
        shared.trackEvent(name: name, properties: properties)
    }

    func trackEvent(name: String, properties: [String: Any] = [:]) {
        incrementCounter(name)
        let stringProps = properties.reduce(into: [String: String]()) { $0[$1.key] = "\($1.value)" }
        enqueueEvent(name: name, context: .empty, properties: stringProps)
        #if DEBUG
        print("📊 \(name)")
        #endif
    }

    func flushOnBackground() {
        queue.async { self.flush() }
    }

    // -----------------------------------------------------------------------
    // MARK: Local counters
    // -----------------------------------------------------------------------

    func incrementCounter(_ name: String, by amount: Int = 1) {
        queue.async {
            var counters = self.loadCounters()
            counters[name, default: 0] += amount
            self.saveCounters(counters)
        }
    }

    func countersSnapshot() -> [String: Int] {
        queue.sync { loadCounters() }
    }

    func resetCounters() {
        queue.async {
            UserDefaults.standard.removeObject(forKey: self.countersKey)
        }
    }

    // -----------------------------------------------------------------------
    // MARK: Private — queuing
    // -----------------------------------------------------------------------

    private func enqueueEvent(name: String, context: AnalyticsContext, properties: [String: String]) {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let payload = AnalyticsEventPayload(
            eventId:     UUID().uuidString,
            eventName:   name,
            anonymousId: AnalyticsIdentity.shared.anonymousId,
            userId:      currentUserId,
            sessionId:   sessionId,
            platform:    "ios",
            appVersion:  appVersion,
            context:     context,
            properties:  properties,
            timestamp:   isoFormatter.string(from: Date())
        )

        queue.async {
            self.pendingEvents.append(payload)
            self.saveQueueToDisk(self.pendingEvents)
            if self.pendingEvents.count >= self.flushThreshold {
                self.flush()
            }
        }
    }

    // -----------------------------------------------------------------------
    // MARK: Private — flushing with retry
    // -----------------------------------------------------------------------

    /// Must be called from within `queue`.
    private func flush() {
        guard !pendingEvents.isEmpty else { return }
        let batch = pendingEvents
        // Optimistically clear the in-memory buffer; disk queue is cleared on success.
        pendingEvents = []
        sendBatch(batch, attempt: 1)
    }

    private func sendBatch(_ events: [AnalyticsEventPayload], attempt: Int) {
        guard let body = try? JSONEncoder().encode(AnalyticsBatch(events: events)) else { return }

        var request = URLRequest(url: backendURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            let success = error == nil && (response as? HTTPURLResponse)?.statusCode == 200

            if success {
                // Remove sent events from disk.
                let sentIds = Set(events.map(\.eventId))
                self.queue.async {
                    self.pendingEvents.removeAll { sentIds.contains($0.eventId) }
                    self.saveQueueToDisk(self.pendingEvents)
                }
                #if DEBUG
                print("📊 flushed \(events.count) event(s)")
                #endif
            } else if attempt < self.maxRetries {
                // Exponential backoff: 2s, 4s, 8s
                let delay = pow(2.0, Double(attempt))
                #if DEBUG
                print("📊 flush failed (attempt \(attempt)), retrying in \(Int(delay))s")
                #endif
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.sendBatch(events, attempt: attempt + 1)
                }
            } else {
                // Max retries reached — put events back in pending queue for next session.
                self.queue.async {
                    self.pendingEvents.insert(contentsOf: events, at: 0)
                    self.saveQueueToDisk(self.pendingEvents)
                }
                #if DEBUG
                print("📊 flush failed after \(self.maxRetries) attempts, queued for next session")
                #endif
            }
        }.resume()
    }

    // -----------------------------------------------------------------------
    // MARK: Private — disk persistence
    // -----------------------------------------------------------------------

    private func loadQueueFromDisk() -> [AnalyticsEventPayload] {
        guard let data = try? Data(contentsOf: queueFileURL) else { return [] }
        return (try? JSONDecoder().decode([AnalyticsEventPayload].self, from: data)) ?? []
    }

    private func saveQueueToDisk(_ events: [AnalyticsEventPayload]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: queueFileURL, options: .atomic)
    }

    // -----------------------------------------------------------------------
    // MARK: Private — UserDefaults counter helpers
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
