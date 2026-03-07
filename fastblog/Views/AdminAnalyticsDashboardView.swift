import SwiftUI

struct AdminAnalyticsDashboardView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService

    @State private var eventCounters: [String: Int] = [:]
    
    // New Backend State
    @State private var backendStats: BackendDashboardAnalytics?
    @State private var isFetchingStats = false
    @State private var fetchError: String?

    private static let adminEmails: Set<String> = [
        "yoobinrickyseo1@gmail.com",
        "inseo.kr@gmail.com"
    ]
    private static let adminUsernames: Set<String> = [
        "inseo", "yoobin", "admin"
    ]

    static func isAdminUser(_ user: AuthUser) -> Bool {
        let email = (user.email ?? "").lowercased()
        let username = (user.username ?? "").lowercased()
        return adminEmails.contains(email) || adminUsernames.contains(username)
    }

    private var isAdmin: Bool {
        guard let user = authService.currentUser else { return false }
        return Self.isAdminUser(user)
    }

    private func refreshCounters() {
        eventCounters = AppAnalytics.shared.countersSnapshot()
    }

    private func fetchBackendStats() {
        guard isAdmin else { return }
        isFetchingStats = true
        fetchError = nil
        Task {
            do {
                let stats = try await APIManager.shared.fetchDashboardAnalytics()
                await MainActor.run {
                    self.backendStats = stats
                    self.isFetchingStats = false
                }
            } catch {
                await MainActor.run {
                    self.fetchError = error.localizedDescription
                    self.isFetchingStats = false
                }
            }
        }
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
                        
                        if isFetchingStats && backendStats == nil {
                            ProgressView("Loading global analytics...")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else if let error = fetchError {
                            Text("Error loading stats: \(error)")
                                .foregroundColor(.red)
                                .font(.subheadline)
                                .padding()
                        } else if let stats = backendStats {
                            overviewSection(stats: stats)
                            apiCostsSection(stats: stats)
                            activationFunnelSection(stats: stats)
                            retentionSection(stats: stats)
                            featureUsageSection(stats: stats)
                            poiAccuracySection(stats: stats)
                        } else {
                            Text("No global analytics found.")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                        
                        Divider().padding(.vertical, 8)
                        
                        Text("Local Device Hardware Analytics")
                            .font(.headline)
                            .padding(.bottom, -8)
                        
                        systemHealthSection
                        localSyncSection
                        funnelSection
                        captionAnalyticsSection
                        eventCountersSection
                        detailsSection
                    }
                    .padding(16)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    refreshCounters()
                    fetchBackendStats()
                }
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
            Text("Platform Analytics")
                .font(.system(.title2, design: .serif).weight(.medium))
            Text("Live data aggregating all users on the platform")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let user = authService.currentUser {
                Text("Logged in as (Username: \(user.username ?? "nil"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func overviewSection(stats: BackendDashboardAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Total Users", value: "\(stats.overview.totalUsers)")
                metricCard(title: "New Users (30d)", value: "\(stats.overview.newUsersLast30Days)")
                metricCard(title: "Total Places", value: "\(stats.overview.totalPlaces)")
                metricCard(title: "Total Photos", value: "\(stats.overview.totalPhotos)")
                if let r = stats.retention {
                    metricCard(title: "Day 7 Retention", value: "\(r.d7Pct)%")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func apiCostsSection(stats: BackendDashboardAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AWS Costs & Storage Usage")
                .font(.headline)
            
            if let costs = stats.apiCosts {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metricCard(title: "AWS Monthly", value: costs.awsMonthlyCost)
                    metricCard(title: "AWS Daily", value: costs.awsDailyCost)
                    metricCard(title: "S3 Storage (PM)", value: costs.awsStorageGB)
                    metricCard(title: "S3 Uploads (PM)", value: costs.awsPutsTotal)
                }
            } else {
                Text("No AWS cost data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func activationFunnelSection(stats: BackendDashboardAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activation Funnel")
                .font(.headline)

            if let f = stats.activationFunnel {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metricCard(title: "Total Users", value: "\(f.totalUsers)")
                    metricCard(title: "Avg Places / User", value: stats.overview.avgPlacesPerUser)
                    metricCard(title: "Total Cloud Blogs", value: "\(f.totalBlogs)")
                    metricCard(title: "Users w/ Blogs", value: "\(f.usersWithBlogs)")
                    metricCard(title: "Users Uploaded", value: "\(f.usersWhoPublished)")
                    metricCard(title: "Avg Blogs / User", value: f.avgBlogsPerUser)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Users → Blogs: \(f.blogsConversionPct)%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Blogs → Published: \(f.publishedConversionPct)%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            } else {
                Text("No funnel data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func retentionSection(stats: BackendDashboardAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Retention & Engagement")
                .font(.headline)

            if let r = stats.retention {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    if let t = stats.timeToFirstBlog {
                        metricCard(title: "Time to 1st Blog (Avg)", value: "\(t.avgMinutes)m")
                        metricCard(title: "Time to 1st Blog (Med)", value: "\(t.medianMinutes)m")
                    }
                    metricCard(title: "Day 1 Retention", value: "\(r.d1Pct)%")
                    metricCard(title: "Day 7 Retention", value: "\(r.d7Pct)%")
                    metricCard(title: "Day 30 Retention", value: "\(r.d30Pct)%")
                    if let s = stats.stickiness {
                        metricCard(title: "Created 2nd Blog", value: "\(s.secondBlogPct)%")
                    }
                }
            } else {
                Text("No retention data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func featureUsageSection(stats: BackendDashboardAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feature Usage")
                .font(.headline)

            if let f = stats.featureUsage, let eq = stats.engagementQuality {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metricCard(title: "Caption Writing", value: "\(f.captionWritingPct)%")
                    metricCard(title: "Audio Recording", value: "\(f.audioRecordingPct)%")
                    metricCard(title: "Place Renames", value: "\(f.placeRenamePct)%")
                    metricCard(title: "Place Captions", value: "\(f.placeCaptionPct)%")
                    metricCard(title: "Avg Renames / User", value: eq.avgRenamedPlacesPerUser)
                    metricCard(title: "Total Renames", value: "\(eq.placesRenamed)")
                }
            } else if let f = stats.featureUsage {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metricCard(title: "Caption Writing", value: "\(f.captionWritingPct)%")
                    metricCard(title: "Audio Recording", value: "\(f.audioRecordingPct)%")
                    metricCard(title: "Place Renames", value: "\(f.placeRenamePct)%")
                    metricCard(title: "Place Captions", value: "\(f.placeCaptionPct)%")
                }
            } else {
                Text("No feature usage data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func poiAccuracySection(stats: BackendDashboardAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("POI Selection Accuracy")
                .font(.headline)
            
            if let p = stats.poiAccuracy {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metricCard(title: "Top 3 Accuracy", value: "\(p.topThreeAccuracy)%")
                    metricCard(title: "Top 10 Accuracy", value: "\(p.topTenAccuracy)%")
                    metricCard(title: "Top 40 Accuracy", value: "\(p.topFortyAccuracy)%")
                    metricCard(title: "Total Selections", value: "\(p.totalSelections)")
                }
            } else {
                Text("No POI data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func metricCard(title: String, value: Int) -> some View {
        metricCard(title: title, value: "\(value)")
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
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

    private var localSyncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Sync Status")
                .font(.headline)

            let totalLocalBlogs = createdRecapStore.recents.count
            let cloudUploadedBlogs = createdRecapStore.recents.filter { 
                $0.cloudState == .uploadedActive || $0.cloudState == .uploadedArchived 
            }.count

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Local Blogs", value: totalLocalBlogs)
                metricCard(title: "Cloud Uploaded", value: cloudUploadedBlogs)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Device upload rate: \(percent(cloudUploadedBlogs, max(totalLocalBlogs, 1)))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
