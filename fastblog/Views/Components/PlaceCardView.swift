//
//  PlaceCardView.swift
//  Capper
//
//  Redesigned premium place cards for Map view with horizontal "peek" scroll.
//

import SwiftUI

// MARK: - RankBadge
struct RankBadge: View {
    let rank: Int
    var useGold: Bool = false
    
    var body: some View {
        Text(ordinalString(rank))
            .font(.system(size: 10, weight: .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(useGold ? Color(red: 0.85, green: 0.65, blue: 0.13) : Color.black.opacity(0.6))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
    
    private func ordinalString(_ number: Int) -> String {
        let suffix: String
        let ones = number % 10
        let tens = (number / 10) % 10
        
        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(number)\(suffix)"
    }
}

// MARK: - PlaceCardView
struct PlaceCardView: View {
    let stop: PlaceStop
    let rank: Int
    let style: CardStyle
    var isSelected: Bool = false
    
    enum CardStyle {
        case minimal
        case editorial
        case voyage // Premium Travel App Style
    }
    
    private static let visitTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    
    private var visitTimeText: String? {
        stop.photos.map(\.timestamp).min().map { Self.visitTimeFormatter.string(from: $0) }
    }
    
    var body: some View {
        Group {
            switch style {
            case .minimal:
                minimalStyle
            case .editorial:
                editorialStyle
            case .voyage:
                voyageStyle
            }
        }
        .frame(width: style == .voyage ? 300 : nil, height: style == .voyage ? 160 : 140)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(isSelected ? Color.blue : Color.white.opacity(0.12), lineWidth: isSelected ? 3 : 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isSelected)
    }
    
    private var voyageStyle: some View {
        ZStack(alignment: .leading) {
            // Glassmorphic Background
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
            
            HStack(spacing: 0) {
                // Info Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        RankBadge(rank: rank, useGold: rank == 1)
                        
                        if let time = visitTimeText {
                            Text(time)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.placeTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        if let subtitle = stop.placeSubtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    
                    if let note = stop.noteText, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(2)
                            .italic()
                            .padding(.top, 2)
                    }
                    
                    Spacer()
                    
                    // Photo count tag
                    HStack(spacing: 4) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 10))
                        Text("\(stop.photos.count) photos")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white.opacity(0.5))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Photo Section
                if let photo = stop.photos.first {
                    RecapPhotoThumbnail(photo: photo, cornerRadius: 18, showIcon: false, targetSize: CGSize(width: 400, height: 400))
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 110, height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.trailing, 10)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
        }
    }
    
    private var editorialStyle: some View {
        ZStack(alignment: .bottomLeading) {
            // Photo Background
            if let photo = stop.photos.first {
                RecapPhotoThumbnail(photo: photo, cornerRadius: 0, showIcon: false, targetSize: CGSize(width: 800, height: 400))
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Color(white: 0.15)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.white.opacity(0.2))
                    )
            }
            
            // Gradients for readability
            LinearGradient(
                colors: [.black.opacity(0.7), .black.opacity(0.2), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(stop.placeTitle)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if let time = visitTimeText {
                        Text(time)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                if let subtitle = stop.placeSubtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    if let note = stop.noteText, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Data: Photo Count
                    HStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("\(stop.photos.count)")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                .padding(.top, 2)
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.85), .black.opacity(0.4), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            
            // Floating Rank Badge
            VStack {
                HStack {
                    RankBadge(rank: rank, useGold: rank == 1)
                    Spacer()
                }
                Spacer()
            }
            .padding(12)
        }
    }
    
    private var minimalStyle: some View {
        HStack(spacing: 0) {
            // Info Side
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    RankBadge(rank: rank, useGold: rank == 1)
                    if let time = visitTimeText {
                        Text(time)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.placeTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let subtitle = stop.placeSubtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                if let note = stop.noteText, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Photo Side
            if let photo = stop.photos.first {
                RecapPhotoThumbnail(photo: photo, cornerRadius: 0, showIcon: false, targetSize: CGSize(width: 400, height: 400))
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 140)
                    .clipped()
            } else {
                Color.secondary.opacity(0.1)
                    .frame(width: 120, height: 140)
                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
            }
        }
        .background(
            ZStack {
                Color(uiColor: .systemBackground)
                Color.blue.opacity(isSelected ? 0.05 : 0)
            }
        )
    }
}

// MARK: - PlaceCardCarousel
struct PlaceCardCarousel: View {
    let stops: [PlaceStop]
    @Binding var selectedIndex: Int
    var style: PlaceCardView.CardStyle = .voyage
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    PlaceCardView(
                        stop: stop,
                        rank: index + 1,
                        style: style,
                        isSelected: selectedIndex == index
                    )
                    .id(index)
                    .onTapGesture {
                        withAnimation(.spring()) {
                            selectedIndex = index
                        }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: Binding(
            get: { selectedIndex },
            set: { if let val = $0 { selectedIndex = val } }
        ))
        .safeAreaPadding(.horizontal, 24) // This creates the "peek" affordance
        .frame(height: style == .voyage ? 180 : 160)
    }
}
