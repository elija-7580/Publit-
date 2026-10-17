import SwiftUI

struct NearbyView: View {
    @Environment(LocationManager.self) private var location
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TripStore.self) private var trips
    /// The live bar is showing the trip already: no second card for it.
    @Environment(\.liveBarInset) private var liveBarInset
    @State private var isVisible = false
    @State private var searching = false
    @State private var openedStop: StopTarget?
    @State private var showMap = false
    @State private var groups: [StopGroup] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// Mode filter, kept between launches ("I never take the bus").
    @AppStorage("nearbyModes") private var storedModes = ""
    /// Modes seen around here, so the chips offer only what runs nearby.
    @State private var seenGroups: Set<ModeGroup> = []
    /// Last answer, to re-filter at once when a chip is tapped.
    @State private var lastStopTimes: [StopTime] = []
    @State private var lastCenter: LatLon?
    /// Distance to the nearest departures when they are beyond `Reach.farDistance`: said above the board.
    @State private var farDistance: Double?

    private var filter: ModeFilter { ModeFilter(storageValue: storedModes) }
    private var filterBinding: Binding<ModeFilter> {
        Binding(get: { ModeFilter(storageValue: storedModes) }, set: { storedModes = $0.storageValue })
    }
    private var availableGroups: [ModeGroup] {
        ModeGroup.allCases.filter { seenGroups.contains($0) || filter.included.contains($0) }
    }

    /// Where and when the board was last requested. A refined GPS fix does not restart a running request.
    @State private var loadedCenter: LatLon?
    @State private var loadedAt = Date.distantPast
    @State private var loadedModes = ""
    @State private var loadGeneration = UUID()

    /// Reload after moving this far (metres) or after `refreshInterval` seconds.
    static let reloadDistance = 150.0
    static var refreshInterval: TimeInterval { Energy.interval(30) }

    var body: some View {
        List {
            goSection
            activeTripSection
            OfflineNote()
            if !location.isDenied, availableGroups.count > 1 || filter.isActive {
                ModeFilterBar(available: availableGroups, filter: filterBinding).chipRow()
            }
            if location.isDenied {
                ContentUnavailableView("Location is off",
                                       systemImage: "location.slash",
                                       description: Text("Allow location access in Settings to see departures near you. Trip planning works without it."))
            } else if groups.isEmpty {
                if let errorMessage {
                    ContentUnavailableView("Departures unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else if isLoading || !location.hasFix {
                    LogoLoader()
                } else if filter.isActive {
                    ContentUnavailableView {
                        Label("No departures for these modes", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text(verbatim: filter.summary ?? "")
                    } actions: {
                        Button("Show all modes") { storedModes = "" }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No departures nearby", systemImage: "tram")
                    } description: {
                        Text("No departures within 5 km. The station map shows stops further away.")
                    } actions: {
                        Button("Station map") { showMap = true }
                    }
                }
            }
            if !groups.isEmpty, let farDistance {
                // Far is not empty: the stops are listed, with how long the walk is.
                InlineNotice(text: Reach.farNote(meters: farDistance), systemImage: "figure.walk")
                    .accessibilityIdentifier("nearbyFarNote")
            }
            if !groups.isEmpty, errorMessage != nil, !Connectivity.shared.isOffline {
                Label("Couldn't refresh. Times may be out of date.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            ForEach(groups) { group in
                Section {
                    // Ink & Dot: the station heads its own card instead of a grey header above it.
                    // Tap the station for its page; the arrow plans a route there from here, now.
                    HStack(spacing: 12) {
                        Button { openedStop = StopTarget(group) } label: {
                            StopGroupHeader(group: group, nearest: group.id == groups.first?.id)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("nearbyStation")
                        Button { go(.place(StopTarget(group).place)) } label: {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.ink)
                                .frame(width: 40, height: 40)
                                .raisedKey(radius: 20)
                        }
                        .accessibilityLabel(Text("Route here"))
                        .accessibilityIdentifier("nearbyRouteHere")
                    }
                    .buttonStyle(.borderless)
                    .tint(.primary)
                    .contextMenu {
                        Button { go(.place(StopTarget(group).place)) } label: {
                            Label("Route here", systemImage: "arrow.triangle.turn.up.right.diamond")
                        }
                        Button { openedStop = StopTarget(group) } label: {
                            Label("All departures", systemImage: "list.bullet")
                        }
                    }
                    .listRowSeparator(.hidden, edges: .bottom)
                    ForEach(group.departures.prefix(5)) { st in
                        // By value: the trip stays open when the board refreshes and this row
                        // changes or leaves (the departure has gone).
                        NavigationLink(value: TripTarget(stopTime: st, stationId: group.id, stationName: group.name,
                                                         coordinate: group.coordinate)) {
                            DepartureRow(stopTime: st)
                        }
                    }
                    NavigationLink {
                        StopDeparturesView(stopId: group.id, name: group.name, coordinate: group.coordinate, exact: group.isPole)
                    } label: {
                        Text("All departures").font(.subheadline.weight(.medium))
                    }
                }
                .inkCard()
            }

        }
        .inkList()
        .tint(Color.ink)
        .navigationTitle("Nearby")
        .screenTrail("Nearby")
        .withSettingsButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMap = true } label: { Label("Station map", systemImage: "map") }
            }
        }
        .sheet(isPresented: $searching) {
            PlaceSearchView(title: "Where to?", allowCurrentLocation: false) { endpoint in go(endpoint) }
        }
        .navigationDestination(isPresented: Bindable(app).showGoNow) { GoNowView() }
        .navigationDestination(item: $openedStop) { s in
            StopDeparturesView(stopId: s.id, name: s.name, coordinate: s.coordinate, exact: s.exact)
        }
        .navigationDestination(for: TripTarget.self) { t in
            TripView(stopTime: t.stopTime, stationId: t.stationId, stationName: t.stationName, stationCoordinate: t.coordinate)
        }
        .fullScreenCover(isPresented: $showMap) { StationMapView() }
        // "Route here/from here" on a map stop switches to Plan: the map closes so Plan is visible.
        .onChange(of: app.tab) { if app.tab != .nearby { showMap = false } }
        .refreshable { await load(force: true) }
        .onChange(of: storedModes) {
            // Show the matching part of the current board at once, then ask the server for more.
            if let c = lastCenter { regroup(lastStopTimes, around: c) }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: "\(refreshEnabled)|\(storedModes)") {
            guard refreshEnabled else { return }
            if location.isDenied { app.firstBoardReady = true }
            await showLastBoard()
            // One loop for the screen. Before, every ~100 m change of the first, still improving GPS
            // fixes cancelled the running request and started over, so the board took many seconds.
            while !Task.isCancelled {
                await load()
                // Once GPS is available, one wake-up every five seconds is enough to notice
                // movement; server requests remain capped at once per 30 seconds.
                try? await Task.sleep(for: location.hasFix ? .seconds(5) : .milliseconds(500))
            }
        }
    }

    private var refreshEnabled: Bool { isVisible && scenePhase == .active && app.tab == .nearby && !showMap && !app.showGoNow }

    @ViewBuilder
    private var activeTripSection: some View {
        if let trip = trips.activeTrip, liveBarInset == 0 {
            Section("Active trip") {
                NavigationLink { SavedTripView(tripId: trip.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(trip.toName, systemImage: "location.north.circle.fill").font(.headline)
                        Text(TripStatus.at(.now, trip.itinerary).headline).font(.subheadline).foregroundStyle(.secondary)
                        if let leg = trip.itinerary.firstTransitLeg { LineBadge(leg) }
                    }
                }
                .accessibilityIdentifier("activeTrip")
            }
            .inkCard()
        }
    }

    /// "I have to get there now": route from the current location, leaving now.
    private func go(_ destination: Endpoint) {
        app.goNow.from = .currentLocation
        app.goNow.to = destination
        app.goNow.timeMode = .now
        app.showGoNow = true
    }

    @ViewBuilder
    private var goSection: some View {
        Section {
            Button { searching = true } label: {
                Label("Where to now?", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .bevelField()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Where to now? Route from your location")
            .accessibilityIdentifier("whereToNow")
            ForEach(favorites.pinned) { p in
                Button { go(.place(p)) } label: {
                    Label { Text(p.role?.title ?? p.name) + Text(verbatim: "  \(p.name)").foregroundStyle(.secondary) }
                        icon: { Image(systemName: p.role?.symbol ?? "mappin") }
                }
            }
            if let next = trips.upcoming().first, next.id != trips.activeTrip?.id,
               next.startTime.timeIntervalSinceNow < 3 * 3600 {
                NavigationLink { SavedTripView(tripId: next.id) } label: {
                    // Same weight as the other rows of this card ("Where to now?", Home, Work).
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next trip: \(next.toName)")
                        Text(TripStatus.at(.now, next.itinerary).headline).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .inkCard()
    }

    /// The last board (up to 30 min old, past departures removed) right away, so the screen is not
    /// empty while GPS and network start. It is replaced as soon as fresh times arrive.
    private func showLastBoard() async {
        guard groups.isEmpty, let last = await TransitousClient.shared.lastNearby(maxAge: 1800, modes: filter.apiValue) else { return }
        let here = location.coordinate ?? last.center
        guard here.distance(to: last.center) < 400 else { return }
        let filter = filter
        seenGroups = Set(ModeGroup.present(in: last.response.stopTimes.map(\.mode)))
        groups = StopGrouping.group(StopTime.upcoming(last.response.stopTimes).filter { filter.allows($0.mode) }, around: here)
        farDistance = Self.far(groups)
        if !groups.isEmpty { app.firstBoardReady = true }
    }

    private func regroup(_ stopTimes: [StopTime], around here: LatLon) {
        let filter = filter
        groups = StopGrouping.group(StopTime.upcoming(stopTimes).filter { filter.allows($0.mode) }, around: here)
        farDistance = Self.far(groups)
    }

    /// Distance of the nearest stop when even that one is far.
    private static func far(_ groups: [StopGroup]) -> Double? {
        guard let nearest = groups.compactMap(\.distance).min(), nearest >= Reach.farDistance else { return nil }
        return nearest
    }

    private func load(force: Bool = false) async {
        guard refreshEnabled, let here = location.coordinate else { return }
        if isLoading, !force { return }
        if !force, loadedModes == storedModes, let c = loadedCenter, here.distance(to: c) < Self.reloadDistance,
           Date().timeIntervalSince(loadedAt) < Self.refreshInterval { return }
        let generation = UUID()
        loadGeneration = generation
        isLoading = true
        defer {
            if loadGeneration == generation {
                isLoading = false
                if !app.firstBoardReady { app.firstBoardReady = true }
            }
        }
        let filter = filter
        let modes = storedModes
        do {
            // Wider and wider until something runs: 500 m, 1.5 km, 5 km. A stop 3 km away is
            // listed with its walking time instead of an empty "no departures".
            var res = StopTimesResponse(stopTimes: [], place: nil, nextPageCursor: nil)
            var radius = 0
            for r in Reach.nearbyRadii where res.stopTimes.isEmpty {
                radius = r
                res = try await TransitousClient.shared.departures(near: here, radius: r, count: 40, modes: filter.apiValue)
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            guard loadGeneration == generation else { return }
            let stopTimes = res.stopTimes
            let present = Set(ModeGroup.present(in: stopTimes.map(\.mode)))
            // A full board says what runs here; a filtered one can only add to it.
            if filter.isActive { seenGroups.formUnion(present) } else { seenGroups = present }
            lastStopTimes = stopTimes
            lastCenter = here
            // The filter may have changed while the request ran: keep to the current one.
            let current = self.filter
            let regrouped = await Task.detached(priority: .userInitiated) {
                StopGrouping.group(StopTime.upcoming(stopTimes).filter { current.allows($0.mode) }, around: here)
            }.value
            try Task.checkCancellation()
            guard loadGeneration == generation else { return }
            HangLog.shared.note("nearby loaded: \(regrouped.count) stops, \(stopTimes.count) departures, radius \(radius) m")
            groups = regrouped
            farDistance = Self.far(regrouped)
            loadedCenter = here
            loadedModes = modes
            loadedAt = Date()
            errorMessage = nil
        } catch {
            guard loadGeneration == generation else { return }
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
                // Try again soon instead of waiting for the next regular refresh.
                loadedAt = Date().addingTimeInterval(10 - Self.refreshInterval)
            } else {
                loadedCenter = nil
            }
        }
    }
}

/// Station name and distance; a street stop also says where its buses go, to tell it from the one across the road.
/// A station from the board, to open its page or route there.
struct StopTarget: Hashable, Identifiable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let exact: Bool

    init(_ group: StopGroup) {
        id = group.id; name = group.name
        lat = group.coordinate.lat; lon = group.coordinate.lon
        exact = group.isPole
    }

    var coordinate: LatLon { LatLon(lat: lat, lon: lon) }

    var place: SavedPlace {
        var p = SavedPlace(id: id, name: name, subtitle: nil, lat: lat, lon: lon, stopId: id)
        if exact { p.exact = true }
        return p
    }
}

struct StopGroupHeader: View {
    let group: StopGroup
    /// The closest stop gets the logo's dot by its distance: "you are this close".
    var nearest = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.name).font(.title3.weight(.bold))
                Spacer()
                if let d = group.distance {
                    HStack(spacing: 5) {
                        if nearest { SignatureDot(size: 7) }
                        Text(Fmt.distance(meters: d)).font(.subheadline.weight(.medium).monospacedDigit())
                        if d >= Reach.walkHintDistance {
                            // Far stops say how long the walk is, not only how far.
                            Label(L10n.f("%lld min", Reach.walkMinutes(meters: d)), systemImage: "figure.walk")
                                .font(.subheadline.weight(.medium).monospacedDigit())
                                .labelStyle(CompactLabelStyle())
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            if group.isPole, !group.directions.isEmpty {
                Label(group.directions.joined(separator: " · "), systemImage: "arrow.right")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .labelStyle(CompactLabelStyle())
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

/// Icon and text closer together than the default label.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.imageScale(.small); configuration.title }
    }
}

struct StopDeparturesView: View {
    /// Includes the other platforms of the station (feeds often split them across IDs).
    static let stationRadius = 150

    let stopId: String
    let name: String
    let coordinate: LatLon
    /// Only this street stop, not the platforms around it (the stop across the road goes the other way).
    var exact = false

    enum Mode: String, CaseIterable, Identifiable { case departures, lines; var id: String { rawValue } }

    @Environment(FavoritesStore.self) private var favorites
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var departures: [StopTime] = []
    @State private var alerts: [Alert] = []
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var lastUpdated: Date?
    @State private var mode: Mode = .departures
    @State private var filter = ModeFilter()
    /// Modes that run here, from the last unfiltered answer.
    @State private var available: [ModeGroup] = []

    private var saved: SavedPlace {
        var p = SavedPlace(id: stopId, name: name, subtitle: nil, lat: coordinate.lat, lon: coordinate.lon, stopId: stopId)
        if exact { p.exact = true }
        return p
    }

    /// Filtered right away on a chip tap; the reload then brings more of the chosen modes.
    private var shown: [StopTime] { departures.filter { filter.allows($0.mode) } }

    var body: some View {
        List {
            if !alerts.isEmpty {
                Section("Alerts") {
                    ServiceAlertsView(alerts: alerts)
                }
            }
            Section {
                if exact, !departures.isEmpty {
                    Label(StopGrouping.directions(departures, limit: 3).joined(separator: " · "), systemImage: "arrow.right")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.f("Towards %@", StopGrouping.directions(departures, limit: 3).joined(separator: ", ")))
                }
                WalkThereRow(name: name, coordinate: coordinate)
                // Both open the Plan tab: "here" as destination or as start.
                HStack(spacing: 16) {
                    Button { app.route(to: saved) } label: {
                        Label("Route here", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                    .accessibilityIdentifier("routeHere")
                    Spacer(minLength: 0)
                    Button { app.route(from: saved) } label: {
                        Label("Route from here", systemImage: "arrow.up.forward.circle")
                    }
                    .accessibilityIdentifier("routeFromHere")
                }
                .buttonStyle(.borderless)
                // The departure board as a link anyone can open (live on their phone, or on the map).
                ShareLink(item: ShareLinks.web(.stop(id: stopId, name: name, lat: coordinate.lat, lon: coordinate.lon)),
                          subject: Text(verbatim: name), message: Text(verbatim: name)) {
                    Label("Share departures", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("shareDepartures")
                Picker("View", selection: $mode) {
                    Text("Departures").tag(Mode.departures)
                    Text("Lines").tag(Mode.lines)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("stopViewMode")
                if available.count > 1 || filter.isActive {
                    ModeFilterBar(available: available, filter: $filter)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }
            Section {
                OfflineNote()
                if let errorMessage, departures.isEmpty {
                    Text(errorMessage).foregroundStyle(.secondary)
                } else if errorMessage != nil, let lastUpdated {
                    Label("Couldn't refresh. Showing times from \(Fmt.time(lastUpdated)).", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if !loaded {
                    LogoLoader()
                } else if shown.isEmpty {
                    if filter.isActive {
                        Text("No departures for these modes").foregroundStyle(.secondary)
                        Button("Show all modes") { filter = .all }
                    } else {
                        Text("No upcoming departures.").foregroundStyle(.secondary)
                    }
                }
                switch mode {
                case .departures:
                    ForEach(shown) { st in
                        NavigationLink {
                            TripView(stopTime: st, stationId: stopId, stationName: name, stationCoordinate: coordinate)
                        } label: { DepartureRow(stopTime: st) }
                    }
                case .lines:
                    ForEach(LineGrouping.lines(shown)) { line in
                        let savedLine = SavedLine(stopTime: line.first, stopId: stopId, stopName: name, at: coordinate)
                        NavigationLink {
                            LineDetailView(line: LineRef(saved: savedLine), initialDepartures: shown)
                        } label: { LineAtStopRow(line: line) }
                        .swipeActions {
                            Button { favorites.toggle(savedLine) } label: {
                                Label(favorites.containsLine(savedLine.id) ? L10n.t("Saved line") : L10n.t("Save line"),
                                      systemImage: favorites.containsLine(savedLine.id) ? "star.slash" : "star")
                            }
                            .tint(Color.inkAction)
                        }
                    }
                }
            }
        }
        .inkList()
        .navigationTitle(name)
        .screenTrail("Stop departures")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggle(saved)
                } label: {
                    Label("Save", systemImage: favorites.contains(saved) ? "star.fill" : "star")
                }
            }
        }
        .refreshable { await load() }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: "\(filter)|\(scenePhase)|\(app.tab)|\(isVisible)") {
            guard isVisible, scenePhase == .active else { return }
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: Energy.duration(30))
            }
        }
    }

    private func load() async {
        let filter = filter
        do {
            // More departures for the lines view: every line of a big station should appear.
            let res = try await TransitousClient.shared.departures(stopId: stopId, count: 60, radius: exact ? nil : Self.stationRadius,
                                                                  modes: filter.apiValue)
            guard !Task.isCancelled else { return }
            departures = StopTime.upcoming(res.stopTimes)
            if !filter.isActive { available = ModeGroup.present(in: res.stopTimes.map(\.mode)) }
            alerts = Alert.relevant((res.place?.alertsList ?? []) + res.stopTimes.flatMap { $0.place.alertsList })
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
        loaded = true
    }
}

/// One line at a station: badge, and the next departures per direction.
struct LineAtStopRow: View {
    let line: LineAtStop

    var body: some View {
        let now = Ticker.minute.now
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                LineBadge(line.first)
                if let detail = line.first.serviceDetail {
                    Text(verbatim: detail).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            ForEach(Array(line.byDirection(perDirection: 3).prefix(3).enumerated()), id: \.offset) { _, dir in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(verbatim: dir.direction ?? L10n.t("Direction unavailable"))
                        .font(.subheadline).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(verbatim: Self.times(dir.departures, now: now))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        .lineLimit(1).fixedSize()
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lineAtStop")
    }

    /// "now · 8 min · 14:35": minutes for the next hour, then clock times. Cancelled ones are left out.
    static func times(_ departures: [StopTime], now: Date) -> String {
        departures.filter { !$0.isCancelled }.map { st in
            let m = Int(ceil(st.departureTime.timeIntervalSince(now) / 60))
            if m <= 0 { return L10n.t("now") }
            if m < 60 { return L10n.f("%lld min", m) }
            return Fmt.time(st.departureTime, tz: st.place.tz)
        }.joined(separator: " · ")
    }
}
