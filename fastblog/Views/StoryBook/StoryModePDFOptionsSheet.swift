//
//  StoryModePDFOptionsSheet.swift
//  fastblog
//
//  PDF options sheet for Story Mode export. Font Style and Photo Style
//  options are present in the UI but not yet wired up to the export pipeline.
//

import SwiftUI

struct StoryModePDFOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onExport: () -> Void

    // Internal state — UI only, not yet connected to export
    @State private var selectedFontTheme: FontTheme = .classic
    @State private var photoShapes: PDFPhotoShapeOptions = PDFPhotoShapeOptions()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    fontThemeSection
                    photoShapeSection
                    exportButton
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("PDF Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Font Theme Section

    private var fontThemeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Font Style", icon: "textformat")

            VStack(spacing: 0) {
                ForEach(FontTheme.allCases, id: \.self) { theme in
                    optionRow(
                        title: theme.label,
                        subtitle: theme.subtitle,
                        isSelected: selectedFontTheme == theme
                    ) {
                        selectedFontTheme = theme
                    }
                    if theme != FontTheme.allCases.last {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Photo Shape Section

    private var photoShapeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Photo Style", icon: "photo")

            // Row 1: left + right columns (paired photos)
            HStack(spacing: 10) {
                photoShapeCell(
                    label: "Left",
                    sublabel: "Paired row",
                    shape: photoShapes.leftShape
                ) { photoShapes.leftShape = photoShapes.leftShape.next() }

                photoShapeCell(
                    label: "Right",
                    sublabel: "Paired row",
                    shape: photoShapes.rightShape
                ) { photoShapes.rightShape = photoShapes.rightShape.next() }
            }

            // Row 2: solo photo (full-row single)
            photoShapeCell(
                label: "Solo",
                sublabel: "Single or last photo",
                shape: photoShapes.singleShape
            ) { photoShapes.singleShape = photoShapes.singleShape.next() }

            Text("Tap a cell to cycle: Rounded → Circle → Rectangle")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Button {
            dismiss()
            onExport()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                Text("Export PDF")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Photo Shape Cell

    private func photoShapeCell(
        label: String,
        sublabel: String,
        shape: PhotoShape,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                shapePreview(shape)
                    .frame(width: 52, height: 52)

                VStack(spacing: 2) {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(shape.label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                    Text(sublabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: shape)
    }

    // MARK: - Shape Preview

    @ViewBuilder
    private func shapePreview(_ shape: PhotoShape) -> some View {
        let fill = Color.accentColor.opacity(0.18)
        let stroke = Color.accentColor
        switch shape {
        case .rounded:
            RoundedRectangle(cornerRadius: 5)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(stroke, lineWidth: 1.5))

        case .squircle:
            RoundedRectangle(cornerRadius: 14)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(stroke, lineWidth: 1.5))

        case .circle:
            Circle()
                .fill(fill)
                .overlay(Circle().stroke(stroke, lineWidth: 1.5))

        case .rectangle:
            Rectangle()
                .fill(fill)
                .overlay(Rectangle().stroke(stroke, lineWidth: 1.5))

        case .arch:
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let r = w / 2
                archPath(width: w, height: h, radius: r)
                    .fill(fill)
                    .overlay(archPath(width: w, height: h, radius: r).stroke(stroke, lineWidth: 1.5))
            }

        case .diamond:
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                diamondPath(width: w, height: h)
                    .fill(fill)
                    .overlay(diamondPath(width: w, height: h).stroke(stroke, lineWidth: 1.5))
            }

        case .hexagon:
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                hexagonPath(width: w, height: h)
                    .fill(fill)
                    .overlay(hexagonPath(width: w, height: h).stroke(stroke, lineWidth: 1.5))
            }
        }
    }

    // MARK: - Custom Shape Paths

    private func archPath(width: CGFloat, height: CGFloat, radius: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: height))
            p.addLine(to: CGPoint(x: 0, y: height / 2))
            p.addArc(center: CGPoint(x: width / 2, y: height / 2),
                     radius: radius,
                     startAngle: .degrees(180), endAngle: .degrees(0),
                     clockwise: true)
            p.addLine(to: CGPoint(x: width, y: height))
            p.closeSubpath()
        }
    }

    private func diamondPath(width: CGFloat, height: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: width / 2, y: 0))
            p.addLine(to: CGPoint(x: width, y: height / 2))
            p.addLine(to: CGPoint(x: width / 2, y: height))
            p.addLine(to: CGPoint(x: 0, y: height / 2))
            p.closeSubpath()
        }
    }

    private func hexagonPath(width: CGFloat, height: CGFloat) -> Path {
        Path { p in
            let cx = width / 2, cy = height / 2
            let r = min(width, height) / 2
            for i in 0..<6 {
                let angle = CGFloat(-Double.pi / 2) + CGFloat(i) * CGFloat(Double.pi / 3)
                let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }

    // MARK: - Shared Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.0, green: 0.85, blue: 1.0),
                             Color(red: 0.2, green: 0.5, blue: 1.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }

    private func optionRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color(uiColor: .tertiarySystemGroupedBackground))
                        .frame(width: 32, height: 32)
                    Image(systemName: isSelected ? "checkmark" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
