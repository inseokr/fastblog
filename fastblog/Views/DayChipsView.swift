//
//  DayChipsView.swift
//  Capper
//

import SwiftUI

struct DayChipsView: View {
    let days: [TripDay]
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        DayChip(
                            title: "Day \(day.dayIndex)",
                            isSelected: selectedIndex == index
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedIndex = index
                            }
                            proxy.scrollTo(day.id, anchor: .center)
                        }
                        .id(day.id)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct DayChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.orange : Color(uiColor: .tertiarySystemFill))
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DayChipsView(
        days: [
            TripDay(dayIndex: 1, dateText: "Jan 1", photos: []),
            TripDay(dayIndex: 2, dateText: "Jan 2", photos: [])
        ],
        selectedIndex: .constant(0)
    )
}
