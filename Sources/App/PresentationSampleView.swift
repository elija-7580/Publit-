#if DEBUG
import SwiftUI
import UIKit
import WidgetKit

/// Deterministic UI fixtures, compiled out of Release builds. Every alert/image is explicitly a demo.
private enum PresentationSamples {
    static let base = Date()
    static let data: [String: Any] = {
        let source = #"{"stopTimes":[{"place":{"name":"Marienplatz","lat":48.137,"lon":11.575,"tz":"Europe/Berlin","stopId":"sample-Marienplatz","track":"51","departure":"DATE:3","scheduledDeparture":"DATE:3"},"mode":"SUBWAY","realTime":true,"headsign":"Garching, Forschungszentrum","tripId":"sample-0","routeShortName":"U6","displayName":null,"routeColor":"0065AE","cancelled":false},{"place":{"name":"Marienplatz","lat":48.137,"lon":11.575,"tz":"Europe/Berlin","stopId":"sample-Marienplatz","track":"51","departure":"DATE:8","scheduledDeparture":"DATE:7"},"mode":"SUBWAY","realTime":true,"headsign":"Fröttmaning","tripId":"sample-1","routeShortName":"U6","displayName":null,"routeColor":"0065AE","cancelled":false},{"place":{"name":"Marienplatz","lat":48.137,"lon":11.575,"tz":"Europe/Berlin","stopId":"sample-Marienplatz","track":"81","departure":"DATE:12","scheduledDeparture":"DATE:9"},"mode":"SUBURBAN","realTime":true,"headsign":"Flughafen München","tripId":"sample-2","routeShortName":"S1","displayName":null,"routeColor":"16C0E9","cancelled":false},{"place":{"name":"Marienplatz","lat":48.137,"lon":11.575,"tz":"Europe/Berlin","stopId":"sample-Marienplatz","track":"5","departure":"DATE:18","scheduledDeparture":"DATE:18"},"mode":"HIGHSPEED_RAIL","realTime":false,"headsign":"Hamburg-Altona","tripId":"sample-3","routeShortName":"ICE","displayName":"ICE 615","routeColor":null,"cancelled":false},{"place":{"name":"Marienplatz","lat":48.137,"lon":11.575,"tz":"Europe/Berlin","stopId":"sample-Marienplatz","track":"Bus B","departure":"DATE:22","scheduledDeparture":"DATE:22","alerts":[{"headerText":"Demo: U3 zwischen Olympiazentrum und Moosach gesperrt","descriptionText":"Testmeldung: Ersatzbus ab Haltestelle Bus B. Keine reale Verkehrsmeldung.","effect":"NO_SERVICE","severityLevel":"SEVERE"}]},"mode":"BUS","realTime":false,"headsign":"Moosach","tripId":"sample-4","routeShortName":"SEV","displayName":null,"routeColor":null,"cancelled":false},{"place":{"name":"Marienplatz","lat":48.137,"lon":11.575,"tz":"Europe/Berlin","stopId":"sample-Marienplatz","track":"7","departure":"DATE:30","scheduledDeparture":"DATE:30"},"mode":"RAIL","realTime":false,"headsign":"","tripId":"sample-5","routeShortName":"RE 3","displayName":null,"routeColor":null,"cancelled":false},{"place":{"name":"Marienplatz","lat":48.137,"lon":11.575,"tz":"Europe/Berlin","stopId":"sample-Marienplatz","track":"82","departure":"DATE:35","scheduledDeparture":"DATE:35"},"mode":"SUBURBAN","realTime":true,"headsign":"Erding","tripId":"sample-6","routeShortName":"S2","displayName":null,"routeColor":"69BE28","cancelled":true}],"itinerary":{"id":"sample-itinerary","duration":660,"startTime":"DATE:3","endTime":"DATE:14","transfers":0,"legs":[{"mode":"SUBWAY","from":{"name":"Marienplatz","lat":48.137,"lon":11.575,"tz":"Europe/Berlin","stopId":"sample-Marienplatz","track":"51"},"to":{"name":"Nordfriedhof","lat":48.137,"lon":11.575,"tz":"Europe/Berlin","stopId":"sample-Nordfriedhof","track":"51"},"duration":660,"startTime":"DATE:3","endTime":"DATE:14","scheduledStartTime":"DATE:3","scheduledEndTime":"DATE:14","realTime":true,"headsign":"Garching, Forschungszentrum","routeShortName":"U6","routeColor":"0065AE","routeTextColor":"FFFFFF","displayName":"U6","tripId":"sample-u6","legGeometry":{"points":"","precision":6},"fareTransferIndex":0,"effectiveFareLegIndex":0}]}}"#
        let raw = try! JSONSerialization.jsonObject(with: Data(source.utf8))
        func dates(_ value: Any) -> Any {
            if let text = value as? String, text.hasPrefix("DATE:"), let minutes = Double(text.dropFirst(5)) {
                return DateParsing.format(base.addingTimeInterval(minutes * 60))
            }
            if let object = value as? [String: Any] { return object.mapValues(dates) }
            if let array = value as? [Any] { return array.map(dates) }
            return value
        }
        return dates(raw) as! [String: Any]
    }()
    static var departures: [StopTime] {
        try! TransitousClient.makeDecoder().decode(StopTimesResponse.self, from: JSONSerialization.data(withJSONObject: data)).stopTimes
    }
    static var itinerary: Itinerary {
        try! TransitousClient.makeDecoder().decode(Itinerary.self, from: JSONSerialization.data(withJSONObject: data["itinerary"]!))
    }
    static var pricedItinerary: Itinerary {
        var trip = itinerary
        let product = FareProduct(name: "Demo — kein Preisangebot", amount: Decimal(string: "3.90")!, currency: "EUR", riderCategory: nil, media: nil)
        trip.fareTransfers = [FareTransfer(rule: nil, transferProducts: nil, effectiveFareLegProducts: [[[product]]])]
        return trip
    }
    static var image: Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 300))
        return renderer.pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 720, height: 300))
            ("DEMO — KEIN FAHRSCHEIN" as NSString).draw(at: CGPoint(x: 40, y: 80), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 36), .foregroundColor: UIColor.black])
            ("Testbild · kein QR-Code · keine Gültigkeit" as NSString).draw(at: CGPoint(x: 40, y: 160), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.darkGray])
        }
    }
}

struct PresentationSampleView: View {
    @Environment(TripStore.self) private var trips
    @Environment(TicketStore.self) private var tickets
    @Environment(SearchHistoryStore.self) private var history
    @Environment(AppState.self) private var app
    private let kind = ProcessInfo.processInfo.environment["PUBLIT_UI_SAMPLE"] ?? "board"
    private let dark = ProcessInfo.processInfo.environment["PUBLIT_UI_DARK"] == "1"
    private let large = ProcessInfo.processInfo.environment["PUBLIT_UI_LARGE"] == "1"

    private var widgetEntry: DeparturesEntry {
        DeparturesEntry(date: PresentationSamples.base, stop: StopEntity(stopId: "demo", name: "Marienplatz", lat: 48.137, lon: 11.575),
                        departures: Array(PresentationSamples.departures.prefix(2)).map(WidgetDeparture.init))
    }

    var body: some View {
        if kind.hasPrefix("pass") {
            PassSampleView(kind: kind)
                .preferredColorScheme(dark ? .dark : .light)
                .dynamicTypeSize(large ? .accessibility2 : .large)
        } else if kind.hasPrefix("route") || kind.hasPrefix("live") {
            DesignSampleView(kind: kind)
                .preferredColorScheme(dark ? .dark : .light)
        } else {
            standard
        }
    }

    private var standard: some View {
        NavigationStack {
            List {
                if kind == "board" {
                    Section("Departures") { ForEach(PresentationSamples.departures) { DepartureRow(stopTime: $0) } }
                } else if kind == "widget" {
                    Section("Departures") {
                        DeparturesWidgetView(entry: widgetEntry, previewFamily: .systemSmall)
                            .frame(width: 136, height: 136).padding(12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                        DeparturesWidgetView(entry: widgetEntry, previewFamily: .systemMedium)
                            .frame(height: 136).padding(12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                } else if kind == "alerts" {
                    Section("Alerts") { ServiceAlertsView(alerts: PresentationSamples.departures[4].serviceAlerts) }
                } else if kind == "fare" {
                    FareSection(itinerary: PresentationSamples.pricedItinerary)
                } else if kind == "leg" {
                    Section("Steps") { ForEach(PresentationSamples.itinerary.legs, id: \.startTime) { LegRow(leg: $0) } }
                } else {
                    Section("Departures") { DepartureRow(stopTime: PresentationSamples.departures[0]) }
                    TripActionsSection(itinerary: PresentationSamples.itinerary, fromName: "Marienplatz", toName: "Nordfriedhof")
                    RecentSearchesSection()
                }
            }
            .inkList()
            .navigationTitle(kind == "board" ? L10n.t("Departures") : kind == "leg" ? L10n.t("Route") : L10n.t("Trip"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(dark ? .dark : .light)
        .dynamicTypeSize(large ? .accessibility2 : .large)
        .task {
            guard kind == "workflow" else { return }
            let saved = trips.save(PresentationSamples.itinerary, from: "Marienplatz", to: "Nordfriedhof")
            trips.update(saved.id, with: PresentationSamples.itinerary)
            if Features.tickets, !tickets.tickets.contains(where: { $0.name == "Ticket-Beispiel" }) {
                tickets.add(name: "Ticket-Beispiel", kind: .single, image: PresentationSamples.image,
                            appLink: nil, validUntil: nil, tripId: saved.id)
            }
            let target = SavedPlace(id: "sample-nord", name: "Nordfriedhof", subtitle: nil, lat: 48.17, lon: 11.58, stopId: nil)
            history.record(from: .currentLocation, to: .place(target), mode: .now, date: .now)
        }
        .sheet(isPresented: Binding(get: {
            if case .trip = app.deepLink { return true }; return false
        }, set: { if !$0 { app.deepLink = nil } })) {
            NavigationStack {
                List {
                    if case .trip(let id) = app.deepLink, let trip = trips.trip(id) {
                        Section("Active trip") { StatusBanner(status: TripStatus.at(.now, trip.itinerary), refreshedAt: trip.refreshedAt) }
                        ForEach(trip.itinerary.legs, id: \.startTime) { LegRow(leg: $0) }
                        TripActionsSection(itinerary: trip.itinerary, fromName: trip.fromName, toName: trip.toName)
                    }
                }
                .inkList()
                .accessibilityIdentifier("activeTripList")
                .navigationTitle("Active trip")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { app.deepLink = nil } } }
            }
            .presentationDetents([.large])
        }
    }
}
#endif
