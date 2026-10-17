import SwiftUI

/// Nearby → "Where to now?": best ways from here, leaving now, kept live.
struct GoNowView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationManager.self) private var location
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var selectedId: String?

    var body: some View {
        let plan = app.goNow
        let its = plan.sortedItineraries
        let windowStart = its.map(\.startTime).min() ?? .now
        let windowEnd = its.map(\.endTime).max() ?? .now
        List {
            if !its.isEmpty {
                CompareMapView(itineraries: its, selectedId: selectedId ?? its.first?.routeKey)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                RouteOptionsButton()
            }
            Section {
                OfflineNote()
                if plan.isLoading && its.isEmpty {
                    LogoLoader()
                } else if let msg = plan.errorMessage, its.isEmpty {
                    Text(msg).foregroundStyle(.secondary)
                }
                if let note = plan.walkNote, !its.isEmpty {
                    // Found only with a longer walk: say so, the walk is part of the decision.
                    Label(note, systemImage: "figure.walk")
                        .font(.footnote).foregroundStyle(Color.delay)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("longWalkNote")
                }
                if !its.isEmpty { ConnectionLegendRow(start: windowStart, end: windowEnd, tz: its.first?.legs.first?.from.tz) }
                ForEach(its) { it in
                    NavigationLink {
                        ItineraryDetailView(itinerary: it, fromName: L10n.t("Current location"), toName: plan.to?.title ?? "")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let dep = it.firstDeparture {
                                Text(leaveText(it, firstDeparture: dep))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(it.startTime < .now.addingTimeInterval(120) ? Color.delay : .secondary)
                            } else {
                                Text("Walk all the way").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            ItineraryRow(itinerary: it, windowStart: windowStart, windowEnd: windowEnd)
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded { selectedId = it.routeKey })
                }
                if plan.canLoadMore {
                    Button("Later connections") { Task { await plan.loadMore() } }
                }
            } header: {
                HStack {
                    Text("From your location")
                    Spacer()
                    if !its.isEmpty { RouteSortMenu() }
                }
            } footer: {
                if let note = its.first.flatMap({ Fmt.foreignZoneNote(tz: $0.legs.first?.from.tz, at: $0.startTime) }) {
                    Label(note, systemImage: "clock")
                }
            }
            StreetComparisonSection(comparisons: plan.comparisons,
                                    bestTransit: its.filter { !$0.isDirect }.map(\.duration).min(),
                                    fromName: L10n.t("Current location"), toName: plan.to?.title ?? "")
        }
        .inkList()
        .navigationTitle(plan.to?.title ?? L10n.t("Route"))
        .screenTrail("Go now")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await plan.search(current: location.coordinate, locationDenied: location.isDenied, silent: true) }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: "\(plan.queryKey)|\(scenePhase)|\(isVisible)") {
            guard isVisible, scenePhase == .active else { return }
            await plan.search(current: location.coordinate, locationDenied: location.isDenied)
            while !Task.isCancelled {
                try? await Task.sleep(for: PlanView.refreshInterval)
                guard !Task.isCancelled else { break }
                await plan.search(current: location.coordinate, locationDenied: location.isDenied, silent: true)
            }
        }
        .onChange(of: location.hasFix) { _, hasFix in
            if hasFix, plan.itineraries.isEmpty { Task { await plan.search(current: location.coordinate) } }
        }
    }

    private func leaveText(_ it: Itinerary, firstDeparture: Date) -> String {
        let mins = Int(ceil(it.startTime.timeIntervalSinceNow / 60))
        return mins <= 0 ? L10n.t("Leave now") : L10n.f("Leave in %lld min", mins)
    }
}
