import SwiftUI

struct MyStatsView: View {
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore

    private var visibleBlogs: [CreatedRecapBlog] {
        createdRecapStore.visibleRecents
    }

    private var draftBlogsCount: Int {
        visibleBlogs.filter { createdRecapStore.getBlogDetail(blogId: $0.sourceTripId) == nil }.count
    }

    private var uploadedBlogsCount: Int {
        visibleBlogs.filter { createdRecapStore.isBlogInCloud(blogId: $0.sourceTripId) }.count
    }

    private var totalSelectedPhotos: Int {
        visibleBlogs.reduce(0) { $0 + $1.selectedPhotoCount }
    }

    private var totalMoments: Int {
        visibleBlogs.reduce(0) { $0 + $1.totalPlaceVisitCount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                metricsGrid
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("My Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your activity")
                .font(.system(.title2, design: .serif).weight(.medium))
            Text("A quick snapshot based on what’s currently saved on this device")
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
            metricCard(title: "Uploaded blogs", value: uploadedBlogsCount)
            metricCard(title: "Moments", value: totalMoments)
            metricCard(title: "Selected photos", value: totalSelectedPhotos)
            metricCard(title: "Draft blogs", value: draftBlogsCount)
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
}

#Preview {
    NavigationStack {
        MyStatsView()
            .environmentObject(CreatedRecapBlogStore.shared)
    }
}
