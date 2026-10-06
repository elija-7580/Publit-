import Foundation
import Observation

/// A saved place or stop. Stored locally on the device only.
struct SavedPlace: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var subtitle: String?
    var lat: Double
    var lon: Double
    var stopId: String?

    var isStop: Bool { stopId != nil }
    var coordinate: LatLon { LatLon(lat: lat, lon: lon) }

    init(id: String, name: String, subtitle: String?, lat: Double, lon: Double, stopId: String?) {
        self.id = id; self.name = name; self.subtitle = subtitle
        self.lat = lat; self.lon = lon; self.stopId = stopId
    }

    init(match: GeocodeMatch) {
        self.init(id: match.id, name: match.name, subtitle: match.subtitle,
                  lat: match.lat, lon: match.lon, stopId: match.isStop ? match.id : nil)
    }

    init(stop place: Place) {
        let sid = place.stationId
        self.init(id: sid, name: place.name, subtitle: nil, lat: place.lat, lon: place.lon, stopId: sid)
    }
}

@MainActor
@Observable
final class FavoritesStore {
    private(set) var items: [SavedPlace] = []
    private let key = "publit.favorites.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            items = decoded
        }
    }

    var stops: [SavedPlace] { items.filter(\.isStop) }
    var places: [SavedPlace] { items.filter { !$0.isStop } }

    func contains(_ id: String) -> Bool { items.contains { $0.id == id } }

    func toggle(_ place: SavedPlace) {
        if contains(place.id) { items.removeAll { $0.id == place.id } } else { items.append(place) }
        persist()
    }

    func remove(_ ids: [String]) {
        items.removeAll { ids.contains($0.id) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }
}
