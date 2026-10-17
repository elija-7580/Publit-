import Foundation

/// Plain coordinate type, independent of CoreLocation so the model layer stays portable and testable.
struct LatLon: Hashable, Codable, Sendable {
    let lat: Double
    let lon: Double

    var isValidCoordinate: Bool { lat.isFinite && lon.isFinite && abs(lat) <= 90 && abs(lon) <= 180 }

    /// `lat,lon` as expected by the MOTIS API, to about 1 m. Full GPS precision only makes
    /// every request URL unique (no cache hits) and says more about where someone is than needed.
    var apiValue: String { Self.format(lat, 5) + "," + Self.format(lon, 5) }

    /// The same point to about 1 km, for search bias: nearby results stay first and repeated
    /// searches from around the same place reuse the cached answer.
    var coarseAPIValue: String { Self.format(lat, 2) + "," + Self.format(lon, 2) }

    /// Locale-independent fixed decimals without trailing zeros ("48.13715", "11.5").
    static func format(_ value: Double, _ decimals: Int) -> String {
        var s = String(format: "%.\(decimals)f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }

    init?(apiValue: String) {
        let parts = apiValue.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        let point = LatLon(lat: parts[0], lon: parts[1])
        guard point.isValidCoordinate else { return nil }
        self = point
    }
}

/// Google-encoded polyline as returned by MOTIS (`precision` 6 for /v2+).
struct EncodedPolyline: Codable, Sendable {
    let points: String
    let precision: Int
    let length: Int
    let coordinates: [LatLon]
    /// Simplified copy for maps, computed once while decoding (off the main thread).
    let mapPoints: [LatLon]

    private enum CodingKeys: String, CodingKey { case points, precision, length }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decode(String.self, forKey: .points)
        precision = try c.decode(Int.self, forKey: .precision)
        length = try c.decodeIfPresent(Int.self, forKey: .length) ?? 0
        coordinates = Polyline.decode(points, precision: precision)
        mapPoints = Polyline.simplify(coordinates)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(points, forKey: .points)
        try c.encode(precision, forKey: .precision)
        try c.encode(length, forKey: .length)
    }
}

/// Booking links per platform, when the feed provides them.
struct TicketUrls: Codable, Hashable, Sendable {
    let web: String?
    let ios: String?
    let android: String?
}

struct Place: Codable, Hashable, Sendable {
    let name: String
    let stopId: String?
    let parentId: String?
    let lat: Double
    let lon: Double
    let tz: String?
    let arrival: Date?
    let departure: Date?
    let scheduledArrival: Date?
    let scheduledDeparture: Date?
    let track: String?
    let scheduledTrack: String?
    let cancelled: Bool?
    let alerts: [Alert]?

    var coordinate: LatLon { LatLon(lat: lat, lon: lon) }
    var alertsList: [Alert] { alerts ?? [] }
    /// Stop identifier to group platforms of one station.
    var stationId: String { parentId ?? stopId ?? "\(name)@\(lat),\(lon)" }
}

struct Alert: Codable, Hashable, Sendable {
    let headerText: String
    let descriptionText: String
    let url: String?
    var effect: String? = nil
    var severityLevel: String? = nil
    var communicationPeriod: [AlertPeriod]? = nil
    var impactPeriod: [AlertPeriod]? = nil
}

struct Leg: Codable, Sendable, RouteStyled {
    let mode: String
    let from: Place
    let to: Place
    let duration: Int
    let startTime: Date
    let endTime: Date
    let scheduledStartTime: Date
    let scheduledEndTime: Date
    let realTime: Bool
    let distance: Double?
    let headsign: String?
    let routeColor: String?
    let routeTextColor: String?
    let routeShortName: String?
    let displayName: String?
    let agencyName: String?
    let agencyUrl: String?
    let agencyFareUrl: String?
    let routeUrl: String?
    let ticketUrls: TicketUrls?
    let routeId: String?
    let tripId: String?
    let cancelled: Bool?
    let intermediateStops: [Place]?
    let alerts: [Alert]?
    let legGeometry: EncodedPolyline
    /// Bike or scooter sharing for `RENTAL` legs.
    var rental: LegRental? = nil
    var fareTransferIndex: Int? = nil
    var effectiveFareLegIndex: Int? = nil
    /// Walking (and cycling) directions: streets, stairs and levels, each with its piece of the path.
    var steps: [StepInstruction]? = nil

    var directionName: String? { TransitLabels.clean(headsign) }
    var isTransit: Bool { ModeStyle.isTransit(mode) }
    var delayMinutes: Int { Int((startTime.timeIntervalSince(scheduledStartTime) / 60).rounded()) }
    /// Boarding stop, every stop in between, and the alighting stop.
    var allStops: [Place] { [from] + (intermediateStops ?? []) + [to] }
}

/// One piece of a walk as the router describes it. Turns are mostly "CONTINUE": `WalkGuide`
/// derives left/right from the geometry.
struct StepInstruction: Codable, Sendable {
    let relativeDirection: String?
    let distance: Double
    var fromLevel: Double? = nil
    var toLevel: Double? = nil
    var polyline: EncodedPolyline? = nil
    var streetName: String? = nil
    var exit: String? = nil
    var area: Bool? = nil
}

struct Itinerary: Codable, Identifiable, Sendable {
    let id: String
    let duration: Int
    let startTime: Date
    let endTime: Date
    let transfers: Int
    var legs: [Leg]
    var fareTransfers: [FareTransfer]? = nil

    var transitLegs: [Leg] { legs.filter(\.isTransit) }
    var firstTransitLeg: Leg? { legs.first(where: \.isTransit) }
    var hasRealtime: Bool { legs.contains { $0.isTransit && $0.realTime } }
    var isCancelled: Bool { legs.contains { $0.cancelled == true } }
    /// Walking (or cycling) only, no public transport.
    var isDirect: Bool { transitLegs.isEmpty }
    /// Departure of the first vehicle (the moment that cannot be missed).
    var firstDeparture: Date? { firstTransitLeg?.startTime }

    /// Same route across live refreshes. The server's `id` encodes current times and changes
    /// with every delay update, so lists, selection and navigation must not depend on it.
    var routeKey: String {
        legs.map { leg in
            "\(leg.mode)~\(leg.tripId ?? leg.from.name)~\(Int(leg.scheduledStartTime.timeIntervalSince1970))"
        }.joined(separator: "|")
    }
}

extension Array where Element == Itinerary {
    /// One row per route: a page loaded twice or a refresh must not repeat an identity in a list.
    var uniqueRoutes: [Itinerary] {
        var seen = Set<String>()
        return filter { seen.insert($0.routeKey).inserted }
    }
}

/// A route opened from a list. Holds its own copy: a live refresh of the list underneath
/// neither closes the detail nor swallows the tap that opens it.
struct OpenedRoute: Hashable, Identifiable {
    let itinerary: Itinerary
    var id: String { itinerary.routeKey }
    static func == (a: OpenedRoute, b: OpenedRoute) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct PlanResponse: Decodable, Sendable {
    let direct: [Itinerary]
    let itineraries: [Itinerary]
    let previousPageCursor: String?
    let nextPageCursor: String?
}

struct StopTime: Decodable, Identifiable, Sendable, RouteStyled {
    let place: Place
    let mode: String
    let realTime: Bool
    let headsign: String
    let agencyName: String?
    let routeId: String?
    let tripId: String
    let routeShortName: String?
    let displayName: String?
    let routeColor: String?
    let routeTextColor: String?
    let cancelled: Bool?
    let tripCancelled: Bool?
    /// Feed direction ("0"/"1"), when given; groups the two directions of a line.
    var directionId: String? = nil
    /// Last stop of the trip.
    var tripTo: SegmentStop? = nil

    /// By the timetable time where known: a new delay must not turn a row into a different row
    /// (in a list that would close a screen opened from it).
    var id: String {
        "\(tripId)|\(place.stopId ?? place.name)|\((scheduledDepartureTime ?? departureTime).timeIntervalSince1970)"
    }
    var directionName: String? { TransitLabels.clean(headsign) }
    var departureTime: Date { place.departure ?? place.arrival ?? .distantPast }
    var scheduledDepartureTime: Date? { place.scheduledDeparture ?? place.scheduledArrival }
    var isCancelled: Bool { cancelled == true || tripCancelled == true || place.cancelled == true }
    var delayMinutes: Int {
        guard let s = scheduledDepartureTime else { return 0 }
        return Int((departureTime.timeIntervalSince(s) / 60).rounded())
    }
}

extension StopTime {
    /// Drops departures that have already left (saved boards shown offline can be minutes old).
    /// Also drops repeated entries, so list IDs stay unique.
    static func upcoming(_ list: [StopTime], now: Date = Date()) -> [StopTime] {
        var seen = Set<String>()
        return list.filter { $0.departureTime > now.addingTimeInterval(-60) && seen.insert($0.id).inserted }
    }
}

struct StopTimesResponse: Decodable, Sendable {
    let stopTimes: [StopTime]
    let place: Place?
    let nextPageCursor: String?
}

struct GeocodeArea: Decodable, Hashable, Sendable {
    let name: String
    let adminLevel: Double?
    let `default`: Bool?
}

struct GeocodeMatch: Decodable, Identifiable, Hashable, Sendable {
    let type: String
    let name: String
    let id: String
    let lat: Double
    let lon: Double
    let street: String?
    let houseNumber: String?
    let country: String?
    let areas: [GeocodeArea]
    /// What kind of place (OSM based, e.g. "place_6", "suburb", "village", "restaurant_14"). Not for stops.
    let category: String?

    var isStop: Bool { type == "STOP" }
    var subtitle: String {
        var parts: [String] = []
        if !isStop, let street, street != name {
            parts.append([street, houseNumber].compactMap { $0 }.joined(separator: " "))
        }
        if let area = areas.first(where: { $0.default == true }) ?? areas.last { parts.append(area.name) }
        if let country { parts.append(country) }
        return parts.joined(separator: ", ")
    }
}

/// A stop on the station map (`/api/v6/map/stops`).
struct MapStop: Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let stopId: String
    let parentId: String?
    let lat: Double
    let lon: Double
    let importance: Double?
    let modes: [String]?

    var id: String { stopId }
    var coordinate: LatLon { LatLon(lat: lat, lon: lon) }
    var stationId: String { parentId ?? stopId }
}
