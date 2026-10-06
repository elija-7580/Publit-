import SwiftUI
import MapKit

struct CompareMapView: View {
    let itineraries: [Itinerary]
    let selectedId: String?

    /// Selected route is drawn last so it sits on top.
    private var ordered: [Itinerary] {
        itineraries.filter { $0.id != selectedId } + itineraries.filter { $0.id == selectedId }
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            UserAnnotation()
            ForEach(ordered) { it in
                let isSelected = it.id == selectedId
                ForEach(Array(it.legs.enumerated()), id: \.offset) { _, leg in
                    MapPolyline(coordinates: leg.legGeometry.clCoordinates)
                        .stroke(isSelected ? leg.lineColor : Color.gray.opacity(0.45),
                                style: StrokeStyle(lineWidth: isSelected ? 5 : 3, lineCap: .round, lineJoin: .round,
                                                   dash: leg.isTransit ? [] : [2, 6]))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

struct ItineraryDetailView: View {
    let itinerary: Itinerary

    var body: some View {
        List {
            Section {
                Map(initialPosition: .automatic) {
                    UserAnnotation()
                    ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { _, leg in
                        MapPolyline(coordinates: leg.legGeometry.clCoordinates)
                            .stroke(leg.isTransit ? leg.lineColor : Color.gray,
                                    style: StrokeStyle(lineWidth: leg.isTransit ? 5 : 3, lineCap: .round, lineJoin: .round,
                                                       dash: leg.isTransit ? [] : [2, 6]))
                    }
                    if let first = itinerary.legs.first {
                        Marker("Start", systemImage: "circle.fill", coordinate: first.from.coordinate.clCoordinate)
                            .tint(.green)
                    }
                    if let last = itinerary.legs.last {
                        Marker("Destination", systemImage: "flag.fill", coordinate: last.to.coordinate.clCoordinate)
                            .tint(.red)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 260)
                .listRowInsets(EdgeInsets())
            }

            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(Fmt.time(itinerary.startTime)) – \(Fmt.time(itinerary.endTime))")
                            .font(.title3.weight(.semibold).monospacedDigit())
                        Text(itinerary.transfers == 0 ? "Direct" : "\(itinerary.transfers) changes")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.duration(seconds: itinerary.duration)).font(.title3.weight(.semibold))
                }
            }

            Section("Steps") {
                ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { _, leg in
                    LegRow(leg: leg)
                }
            }

            Section { AttributionFooter() }
        }
        .navigationTitle("Route")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LegRow: View {
    let leg: Leg

    var body: some View {
        if leg.isTransit {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    LineBadge(leg)
                    if let h = leg.headsign, !h.isEmpty {
                        Text("→ \(h)").font(.subheadline).lineLimit(1)
                    }
                    Spacer()
                    if leg.realTime {
                        Text("live").font(.caption2.weight(.bold)).foregroundStyle(.green)
                    }
                }
                stopLine(time: leg.startTime, delay: leg.delayMinutes, name: leg.from.name, track: leg.from.track)
                let stops = leg.intermediateStops?.count ?? 0
                Text("\(stops == 0 ? "No stops" : stops == 1 ? "1 stop" : "\(stops) stops") · \(Fmt.duration(seconds: leg.duration))")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 52)
                stopLine(time: leg.endTime,
                         delay: Int((leg.endTime.timeIntervalSince(leg.scheduledEndTime) / 60).rounded()),
                         name: leg.to.name, track: leg.to.track)
                if leg.cancelled == true {
                    Text("This trip is cancelled.").font(.caption.weight(.semibold)).foregroundStyle(.red)
                }
                ForEach(leg.alerts ?? [], id: \.self) { a in
                    Label(a.headerText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 8) {
                Image(systemName: ModeStyle.symbol(leg.mode)).foregroundStyle(.secondary).frame(width: 24)
                Text("\(ModeStyle.label(leg.mode)) \(Fmt.duration(seconds: leg.duration))")
                if let d = leg.distance, d > 0 {
                    Text("· \(Fmt.distance(meters: d))").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.subheadline)
        }
    }

    private func stopLine(time: Date, delay: Int, name: String, track: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Fmt.time(time)).font(.subheadline.weight(.semibold).monospacedDigit()).frame(width: 44, alignment: .leading)
            if delay > 0 {
                Text("+\(delay)").font(.caption.monospacedDigit()).foregroundStyle(.orange)
            }
            Text(name).font(.subheadline).lineLimit(1)
            Spacer()
            if let track, !track.isEmpty {
                Text("Pl. \(track)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
