import SwiftUI

struct PlaceSearchView: View {
    let title: String
    let allowCurrentLocation: Bool
    let onSelect: (Endpoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(FavoritesStore.self) private var favorites
    @Environment(LocationManager.self) private var location
    @State private var query = ""
    @State private var results: [GeocodeMatch] = []
    @State private var errorMessage: String?
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if allowCurrentLocation && !location.isDenied {
                        Button { select(.currentLocation) } label: {
                            Label("Current location", systemImage: "location.fill")
                        }
                    }
                    if !favorites.items.isEmpty {
                        Section("Saved") {
                            ForEach(favorites.items) { f in
                                Button { select(.place(f)) } label: {
                                    PlaceLabel(name: f.name, subtitle: f.subtitle, isStop: f.isStop)
                                }
                            }
                        }
                    }
                } else {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.secondary)
                    } else if results.isEmpty && !isSearching {
                        Text("No matches.").foregroundStyle(.secondary)
                    }
                    ForEach(results) { m in
                        let saved = SavedPlace(match: m)
                        Button { select(.place(saved)) } label: {
                            PlaceLabel(name: m.name, subtitle: m.subtitle, isStop: m.isStop)
                        }
                        .swipeActions {
                            Button { favorites.toggle(saved) } label: {
                                Label("Save", systemImage: favorites.contains(saved.id) ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Address, stop or place")
            .autocorrectionDisabled()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task(id: query) { await search() }
        }
    }

    private func select(_ endpoint: Endpoint) {
        onSelect(endpoint)
        dismiss()
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; errorMessage = nil; return }
        // Debounce: the task is cancelled when the query changes again.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let r = try await TransitousClient.shared.geocode(text, near: location.coordinate)
            guard !Task.isCancelled else { return }
            results = r
            errorMessage = nil
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PlaceLabel: View {
    let name: String
    let subtitle: String?
    let isStop: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isStop ? "tram.circle.fill" : "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(isStop ? Color.blue : Color.red)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).foregroundStyle(.primary).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
