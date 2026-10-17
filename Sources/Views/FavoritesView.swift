import SwiftUI

struct FavoritesView: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(AppState.self) private var app
    @Environment(TripStore.self) private var trips
    @State private var adding = false
    @State private var settingRole: PlaceRole?

    var body: some View {
        List {
            Section("Home and Work") {
                ForEach(PlaceRole.allCases, id: \.self) { role in
                    if let p = favorites.place(for: role) {
                        Button { app.route(to: p) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: role.symbol).foregroundStyle(Color.ink).frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(role.title).foregroundStyle(.primary)
                                    Text(p.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { favorites.clear(role) } label: { Label("Remove", systemImage: "trash") }
                            Button { settingRole = role } label: { Label("Change", systemImage: "pencil") }
                        }
                        .accessibilityHint("Plans a route to \(role.title)")
                    } else {
                        Button { settingRole = role } label: {
                            Label("Set \(role.title)", systemImage: role.symbol)
                        }
                    }
                }
            }

            upcomingTrips

            Section("Lines") {
                NavigationLink { LinesView() } label: {
                    Label(L10n.t("Find a line"), systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("findLine")
                if !favorites.lines.isEmpty {
                    ForEach(favorites.lines) { line in
                        NavigationLink {
                            LineDetailView(line: LineRef(saved: line))
                        } label: {
                            HStack(spacing: 10) {
                                LineBadge(line)
                                Text(L10n.f("At %@", line.stopName)).lineLimit(1)
                            }
                        }
                    }
                    .onDelete { idx in favorites.removeLines(idx.map { favorites.lines[$0].id }) }
                }
            }
            if favorites.stops.isEmpty && favorites.places.isEmpty && favorites.lines.isEmpty {
                Section {
                    EmptyState(title: L10n.t("Nothing else saved yet"), systemImage: "star",
                               message: L10n.t("Save stops from their departure board, lines from a trip, or add places with +."))
                }
            }
            if !favorites.stops.isEmpty {
                Section("Stops") {
                    ForEach(favorites.stops) { s in
                        NavigationLink {
                            StopDeparturesView(stopId: s.stopId ?? s.id, name: s.name, coordinate: s.coordinate, exact: s.exact == true)
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
                        .swipeActions(edge: .leading) {
                            Button { favorites.set(p, as: .home) } label: { Label("Home", systemImage: "house") }.tint(Color.inkAction)
                            Button { favorites.set(p, as: .work) } label: { Label("Work", systemImage: "briefcase") }.tint(Color.inkAction)
                        }
                    }
                    .onDelete { idx in favorites.remove(idx.map { favorites.places[$0].id }) }
                }
            }
        }
        .inkList()
        .navigationTitle("Saved")
        .screenTrail("Saved")
        .withSettingsButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Label("Add", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $adding) {
            PlaceSearchView(title: "Save a place", allowCurrentLocation: false) { endpoint in
                if case .place(let p) = endpoint, !favorites.contains(p) { favorites.toggle(p) }
            }
        }
        .sheet(item: $settingRole) { role in
            PlaceSearchView(title: "Set \(role.title)", allowCurrentLocation: false) { endpoint in
                if case .place(let p) = endpoint { favorites.set(p, as: role) }
            }
        }
    }

    /// Saved trips still to come, right below Home and Work; past ones on their own screen.
    @ViewBuilder
    private var upcomingTrips: some View {
        let upcoming = trips.upcoming()
        Section {
            ForEach(upcoming) { t in
                NavigationLink { SavedTripView(tripId: t.id) } label: { SavedTripRow(trip: t) }
            }
            .onDelete { idx in idx.map { upcoming[$0].id }.forEach { id in
                LeaveReminder.cancel(id); Task { await LiveTripActivity.end(id) }; trips.remove(id)
            } }
            if !trips.past().isEmpty {
                NavigationLink { PastTripsView() } label: {
                    Label("Past trips", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("pastTrips")
            }
        } header: {
            Text("Upcoming trips")
        } footer: {
            if upcoming.isEmpty {
                Text("Save a route to see it here, add it to your calendar and get a reminder when to leave.")
            }
        }
    }
}

/// Trips that are over, newest first. Swipe right to plan the same route again next week.
struct PastTripsView: View {
    @Environment(AppState.self) private var app
    @Environment(TripStore.self) private var trips

    var body: some View {
        let past = Array(trips.past().prefix(50))
        List {
            ForEach(past) { t in
                NavigationLink { SavedTripView(tripId: t.id) } label: { SavedTripRow(trip: t).opacity(0.7) }
                    .swipeActions(edge: .leading) {
                        Button { planAgain(t) } label: { Label("Plan again", systemImage: "arrow.clockwise") }
                            .tint(Color.inkAction)
                    }
            }
            .onDelete { idx in idx.map { past[$0].id }.forEach(trips.remove) }
        }
        .inkList()
        .overlay {
            if past.isEmpty { ContentUnavailableView("Past trips", systemImage: "clock.arrow.circlepath") }
        }
        .navigationTitle("Past trips")
        .screenTrail("Past trips")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Same route again: same places, next week at the same time, in the Plan tab.
    private func planAgain(_ t: SavedTrip) {
        app.plan.from = .place(SavedPlace(id: "trip-from-\(t.id)", name: t.fromName, subtitle: nil,
            lat: t.itinerary.legs.first?.from.lat ?? 0, lon: t.itinerary.legs.first?.from.lon ?? 0, stopId: nil))
        app.plan.to = .place(SavedPlace(id: "trip-to-\(t.id)", name: t.toName, subtitle: nil,
            lat: t.itinerary.legs.last?.to.lat ?? 0, lon: t.itinerary.legs.last?.to.lon ?? 0, stopId: nil))
        app.plan.timeMode = .departAt
        app.plan.date = PlanView.nextOccurrence(of: t.startTime)
        app.plan.searchStarted = true
        app.tab = .plan
    }
}
