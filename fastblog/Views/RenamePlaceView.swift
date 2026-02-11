//
//  RenamePlaceView.swift
//  Capper
//

import SwiftUI

struct RenamePlaceView: View {
    @State private var placeTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(placeTitle: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _placeTitle = State(initialValue: placeTitle)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Place name", text: $placeTitle)
                }
            }
            .navigationTitle("Rename Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(placeTitle.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
            }
        }
    }
}

#Preview {
    RenamePlaceView(placeTitle: "Central Park", onSave: { _ in }, onCancel: {})
}
