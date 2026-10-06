import SwiftUI

struct StopGroup: Identifiable {
    let id: String
    let name: String
    let coordinate: LatLon
    var departures: [StopTime]
    var distance: Double?
}

struct NearbyView: View {
    @Environment(LocationManager.self) private var location
    @State private var groups: [StopGroup] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Rounded position (~100 m) so small GPS jitter does not trigger reloads.
    private var locationKey: String {
        guard let c = location.coordinate else { return "none" }
        return String(format: "%.3f,%.3f", c.lat, c.lon)
    }

    var body: some View {
        List {
            if location.isDenied {
                ContentUnavailableView("Location is off",
                                       systemImage: "location.slash",
                                       description: Text("Allow location access in Settings to see departures near you. Trip planning works without it."))
            } else if groups.isEmpty {
                if let errorMessage {
                    ContentUnavailableView("Departures unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else if isLoading || location.coordinate == nil {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    ContentUnavailableView("No departures nearby", systemImage: "tram",
                                           description: Text("No public transport stops within 1.5 km."))
                }
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.departures.prefix(5)) { DepartureRow(stopTime: $0) }
                    NavigationLink {
                        StopDeparturesView(stopId: group.id, name: group.name, coordinate: group.coordinate)
                    } label: {
                        Text("All departures").font(.subheadline)
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        if let d = group.distance { Text(Fmt.distance(meters: d)) }
                    }
                }
            }

            if !groups.isEmpty {
                Section { AttributionFooter() }
            }
        }
        .navigationTitle("Nearby")
        .refreshable { await load() }
        .task(id: locationKey) {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func load() async {
        guard let here = location.coordinate else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var res = try await TransitousClient.shared.departures(near: here, radius: 500, count: 80)
            if res.stopTimes.isEmpty {
                res = try await TransitousClient.shared.departures(near: here, radius: 1500, count: 80)
            }
            groups = Self.group(res.stopTimes, around: here)
            errorMessage = nil
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
    }

    static func group(_ stopTimes: [StopTime], around here: LatLon) -> [StopGroup] {
        var byId: [String: StopGroup] = [:]
        var order: [String] = []
        for st in stopTimes.sorted(by: { $0.departureTime < $1.departureTime }) {
            let key = st.place.stationId
            if byId[key] == nil {
                byId[key] = StopGroup(id: key, name: st.place.name, coordinate: st.place.coordinate,
                                      departures: [], distance: here.distance(to: st.place.coordinate))
                order.append(key)
            }
            byId[key]?.departures.append(st)
        }
        return order.compactMap { byId[$0] }
            .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }
}

struct StopDeparturesView: View {
    let stopId: String
    let name: String
    let coordinate: LatLon

    @Environment(FavoritesStore.self) private var favorites
    @Environment(AppState.self) private var app
    @State private var departures: [StopTime] = []
    @State private var alerts: [Alert] = []
    @State private var errorMessage: String?
    @State private var loaded = false

    private var saved: SavedPlace {
        SavedPlace(id: stopId, name: name, subtitle: nil, lat: coordinate.lat, lon: coordinate.lon, stopId: stopId)
    }

    var body: some View {
        List {
            if !alerts.isEmpty {
                Section("Alerts") {
                    ForEach(alerts, id: \.self) { a in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.headerText).font(.subheadline.weight(.semibold))
                            if !a.descriptionText.isEmpty {
                                Text(a.descriptionText).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                if let errorMessage, departures.isEmpty {
                    Text(errorMessage).foregroundStyle(.secondary)
                } else if !loaded {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if departures.isEmpty {
                    Text("No upcoming departures.").foregroundStyle(.secondary)
                }
                ForEach(departures) { DepartureRow(stopTime: $0) }
            }
            Section { AttributionFooter() }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    app.route(to: saved)
                } label: {
                    Label("Route here", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
                Button {
                    favorites.toggle(saved)
                } label: {
                    Label("Save", systemImage: favorites.contains(stopId) ? "star.fill" : "star")
                }
            }
        }
        .refreshable { await load() }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func load() async {
        do {
            let res = try await TransitousClient.shared.departures(stopId: stopId, count: 40)
            departures = res.stopTimes
            alerts = Array(Set(res.place?.alertsList ?? []))
            errorMessage = nil
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
        loaded = true
    }
}
