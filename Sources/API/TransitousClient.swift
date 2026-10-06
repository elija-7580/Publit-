import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct ServerError: Decodable { let error: String }

/// Client for the Transitous MOTIS 2 API (https://transitous.org/api/).
///
/// Usage policy: open-source, non-commercial, identifying User-Agent, visible attribution.
final class TransitousClient: @unchecked Sendable {
    static let shared = TransitousClient()

    private let base: URL
    private let session: URLSession
    private let userAgent: String
    let decoder: JSONDecoder

    init(base: URL = URL(string: "https://api.transitous.org")!,
         userAgent: String = AppInfo.userAgent) {
        self.base = base
        self.userAgent = userAgent
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
        decoder = TransitousClient.makeDecoder()
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = DateParsing.parse(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
        }
        return d
    }

    // MARK: Endpoints

    func geocode(_ text: String, near: LatLon?, language: String? = Locale.current.language.languageCode?.identifier) async throws -> [GeocodeMatch] {
        var q = [URLQueryItem(name: "text", value: text), URLQueryItem(name: "numResults", value: "15")]
        if let near {
            q.append(URLQueryItem(name: "place", value: near.apiValue))
            q.append(URLQueryItem(name: "placeBias", value: "5"))
        }
        if let language { q.append(URLQueryItem(name: "language", value: language)) }
        return try await get("/api/v1/geocode", q)
    }

    func plan(from: LatLon, to: LatLon, time: Date?, arriveBy: Bool, pageCursor: String? = nil) async throws -> PlanResponse {
        var q = [
            URLQueryItem(name: "fromPlace", value: from.apiValue),
            URLQueryItem(name: "toPlace", value: to.apiValue),
            URLQueryItem(name: "arriveBy", value: arriveBy ? "true" : "false"),
        ]
        if let time { q.append(URLQueryItem(name: "time", value: DateParsing.format(time))) }
        if let pageCursor { q.append(URLQueryItem(name: "pageCursor", value: pageCursor)) }
        return try await get("/api/v6/plan", q)
    }

    func departures(near center: LatLon, radius: Int, count: Int) async throws -> StopTimesResponse {
        try await get("/api/v6/stoptimes", [
            URLQueryItem(name: "center", value: center.apiValue),
            URLQueryItem(name: "radius", value: String(radius)),
            URLQueryItem(name: "n", value: String(count)),
        ])
    }

    func departures(stopId: String, count: Int) async throws -> StopTimesResponse {
        try await get("/api/v6/stoptimes", [
            URLQueryItem(name: "stopId", value: stopId),
            URLQueryItem(name: "n", value: String(count)),
            URLQueryItem(name: "withAlerts", value: "true"),
        ])
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem]) async throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        var req = URLRequest(url: comps.url!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let err = try? JSONDecoder().decode(ServerError.self, from: data) {
                throw APIError(message: err.error)
            }
            throw APIError(message: "Server error (HTTP \(status)).")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError(message: "Unexpected response from the routing service.")
        }
    }
}

enum DateParsing {
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parse(_ s: String) -> Date? { plain.date(from: s) ?? fractional.date(from: s) }
    static func format(_ d: Date) -> String { plain.string(from: d) }
}
