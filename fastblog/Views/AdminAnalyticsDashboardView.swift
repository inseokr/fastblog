import SwiftUI

struct AdminAnalyticsDashboardView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @EnvironmentObject private var authService: AuthService

    private let adminEmail = "yoobinrickyseo1@gmail.com"

    private var isAdmin: Bool {
        (authService.currentUser?.email ?? "").lowercased() == adminEmail.lowercased()
    }

    private var visibleBlogs: [CreatedRecapBlog] {
        createdRecapStore.visibleRecents
    }

    private var draftBlogsCount: Int {
        visibleBlogs.filter { createdRecapStore.getBlogDetail(blogId: $0.sourceTripId) == nil }.count
    }

    private var savedBlogsCount: Int {
        visibleBlogs.count - draftBlogsCount
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

    private var uploadedShareableLinksCount: Int {
        visibleBlogs.filter { $0.blogKey != nil }.count
    }

    var body: some View {
        Group {
            if isAdmin {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        metricsGrid
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
            metricCard(title: "Saved blogs", value: savedBlogsCount)
            metricCard(title: "Uploaded", value: uploadedBlogsCount)
            metricCard(title: "Local only", value: localOnlyBlogsCount)
            metricCard(title: "Selected photos", value: totalSelectedPhotos)
            metricCard(title: "Places added", value: totalPlacesAdded)
            metricCard(title: "Blogs w/ caption", value: blogsWithAnyCaptionCount)
            metricCard(title: "Share links", value: uploadedShareableLinksCount)
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
}

#Preview {
    NavigationStack {
        AdminAnalyticsDashboardView()
            .environmentObject(CreatedRecapBlogStore.shared)
            .environmentObject(AuthService.shared)
    }
}
