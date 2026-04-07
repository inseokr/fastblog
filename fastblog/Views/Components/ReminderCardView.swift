//
//  ReminderCardView.swift
//  Capper
//

import SwiftUI
import Photos

struct ReminderCardView: View {
    let reminder: SmartReminder
    let onCreate: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with icon and title
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 20, weight: .bold))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Before You Forget")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.orange)
                            .textCase(.uppercase)
                        
                        Text(reminder.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Photo Strip
                HStack(spacing: 8) {
                    ForEach(reminder.assets.prefix(3), id: \.localIdentifier) { asset in
                        AssetPhotoView(assetIdentifier: asset.localIdentifier, cornerRadius: 12, targetSize: CGSize(width: 300, height: 300))
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(appChromeBaseRadius: 12))
                            .overlay(
                                RoundedRectangle(appChromeBaseRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                    
                    if reminder.assets.count > 3 {
                        ZStack {
                            RoundedRectangle(appChromeBaseRadius: 12)
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 100, height: 100)
                            VStack(spacing: 4) {
                                Text("\(reminder.assets.count - 3)+")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                Text("more")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                }
                
                // Location & Dates
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let cityName = reminder.cityName {
                            Text(cityName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        
                        Text(dateRangeString)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Button(action: onCreate) {
                        Text("Create it now")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [.orange, .red.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Capsule())
                            .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(appChromeBaseRadius: 24)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(appChromeBaseRadius: 24)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // X Button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(12)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .padding(12)
        }
    }
    
    private var dateRangeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        if calendar.isDate(reminder.startDate, inSameDayAs: reminder.endDate) {
            return formatter.string(from: reminder.startDate)
        } else {
            return "\(formatter.string(from: reminder.startDate)) - \(formatter.string(from: reminder.endDate))"
        }
    }
    
    private let calendar = Calendar.current
}
