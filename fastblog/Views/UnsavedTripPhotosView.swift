//
//  UnsavedTripPhotosView.swift
//  Capper
//

import SwiftUI

struct UnsavedTripPhotosView: View {
    let trip: TripDraft
    var onCreateBlog: () -> Void
    
    @State private var selectedDayIndex: Int? = nil
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    private var displayedPhotos: [MockPhoto] {
        if let idx = selectedDayIndex {
            guard idx >= 0 && idx < trip.days.count else { return [] }
            return trip.days[idx].photos
        } else {
            return trip.days.flatMap(\.photos)
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(displayedPhotos) { photo in
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                MockPhotoThumbnail(photo: photo, cornerRadius: 0, showIcon: false)
                            )
                            .clipped()
                    }
                }
                .padding(.bottom, 160) // Space for bottom controls
            }
            
            VStack(spacing: 16) {
                // Day Filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterPill(title: "All", isSelected: selectedDayIndex == nil) {
                            selectedDayIndex = nil
                        }
                        
                        ForEach(Array(trip.days.enumerated()), id: \.offset) { index, day in
                            FilterPill(title: "Day \(day.dayIndex)", isSelected: selectedDayIndex == index) {
                                selectedDayIndex = index
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                
                // Create Blog CTA
                Button(action: onCreateBlog) {
                    Text("Create Blog")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .padding(.top, 16)
            // Gradient background for readability of controls
            .background(
                LinearGradient(colors: [.black, .black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
            )
        }
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white : Color.white.opacity(0.2))
                .clipShape(Capsule())
        }
    }
}
