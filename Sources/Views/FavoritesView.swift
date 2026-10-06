import SwiftUI

struct FavoritesView: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(AppState.self) private var app
    @State private var adding = false

    var body: some View {
        List {
            if favorites.items.isEmpty {
                ContentUnavailableView("Nothing saved yet", systemImage: "star",
                                       description: Text("Save stops from their departure board, or add places here."))
            }
            if !favorites.stops.isEmpty {
                Section("Stops") {
                    ForEach(favorites.stops) { s in
                        NavigationLink {
                            StopDeparturesView(stopId: s.stopId ?? s.id, name: s.name, coordinate: s.coordinate)
                        } label: {
                            PlaceLabel(name: s.name, subtitle: s.subtitle, isStop: true)
                        }
                    }
                    .onDelete { idx in favorites.remove(idx.map { favorites.stops[$0].id }) }
                }
            }
            if !favorites.places.isEmpty {
                Section("Places") {
                    ForEach(favorites.places) { p in
                        Button { app.route(to: p) } label: {
                            PlaceLabel(name: p.name, subtitle: p.subtitle, isStop: false)
                        }
                    }
                    .onDelete { idx in favorites.remove(idx.map { favorites.places[$0].id }) }
                }
            }
            Section("About") {
                AttributionFooter()
                Text("Publit is open source and free. No account, no ads, no tracking. Favorites stay on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Saved")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Label("Add", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $adding) {
            PlaceSearchView(title: "Save a place", allowCurrentLocation: false) { endpoint in
                if case .place(let p) = endpoint, !favorites.contains(p.id) { favorites.toggle(p) }
            }
        }
    }
}
