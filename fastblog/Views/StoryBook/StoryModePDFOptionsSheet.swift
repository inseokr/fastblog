//
//  StoryModePDFOptionsSheet.swift
//  fastblog
//
//  PDF options sheet for Story Mode export.
//

import SwiftUI

struct StoryModePDFOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onExport: () -> Void

    @AppStorage("pdfExportOptions") private var pdfExportOptionsData: Data = (try? JSONEncoder().encode(PDFExportOptions())) ?? Data()
    @State private var pending: PDFExportOptions = PDFExportOptions()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    fontThemeSection
                    colorStyleSection
                    exportButton
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Book Options")
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
        .onAppear {
            pending = (try? JSONDecoder().decode(PDFExportOptions.self, from: pdfExportOptionsData)) ?? PDFExportOptions()
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
                        isSelected: pending.fontTheme == theme
                    ) {
                        pending.fontTheme = theme
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

    // MARK: - Color Style Section

    private var colorStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Color Style", icon: "circle.lefthalf.filled")

            VStack(spacing: 0) {
                ForEach(BlogColor.allCases, id: \.self) { style in
                    optionRow(
                        title: style.label,
                        subtitle: style.subtitle,
                        isSelected: pending.colorStyle == style
                    ) {
                        pending.colorStyle = style
                    }
                    if style != BlogColor.allCases.last {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Button {
            if let data = try? JSONEncoder().encode(pending) {
                pdfExportOptionsData = data
            }
            dismiss()
            onExport()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                Text("Open Book")
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
