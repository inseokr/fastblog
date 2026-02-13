//
//  EditPlaceStopNameSheet.swift
//  fastblog
//

import MapKit
import SwiftUI

struct EditPlaceStopNameSheet: View {
    @Binding var placeTitle: String
    var location: CLLocationCoordinate2D?
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var searchViewModel = PlaceSearchViewModel()
    @State private var editedTitle: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Place name", text: $editedTitle)
                        .autocorrectionDisabled()
                        .onChange(of: editedTitle) { _, newValue in
                            searchViewModel.query = newValue
                        }
                }

                if !searchViewModel.suggestions.isEmpty {
                    Section("Nearby Suggestions") {
                        ForEach(Array(searchViewModel.suggestions.enumerated()), id: \.offset) { _, suggestion in
                            Button {
                                editedTitle = suggestion.title
                                searchViewModel.suggestions = []
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(suggestion.title)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(suggestion.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                if !editedTitle.isEmpty {
                    Section {
                        if let encoded = editedTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text("Search on Google")
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    }
                }
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
                searchViewModel.setBiasLocation(location)
            }
            .preferredColorScheme(.dark)
        }
    }
}

#Preview {
    EditPlaceStopNameSheet(placeTitle: .constant("Iceland Ring Road"), location: nil, onSave: { _ in })
}
