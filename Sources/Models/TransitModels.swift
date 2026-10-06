import Foundation

/// Plain coordinate type, independent of CoreLocation so the model layer stays portable and testable.
struct LatLon: Hashable, Codable, Sendable {
    let lat: Double
    let lon: Double

    /// `lat,lon` as expected by the MOTIS API.
    var apiValue: String { "\(lat),\(lon)" }
}

/// Google-encoded polyline as returned by MOTIS (`precision` 6 for /v2+).
struct EncodedPolyline: Decodable, Sendable {
    let points: String
    let precision: Int
    let length: Int
    let coordinates: [LatLon]

    private enum CodingKeys: String, CodingKey { case points, precision, length }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decode(String.self, forKey: .points)
        precision = try c.decode(Int.self, forKey: .precision)
        length = try c.decodeIfPresent(Int.self, forKey: .length) ?? 0
        coordinates = Polyline.decode(points, precision: precision)
    }
}

struct Place: Decodable, Hashable, Sendable {
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

struct Alert: Decodable, Hashable, Sendable {
    let headerText: String
    let descriptionText: String
    let url: String?
}

struct Leg: Decodable, Sendable, RouteStyled {
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
    let tripId: String?
    let cancelled: Bool?
    let intermediateStops: [Place]?
    let alerts: [Alert]?
    let legGeometry: EncodedPolyline

    var isTransit: Bool { ModeStyle.isTransit(mode) }
    var delayMinutes: Int { Int((startTime.timeIntervalSince(scheduledStartTime) / 60).rounded()) }
}

struct Itinerary: Decodable, Identifiable, Sendable {
    let id: String
    let duration: Int
    let startTime: Date
    let endTime: Date
    let transfers: Int
    let legs: [Leg]

    var transitLegs: [Leg] { legs.filter(\.isTransit) }
    var firstTransitLeg: Leg? { legs.first(where: \.isTransit) }
    var hasRealtime: Bool { legs.contains { $0.isTransit && $0.realTime } }
    var isCancelled: Bool { legs.contains { $0.cancelled == true } }
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
    let tripId: String
    let routeShortName: String?
    let displayName: String?
    let routeColor: String?
    let routeTextColor: String?
    let cancelled: Bool?
    let tripCancelled: Bool?

    var id: String { "\(tripId)|\(place.stopId ?? place.name)|\(departureTime.timeIntervalSince1970)" }
    var departureTime: Date { place.departure ?? place.arrival ?? .distantPast }
    var scheduledDepartureTime: Date? { place.scheduledDeparture ?? place.scheduledArrival }
    var isCancelled: Bool { cancelled == true || tripCancelled == true || place.cancelled == true }
    var delayMinutes: Int {
        guard let s = scheduledDepartureTime else { return 0 }
        return Int((departureTime.timeIntervalSince(s) / 60).rounded())
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
