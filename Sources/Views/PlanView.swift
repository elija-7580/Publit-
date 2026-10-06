import SwiftUI

struct PlanView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationManager.self) private var location
    @State private var picking: PickTarget?
    @State private var showMap = false
    @State private var selectedId: String?

    enum PickTarget: String, Identifiable { case from, to; var id: String { rawValue } }

    var body: some View {
        @Bindable var plan = app.plan
        List {
            Section {
                endpointButton(label: "From", endpoint: plan.from, target: .from)
                endpointButton(label: "To", endpoint: plan.to, target: .to)
                Picker("When", selection: $plan.timeMode) {
                    ForEach(TimeMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if plan.timeMode != .now {
                    DatePicker("Time", selection: $plan.date)
                }
            }

            if plan.to != nil {
                resultsSection(plan)
            }
        }
        .navigationTitle("Plan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.plan.swap() } label: { Label("Swap", systemImage: "arrow.up.arrow.down") }
                    .disabled(plan.to == nil)
            }
        }
        .sheet(item: $picking) { target in
            PlaceSearchView(title: target == .from ? "From" : "To", allowCurrentLocation: true) { endpoint in
                if target == .from { app.plan.from = endpoint } else { app.plan.to = endpoint }
            }
        }
        .task(id: app.plan.queryKey) {
            selectedId = nil
            await app.plan.search(current: location.coordinate)
        }
        .onChange(of: location.coordinate == nil) { _, isNil in
            // Retry once the first location fix arrives.
            if !isNil, app.plan.itineraries.isEmpty, app.plan.to != nil {
                Task { await app.plan.search(current: location.coordinate) }
            }
        }
    }

    private func endpointButton(label: String, endpoint: Endpoint?, target: PickTarget) -> some View {
        Button { picking = target } label: {
            HStack {
                Text(label).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                if let endpoint {
                    if case .currentLocation = endpoint {
                        Image(systemName: "location.fill").foregroundStyle(.blue)
                    }
                    Text(endpoint.title).foregroundStyle(.primary).lineLimit(1)
                } else {
                    Text("Where to?").foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func resultsSection(_ plan: PlanModel) -> some View {
        let its = plan.itineraries
        let windowStart = its.map(\.startTime).min() ?? .now
        let windowEnd = its.map(\.endTime).max() ?? .now

        Section {
            if plan.isLoading && its.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let msg = plan.errorMessage, its.isEmpty {
                Text(msg).foregroundStyle(.secondary)
            }

            if showMap && !its.isEmpty {
                CompareMapView(itineraries: its, selectedId: selectedId ?? its.first?.id)
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets())
                ForEach(its) { it in
                    Button { selectedId = it.id } label: {
                        ItineraryRow(itinerary: it, windowStart: windowStart, windowEnd: windowEnd)
                            .padding(.leading, 6)
                            .overlay(alignment: .leading) {
                                if it.id == (selectedId ?? its.first?.id) {
                                    Capsule().fill(.blue).frame(width: 3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                if let sel = its.first(where: { $0.id == (selectedId ?? its.first?.id) }) {
                    NavigationLink("Details of selected route") { ItineraryDetailView(itinerary: sel) }
                }
            } else {
                ForEach(its) { it in
                    NavigationLink {
                        ItineraryDetailView(itinerary: it)
                    } label: {
                        ItineraryRow(itinerary: it, windowStart: windowStart, windowEnd: windowEnd)
                    }
                }
            }

            if plan.canLoadMore {
                Button {
                    Task { await plan.loadMore() }
                } label: {
                    HStack {
                        Text(plan.timeMode == .arriveBy ? "Earlier connections" : "Later connections")
                        if plan.isLoadingMore { Spacer(); ProgressView() }
                    }
                }
            }
        } header: {
            HStack {
                Text("Routes")
                Spacer()
                if !its.isEmpty {
                    Button(showMap ? "List" : "Map") { withAnimation { showMap.toggle() } }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                }
            }
        } footer: {
            if !its.isEmpty { AttributionFooter().padding(.top, 8) }
        }
    }
}

/// One route in the comparison list. All rows share one time axis so routes can be compared at a glance.
struct ItineraryRow: View {
    let itinerary: Itinerary
    let windowStart: Date
    let windowEnd: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Fmt.time(itinerary.startTime)) – \(Fmt.time(itinerary.endTime))")
                    .font(.headline.monospacedDigit())
                if itinerary.hasRealtime {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.caption).foregroundStyle(.green)
                        .accessibilityLabel("Live data")
                }
                Spacer()
                Text(Fmt.duration(seconds: itinerary.duration))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            TimelineBar(itinerary: itinerary, windowStart: windowStart, windowEnd: windowEnd)
                .frame(height: 20)
            HStack(spacing: 8) {
                Text(itinerary.transfers == 0 ? "Direct" :
                        itinerary.transfers == 1 ? "1 change" : "\(itinerary.transfers) changes")
                if let first = itinerary.firstTransitLeg {
                    Text("· \(first.lineName) from \(first.from.name)").lineLimit(1)
                }
                if itinerary.isCancelled {
                    Text("Cancelled").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct TimelineBar: View {
    let itinerary: Itinerary
    let windowStart: Date
    let windowEnd: Date

    var body: some View {
        GeometryReader { geo in
            let span = max(windowEnd.timeIntervalSince(windowStart), 60)
            let width = geo.size.width
            let height = geo.size.height
            ZStack(alignment: .leading) {
                ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { _, leg in
                    let x = leg.startTime.timeIntervalSince(windowStart) / span * width
                    let w = max(leg.endTime.timeIntervalSince(leg.startTime) / span * width, 2)
                    if leg.isTransit {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(leg.lineColor)
                            .overlay {
                                if w > 36 {
                                    Text(leg.lineName)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(leg.lineTextColor)
                                        .lineLimit(1)
                                        .padding(.horizontal, 2)
                                }
                            }
                            .frame(width: w, height: height)
                            .offset(x: x)
                    } else {
                        Capsule()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: w, height: 4)
                            .offset(x: x)
                    }
                }
            }
            .frame(width: width, height: height, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}
