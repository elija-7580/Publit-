import SwiftUI
import MapKit

struct CompareMapView: View {
    let itineraries: [Itinerary]
    let selectedId: String?

    /// Selected route is drawn last so it sits on top.
    private var ordered: [Itinerary] {
        itineraries.filter { $0.routeKey != selectedId } + itineraries.filter { $0.routeKey == selectedId }
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            UserAnnotation()
            ForEach(ordered, id: \.routeKey) { it in
                let isSelected = it.routeKey == selectedId
                ForEach(Array(it.legs.enumerated()), id: \.offset) { _, leg in
                    MapPolyline(coordinates: leg.legGeometry.clCoordinates)
                        .stroke(isSelected ? (leg.isTransit ? leg.lineStroke : Color.routeAhead) : Color.gray.opacity(0.45),
                                style: .leg(leg.isTransit, width: isSelected ? 5 : 3))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

struct ItineraryDetailView: View {
    @Environment(TripStore.self) private var trips
    /// False once this screen is popped or dismissed (still true while a child screen is pushed).
    @Environment(\.isPresented) private var isPresented
    let itinerary: Itinerary
    var fromName: String = ""
    var toName: String = ""
    /// Live state of a saved trip ("On time", "Leave in 6 min", …), evaluated every 30 s.
    /// Only the banner redraws on that timer, not the map and the steps.
    var statusAt: ((Date) -> TripStatus)? = nil
    var refreshedAt: Date? = nil
    @State private var showsMap = false

    private var isBikeOrCar: Bool {
        let m = StreetComparison.streetMode(itinerary)
        return m == "BIKE" || m == "CAR"
    }

    private var resolvedFrom: String { fromName.isEmpty ? Self.placeName(itinerary.legs.first?.from) : fromName }
    private var resolvedTo: String { toName.isEmpty ? Self.placeName(itinerary.legs.last?.to) : toName }

    /// MOTIS names coordinate endpoints "START"/"END".
    static func placeName(_ p: Place?) -> String {
        guard let p, p.name != "START", p.name != "END" else { return L10n.t("Destination") }
        return p.name
    }

    var body: some View {
        let warnings = TransferRisk.warnings(for: itinerary)
        List {
            // 1. What matters first: the way at a glance, when, how long, which lines, live state and warnings.
            Section {
                Button { showsMap = true } label: {
                    RouteMap(itinerary: itinerary)
                        .frame(height: 190)
                        .allowsHitTesting(false)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.body.weight(.semibold))
                                .frame(width: 40, height: 40)
                                .matteSurface(in: Circle())
                                .padding(10)
                        }
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .accessibilityLabel(Text("Trip overview"))
                .accessibilityIdentifier("routePreviewMap")
                if let statusAt {
                    Clocked(every: 30) { now in
                        StatusBanner(status: statusAt(now), refreshedAt: refreshedAt)
                    }
                }
                Clocked(every: 30) { now in LeaveHero(itinerary: itinerary, now: now) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                RouteSummary(itinerary: itinerary, showsTimes: false)
                if let note = Fmt.foreignZoneNote(tz: itinerary.legs.first?.from.tz, at: itinerary.startTime) {
                    Label(note, systemImage: "clock").font(.footnote).foregroundStyle(.secondary)
                }
                if StreetComparison.streetMode(itinerary) == "CAR" {
                    Label("Driving times are without traffic and parking.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            // Warnings in one calm form: a coloured edge, the words in ink.
            if !warnings.isEmpty {
                Section {
                    ForEach(warnings, id: \.self) { w in
                        Notice(level: w.level == .missed ? .critical : .change, title: w.message)
                    }
                }
            }

            // 2. What you can do with it, right below: start, save, calendar, reminder.
            // Cycling and driving are shown for comparison only: no trip, reminder or fares.
            if !isBikeOrCar {
                TripActionsSection(itinerary: itinerary, fromName: resolvedFrom, toName: resolvedTo)
            }

            // 3. The way, step by step, as a timeline: times on the left, the line in its colour.
            Section("Steps") {
                ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { _, leg in
                    TimelineLegRow(leg: leg)
                }
                TimelineEndRow(time: itinerary.endTime, tz: itinerary.legs.last?.to.tz, name: resolvedTo)
            }

            if !isBikeOrCar { FareSection(itinerary: itinerary) }
        }
        .inkList()
        .sheet(isPresented: $showsMap) {
            NavigationStack {
                RouteMap(itinerary: itinerary)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(Text("Trip overview"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showsMap = false } }
                    }
            }
        }
        .navigationTitle("Route")
        .screenTrail("Route")
        .navigationBarTitleDisplayMode(.inline)
        .showPassToolbar(tripId: trips.saved(itinerary)?.id, at: itinerary.startTime, enabled: Features.passes)
        // A trip unsaved here is only deleted when the screen closes, not when a detail is pushed.
        .onDisappear { if !isPresented { trips.discardPendingRemovalsLater() } }
        .onChange(of: isPresented) { _, presented in if !presented { trips.discardPendingRemovalsLater() } }
    }
}

/// Time, duration and the chain of lines, e.g. 🚶 › S8 › U6 › 🚶.
struct RouteSummary: View {
    let itinerary: Itinerary
    /// Off under the leave card, which already shows them.
    var showsTimes = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Chosen by text size, not ViewThatFits: measuring both layouts in a self-sizing row
            // can make the row's height flip between passes.
            if showsTimes {
                if typeSize.isAccessibilitySize {
                    stackedTimes
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Fmt.time(itinerary.startTime, tz: itinerary.legs.first?.from.tz)) – \(Fmt.time(itinerary.endTime, tz: itinerary.legs.last?.to.tz))")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        DurationFigure(seconds: itinerary.duration)
                            .lineLimit(1).fixedSize()
                    }
                }
            }
            legChain
            HStack(spacing: 6) {
                Text(Fmt.changes(itinerary.transfers))
                if itinerary.hasRealtime && !Connectivity.shared.isOffline {
                    Text(verbatim: "·")
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(Color.live)
                }
                if itinerary.isCancelled {
                    Text(verbatim: "·")
                    Text("Cancelled").foregroundStyle(Color.danger)
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var stackedTimes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Fmt.time(itinerary.startTime, tz: itinerary.legs.first?.from.tz)) – \(Fmt.time(itinerary.endTime, tz: itinerary.legs.last?.to.tz))")
                .font(.title2.bold().monospacedDigit())
            DurationFigure(seconds: itinerary.duration)
        }
    }

    private var legChain: some View {
        // Short walks between platforms are noise in the overview; the steps list keeps them.
        let legs = itinerary.legs.filter { $0.isTransit || $0.duration >= 120 }
        return FlowRow(spacing: 4) {
            ForEach(Array(legs.enumerated()), id: \.offset) { i, leg in
                HStack(spacing: 4) {
                    if i > 0 {
                        Image(systemName: "chevron.compact.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    if leg.isTransit {
                        LineBadge(leg)
                    } else {
                        HStack(spacing: 2) {
                            Image(systemName: ModeStyle.symbol(leg.mode))
                            Text(verbatim: "\(max(1, leg.duration / 60))")
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Wraps its children onto new lines when they do not fit (long routes with many changes).
struct FlowRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let frames = arrange(subviews, maxWidth: maxWidth)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // The same arrangement as when measuring, so rows never differ between the two.
        let frames = arrange(subviews, maxWidth: proposal.width ?? bounds.width)
        for (v, f) in zip(subviews, frames) {
            v.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return frames
    }
}

extension StrokeStyle {
    /// Route lines on maps: always solid. Walks are told apart by colour (`Color.routeAhead`) and a
    /// slightly thinner line; the dotted walks of earlier builds broke up or vanished on the map.
    static func leg(_ isTransit: Bool, width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: isTransit ? width : max(3, width - 1), lineCap: .round, lineJoin: .round)
    }
}

/// The whole route on a map, with start and destination.
struct RouteMap: View {
    let itinerary: Itinerary

    var body: some View {
        Map(initialPosition: .automatic) {
            UserAnnotation()
            ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { _, leg in
                MapPolyline(coordinates: leg.legGeometry.clCoordinates)
                    .stroke(leg.isTransit ? leg.lineStroke : Color.routeAhead, style: .leg(leg.isTransit, width: 5))
            }
            if let first = itinerary.legs.first {
                Marker("Start", systemImage: "circle.fill", coordinate: first.from.coordinate.clCoordinate)
                    .tint(Color.inkAction)
            }
            if let last = itinerary.legs.last {
                Marker("Destination", systemImage: "flag.fill", coordinate: last.to.coordinate.clCoordinate)
                    .tint(Color.inkAction)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

struct LegRow: View {
    let leg: Leg
    /// Its own coloured bar on the left; off inside the timeline, which draws the line itself.
    var bar = true

    var body: some View {
        if leg.isTransit {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    LineBadge(leg)
                    if let detail = leg.serviceDetail {
                        Text(verbatim: detail).font(.caption.weight(.semibold))
                    }
                    Spacer(minLength: 4)
                    DurationFigure(seconds: leg.duration, size: 22)
                }
                DirectionLabel(direction: leg.shownDirection, circular: leg.isCircular)
                if leg.isReplacementBus { Label("Rail replacement bus", systemImage: "bus.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color.delay) }
                stopLine(label: "Board here", time: leg.startTime, delay: leg.delayMinutes,
                         name: leg.from.name, track: leg.from.track, tz: leg.from.tz)
                HStack(spacing: 6) {
                    if let stops = leg.intermediateStops { Text(Fmt.stops(stops.count)); Text(verbatim: "·") }
                    Text(leg.realTime && !Connectivity.shared.isOffline ? L10n.t("Live") : L10n.t("Timetable"))
                }
                .font(.caption).foregroundStyle(.secondary)
                stopLine(label: "Get off here", time: leg.endTime,
                         delay: Int((leg.endTime.timeIntervalSince(leg.scheduledEndTime) / 60).rounded()),
                         name: leg.to.name, track: leg.to.track, tz: leg.to.tz)
                if leg.cancelled == true {
                    Text("This trip is cancelled.").font(.caption.weight(.semibold)).foregroundStyle(Color.danger)
                }
                ServiceAlertsView(alerts: leg.serviceAlerts)
                GetOffButton(leg: leg)
            }
            .padding(.vertical, 6)
            .padding(.leading, bar ? 12 : 0)
            .overlay(alignment: .leading) {
                if bar {
                    RoundedRectangle(cornerRadius: 2).fill(leg.lineStroke).frame(width: 4).padding(.vertical, 6)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("transitLeg")
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: leg.rental.map { $0.kind.symbol } ?? ModeStyle.symbol(leg.mode))
                    .foregroundStyle(leg.rental == nil ? Color.secondary : Color.ink).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    if let r = leg.rental {
                        // Shared bike or scooter: whose, from where, and a link to rent it.
                        Text(verbatim: "\(r.kind.title) · \(r.systemName ?? ModeStyle.label(leg.mode))")
                        if let from = r.fromStationName, !from.isEmpty {
                            Text(L10n.f("Pick up at %@", from)).foregroundStyle(.secondary)
                        }
                        if let to = r.toStationName, !to.isEmpty {
                            Text(L10n.f("Return at %@", to)).foregroundStyle(.secondary)
                        }
                        if let d = leg.distance, d > 0 { Text(Fmt.distance(meters: d)).foregroundStyle(.secondary) }
                        if let url = r.bookingURL {
                            Link(destination: url) { Label("Rent in the provider's app", systemImage: "arrow.up.forward.app") }
                                .font(.subheadline.weight(.semibold))
                        }
                    } else {
                        Text(verbatim: ModeStyle.label(leg.mode))
                        if let d = leg.distance, d > 0 { Text(Fmt.distance(meters: d)).foregroundStyle(.secondary) }
                    }
                }
                Spacer(minLength: 4)
                DurationFigure(seconds: leg.duration, size: 22)
            }
            .font(.subheadline)
        }
    }

    private func stopLine(label: LocalizedStringKey, time: Date, delay: Int, name: String,
                          track: String?, tz: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.time(time, tz: tz)).font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1).fixedSize()
                if delay > 0 { Text(L10n.f("+%lld min", delay)).font(.caption).foregroundStyle(Color.delay) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: name).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if let track = TransitLabels.clean(track) {
                    Text(L10n.f("Platform %@", track)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "Remind me to get off" for one transit leg.
struct GetOffButton: View {
    let leg: Leg
    @State private var scheduled = false
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                Task { await toggle() }
            } label: {
                Label(scheduled ? L10n.t("Reminder set") : L10n.t("Remind me to get off"),
                      systemImage: scheduled ? "bell.fill" : "bell")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task { scheduled = await GetOffReminder.isScheduled(leg) }
    }

    private func toggle() async {
        if scheduled {
            GetOffReminder.cancel(for: leg)
            scheduled = false
            note = nil
            return
        }
        switch await GetOffReminder.schedule(for: leg) {
        case .scheduled(let date):
            scheduled = true
            note = L10n.f("We'll notify you at %@.", Fmt.time(date, tz: leg.to.tz))
        case .tooLate:
            note = L10n.t("This stop is less than two minutes away.")
        case .denied:
            note = L10n.t("Allow notifications for Publit in Settings.")
        }
    }
}

/// Live state of a saved trip.
struct StatusBanner: View {
    let status: TripStatus
    let refreshedAt: Date?

    private var color: Color {
        switch status.phase {
        case .cancelled: return .danger
        default: return status.delayMinutes > 0 ? .delay : .live
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.headline).font(.headline)
                Spacer()
                if status.phase != .arrived && status.phase != .cancelled {
                    Text(status.delayMinutes > 0 ? L10n.f("+%lld min", status.delayMinutes) : L10n.t("On time"))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(color)
                }
            }
            Text(status.detail).font(.subheadline).foregroundStyle(status.phase == .cancelled ? Color.danger : .secondary)
            if let refreshedAt {
                Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One leg in the route timeline: when it starts, a stop on the line (solid in the line's colour,
/// dotted blue on foot) and the leg itself.
struct TimelineLegRow: View {
    let leg: Leg

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Fmt.time(leg.startTime, tz: leg.from.tz))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 52, alignment: .trailing)
                .padding(.top, 10)
            TimelineRail(color: leg.isTransit ? leg.lineStroke : Color.secondary, dotted: !leg.isTransit)
            LegRow(leg: leg, bar: false)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }
}

/// The end of the timeline: arrival time and the destination.
struct TimelineEndRow: View {
    let time: Date
    let tz: String?
    let name: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(Fmt.time(time, tz: tz))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 52, alignment: .trailing)
            Image(systemName: "flag.checkered.circle.fill")
                .font(.title3).foregroundStyle(Color.ink)
                .frame(width: 18)
            Text(name).font(.headline)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }
}

private struct TimelineRail: View {
    let color: Color
    let dotted: Bool

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .strokeBorder(color, lineWidth: 3)
                .background(Circle().fill(Color.surface))
                .frame(width: 14, height: 14)
                .padding(.top, 12)
            RailLine()
                .stroke(color, style: StrokeStyle(lineWidth: dotted ? 3 : 5, lineCap: .round, dash: dotted ? [0.1, 7] : []))
                .frame(width: 18)
        }
        .frame(width: 18)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private struct RailLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// The one number that decides: when to leave (or the times), and when you arrive. Ink slab, big type.
struct LeaveHero: View {
    let itinerary: Itinerary
    let now: Date

    var body: some View {
        let tz = itinerary.legs.first?.from.tz
        let minutes = Int((itinerary.startTime.timeIntervalSince(now) / 60).rounded(.up))
        let big: String = minutes > 90 || minutes < -1
            ? "\(Fmt.time(itinerary.startTime, tz: tz)) – \(Fmt.time(itinerary.endTime, tz: itinerary.legs.last?.to.tz))"
            : minutes >= 1 ? L10n.f("Leave in %lld min", minutes) : L10n.t("Leave now")
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.duration(seconds: itinerary.duration))
                    .font(.caption.weight(.semibold)).opacity(0.65)
                Text(verbatim: big)
                    .font(.title2.weight(.heavy).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Arrive").font(.caption.weight(.semibold)).opacity(0.65)
                Text(Fmt.time(itinerary.endTime, tz: itinerary.legs.last?.to.tz))
                    .font(.title2.weight(.heavy).monospacedDigit())
            }
        }
        .foregroundStyle(Color.onInk)
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Color.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
