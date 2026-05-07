// fastblog/Views/TransportModePickerSheet.swift
import SwiftUI

/// Pull-up sheet for choosing the travel mode between two consecutive place stops.
/// Pass `currentMode: nil` to represent "Auto-detect".
struct TransportModePickerSheet: View {
    let fromPlaceTitle: String
    let toPlaceTitle: String
    let autoDetectedMode: TravelMode?
    var currentMode: TravelMode?
    var onSelect: (TravelMode?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 12)

            // Header
            VStack(spacing: 3) {
                Text("Transport Mode")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("\(fromPlaceTitle) → \(toPlaceTitle)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.bottom, 16)

            // Auto-detect row
            modeRow(
                symbolName: autoDetectedMode?.sfSymbolName ?? "wand.and.stars",
                tintColor: autoDetectedMode.map { Color(uiColor: $0.tintColor) } ?? .secondary,
                label: "Auto-detect",
                sublabel: autoDetectedMode.map { "Currently: \($0.displayName)" },
                isSelected: currentMode == nil
            ) {
                onSelect(nil)
                dismiss()
            }

            Divider().background(Color(white: 0.25))

            // Explicit mode rows
            ForEach(TravelMode.allCases, id: \.self) { mode in
                modeRow(
                    symbolName: mode.sfSymbolName,
                    tintColor: Color(uiColor: mode.tintColor),
                    label: mode.displayName,
                    sublabel: nil,
                    isSelected: currentMode == mode
                ) {
                    onSelect(mode)
                    dismiss()
                }
                if mode != TravelMode.allCases.last {
                    Divider().background(Color(white: 0.25))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 34)
        .background(Color(white: 0.1))
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
    }

    private var sheetHeight: CGFloat {
        let rowH: CGFloat = 56
        let headerH: CGFloat = 8 + 5 + 12 + 46 + 16
        let rows = CGFloat(TravelMode.allCases.count + 1)
        return headerH + rows * rowH + (rows - 1) + 34
    }

    @ViewBuilder
    private func modeRow(
        symbolName: String,
        tintColor: Color,
        label: String,
        sublabel: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tintColor.opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(tintColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.body)
                        .foregroundColor(.white)
                    if let sub = sublabel {
                        Text(sub)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
