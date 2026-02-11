//
//  BlogPreviewView.swift
//  Capper
//

import SwiftUI

struct BlogPreviewView: View {
    let trip: TripDraft
    @EnvironmentObject private var createdRecapStore: CreatedRecapBlogStore
    @State private var showSavedScreen = false
    @State private var showRecapBlogPage = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(trip.days) { day in
                    let selectedPhotos = day.photos.filter(\.isSelected)
                    if !selectedPhotos.isEmpty {
                        daySection(day: day, photos: selectedPhotos)
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Blog Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRecapBlogPage = true
                } label: {
                    Text("Open in Recap")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Share stub
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationDestination(isPresented: $showRecapBlogPage) {
            RecapBlogPageView(blogId: trip.id, initialTrip: trip)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                createdRecapStore.addCreatedBlog(trip: trip)
                showSavedScreen = true
            } label: {
                Text("Create Recap Blog")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
        }
        .navigationDestination(isPresented: $showSavedScreen) {
            RecapSavedView()
        }
        .preferredColorScheme(.dark)
    }

    private func daySection(day: TripDay, photos: [MockPhoto]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Day \(day.dayIndex) – \(day.dateText)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(photos) { photo in
                    MockPhotoThumbnail(photo: photo, cornerRadius: 8, showIcon: false)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        BlogPreviewView(trip: TripDraft(
            title: "Iceland",
            dateRangeText: "Jan 1 – Jan 5",
            days: [
                TripDay(dayIndex: 1, dateText: "Jan 1", photos: [
                    MockPhoto(imageName: "photo", timestamp: Date(), isSelected: true),
                    MockPhoto(imageName: "camera", timestamp: Date(), isSelected: true)
                ])
            ],
            coverImageName: "photo",
            isScannedFromDefaultRange: true
        ))
        .environmentObject(CreatedRecapBlogStore.shared)
    }
}
