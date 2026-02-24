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
    @FocusState private var isFocused: Bool
    @State private var showSuggestions: Bool = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Place name", text: $editedTitle)
                            .focused($isFocused)
                            .autocorrectionDisabled()
                            .onChange(of: isFocused) { _, focused in
                                if focused {
                                    showSuggestions = true
                                    searchViewModel.query = editedTitle
                                }
                            }
                            .onChange(of: editedTitle) { oldValue, newValue in
                                if oldValue == placeTitle && newValue.hasPrefix(placeTitle) && newValue.count > oldValue.count {
                                    editedTitle = String(newValue.dropFirst(placeTitle.count))
                                } else if showSuggestions {
                                    searchViewModel.query = newValue
                                }
                            }
                        
                        if !editedTitle.isEmpty {
                            Button {
                                editedTitle = ""
                                searchViewModel.query = ""
                                isFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if showSuggestions && !searchViewModel.suggestions.isEmpty {
                    Section("Nearby Suggestions") {
                        ForEach(Array(searchViewModel.suggestions.enumerated()), id: \.offset) { _, suggestion in
                            Button {
                                showSuggestions = false
                                isFocused = false
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
                    .foregroundStyle(editedTitle != placeTitle ? .blue : .primary)
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
