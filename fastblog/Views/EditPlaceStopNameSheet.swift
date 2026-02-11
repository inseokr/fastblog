//
//  EditPlaceStopNameSheet.swift
//  Capper
//

import SwiftUI

struct EditPlaceStopNameSheet: View {
    @Binding var placeTitle: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var editedTitle: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Place name", text: $editedTitle)
                    .autocorrectionDisabled()
            }
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? "Stop" : trimmed)
                        dismiss()
                    }
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                editedTitle = placeTitle
            }
            .preferredColorScheme(.dark)
        }
    }
}

#Preview {
    EditPlaceStopNameSheet(placeTitle: .constant("Iceland Ring Road"), onSave: { _ in })
}
