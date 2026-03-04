import SwiftUI

struct AdminAnalyticsDashboardView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService

    @State private var eventCounters: [String: Int] = [:]

    private let adminEmails: Set<String> = [
        "yoobinrickyseo1@gmail.com",
        "inseo.kr@gmail.com"
    ]

    private var isAdmin: Bool {
        let email = (authService.currentUser?.email ?? "").lowercased()
        return adminEmails.contains(email)
    }

    private var visibleBlogs: [CreatedRecapBlog] {
        createdRecapStore.visibleRecents
    }

    private var draftBlogsCount: Int {
        visibleBlogs.filter { createdRecapStore.getBlogDetail(blogId: $0.sourceTripId) == nil }.count
    }

    private var uploadedBlogsCount: Int {
        visibleBlogs.filter { createdRecapStore.isBlogInCloud(blogId: $0.sourceTripId) }.count
    }

    private var localOnlyBlogsCount: Int {
        visibleBlogs.filter { !createdRecapStore.isBlogInCloud(blogId: $0.sourceTripId) }.count
    }

    private var totalSelectedPhotos: Int {
        visibleBlogs.reduce(0) { $0 + $1.selectedPhotoCount }
    }

    private var totalPlacesAdded: Int {
        visibleBlogs.reduce(0) { $0 + $1.totalPlaceVisitCount }
    }

    private var blogsWithAnyCaptionCount: Int {
        visibleBlogs.filter { ($0.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count
    }

    private func refreshCounters() {
        eventCounters = AppAnalytics.shared.countersSnapshot()
    }

    private func count(_ name: String) -> Int {
        eventCounters[name, default: 0]
    }

    private func percent(_ numerator: Int, _ denominator: Int) -> String {
        guard denominator > 0 else { return "—" }
        let p = (Double(numerator) / Double(denominator)) * 100.0
        return String(format: "%.0f%%", p)
    }

    var body: some View {
        Group {
            if isAdmin {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        metricsGrid
                        systemHealthSection
                        funnelSection
                        captionAnalyticsSection
                        eventCountersSection
                        detailsSection
                    }
                    .padding(16)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Admin Dashboard")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Access denied")
                        .font(.headline)
                    Text("This dashboard is only available to the app admin.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Admin Dashboard")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pre-launch analytics")
                .font(.system(.title2, design: .serif).weight(.medium))
            Text("Local, on-device counters from current app data")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCard(title: "Blogs", value: visibleBlogs.count)
            metricCard(title: "Draft blogs", value: draftBlogsCount)
            metricCard(title: "Uploaded", value: uploadedBlogsCount)
            metricCard(title: "Local only", value: localOnlyBlogsCount)
            metricCard(title: "Selected photos", value: totalSelectedPhotos)
            metricCard(title: "Places added", value: totalPlacesAdded)
            metricCard(title: "Blogs w/ caption", value: blogsWithAnyCaptionCount)
            metricCard(title: "Share links", value: count("blog_link_share_completed"))
        }
    }

    private func metricCard(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)

            Text("These metrics are derived from the blogs currently stored on this device for the signed-in user (or anonymous session). For App Store launch analytics across all users, we’ll add server-side event ingest + aggregation.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var systemHealthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("System health")
                    .font(.headline)
                Spacer()
                Button("Refresh") { refreshCounters() }
                    .font(.subheadline)
            }

            let uploadAttempts = count("upload_attempted")
            let uploadSuccess = count("upload_success")
            let uploadFailed = count("upload_failed")

            let photoPrompted = count("photo_permission_prompted")
            let photoGranted = count("photo_permission_granted")
            let locationPrompted = count("location_permission_prompted")
            let locationGranted = count("location_permission_granted")

            let scansStarted = count("trip_scan_started")
            let scansCompleted = count("trip_scan_completed")
            let tripsDetected = count("trips_detected")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Trip scans started", value: scansStarted)
                metricCard(title: "Trip scans completed", value: scansCompleted)
                metricCard(title: "Trips detected", value: tripsDetected)
                metricCard(title: "Avg trips / scan", value: scansCompleted == 0 ? 0 : Int(round(Double(tripsDetected) / Double(scansCompleted))))
                metricCard(title: "Upload attempts", value: uploadAttempts)
                metricCard(title: "Upload failures", value: uploadFailed)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Upload success rate: \(percent(uploadSuccess, max(uploadAttempts, 1)))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Photo permission accept rate: \(percent(photoGranted, max(photoPrompted, 1)))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Location permission accept rate: \(percent(locationGranted, max(locationPrompted, 1)))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { refreshCounters() }
    }

    private var funnelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blog creation funnel")
                .font(.headline)

            let appOpened = count("app_opened")
            let scansStarted = count("trip_scan_started")
            let scansCompleted = count("trip_scan_completed")
            let tripSelected = count("trip_selected")
            let blogCreated = count("blog_created")
            let firstCaption = count("first_caption_written")
            let blogSaved = count("blog_saved")
            let blogPublished = count("blog_published")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "App opened", value: appOpened)
                metricCard(title: "Trip scans started", value: scansStarted)
                metricCard(title: "Trip scans completed", value: scansCompleted)
                metricCard(title: "Trips selected", value: tripSelected)
                metricCard(title: "Blogs created", value: blogCreated)
                metricCard(title: "First caption written", value: firstCaption)
                metricCard(title: "Blogs saved", value: blogSaved)
                metricCard(title: "Blogs published", value: blogPublished)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Scan → Trip selected: \(percent(tripSelected, max(scansCompleted, 1)))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Trip selected → Blog created: \(percent(blogCreated, max(tripSelected, 1)))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Blog created → First caption: \(percent(firstCaption, max(blogCreated, 1)))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("First caption → Published: \(percent(blogPublished, max(firstCaption, 1)))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var captionAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Captions")
                .font(.headline)

            let dayCaptions = count("day_caption_created")
            let placeCaptions = count("place_caption_created")
            let photoCaptions = count("photo_caption_created")
            let blogsCreated = max(count("blog_created"), 1)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Day captions", value: dayCaptions)
                metricCard(title: "Place captions", value: placeCaptions)
                metricCard(title: "Photo captions", value: photoCaptions)
                metricCard(title: "Avg captions / blog", value: Int(round(Double(dayCaptions + placeCaptions + photoCaptions) / Double(blogsCreated))))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var eventCountersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Event counters")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    AppAnalytics.shared.resetCounters()
                    refreshCounters()
                }
                .font(.subheadline)
            }

            let sorted = eventCounters.keys.sorted()
            if sorted.isEmpty {
                Text("No events tracked yet on this device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sorted, id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(eventCounters[key] ?? 0)")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        AdminAnalyticsDashboardView()
            .environmentObject(CreatedRecapBlogStore.shared)
            .environmentObject(AuthService.shared)
    }
}
