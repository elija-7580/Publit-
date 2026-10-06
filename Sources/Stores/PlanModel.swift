import Foundation
import Observation

enum Endpoint: Hashable {
    case currentLocation
    case place(SavedPlace)

    var title: String {
        switch self {
        case .currentLocation: return "Current location"
        case .place(let p): return p.name
        }
    }

    var key: String {
        switch self {
        case .currentLocation: return "here"
        case .place(let p): return p.id
        }
    }

    func coordinate(current: LatLon?) -> LatLon? {
        switch self {
        case .currentLocation: return current
        case .place(let p): return p.coordinate
        }
    }
}

enum TimeMode: String, CaseIterable, Identifiable {
    case now = "Now"
    case departAt = "Depart"
    case arriveBy = "Arrive"
    var id: String { rawValue }
}

@MainActor
@Observable
final class PlanModel {
    var from: Endpoint = .currentLocation
    var to: Endpoint?
    var timeMode: TimeMode = .now
    var date = Date()

    private(set) var itineraries: [Itinerary] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?

    private var nextCursor: String?
    @ObservationIgnored private var lastRequest: (from: LatLon, to: LatLon, time: Date?, arriveBy: Bool)?
    @ObservationIgnored private var token = UUID()

    var canLoadMore: Bool { nextCursor != nil && !itineraries.isEmpty }

    /// Changes whenever a new search is needed.
    var queryKey: String {
        let t = timeMode == .now ? "now" : String(Int(date.timeIntervalSince1970 / 60))
        return "\(from.key)|\(to?.key ?? "-")|\(timeMode.rawValue)|\(t)"
    }

    func swap() {
        guard let t = to else { return }
        to = from
        from = t
    }

    func search(current: LatLon?) async {
        guard let to else {
            itineraries = []; errorMessage = nil; return
        }
        guard let f = from.coordinate(current: current), let t = to.coordinate(current: current) else {
            errorMessage = "Waiting for your location…"
            return
        }
        let myToken = UUID()
        token = myToken
        isLoading = true
        errorMessage = nil
        let time: Date? = timeMode == .now ? nil : date
        let arriveBy = timeMode == .arriveBy
        do {
            let res = try await TransitousClient.shared.plan(from: f, to: t, time: time, arriveBy: arriveBy)
            guard token == myToken else { return }
            itineraries = res.itineraries.isEmpty ? res.direct : res.itineraries
            nextCursor = arriveBy ? res.previousPageCursor : res.nextPageCursor
            lastRequest = (f, t, time, arriveBy)
            if itineraries.isEmpty { errorMessage = "No connections found." }
        } catch {
            guard token == myToken, !Self.isCancellation(error) else { return }
            itineraries = []
            errorMessage = error.localizedDescription
        }
        if token == myToken { isLoading = false }
    }

    func loadMore() async {
        guard let req = lastRequest, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let res = try await TransitousClient.shared.plan(from: req.from, to: req.to, time: req.time,
                                                             arriveBy: req.arriveBy, pageCursor: cursor)
            let known = Set(itineraries.map(\.id))
            let fresh = res.itineraries.filter { !known.contains($0.id) }
            itineraries = (itineraries + fresh).sorted { $0.startTime < $1.startTime }
            nextCursor = req.arriveBy ? res.previousPageCursor : res.nextPageCursor
        } catch {
            if !Self.isCancellation(error) { errorMessage = error.localizedDescription }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let e = error as? URLError, e.code == .cancelled { return true }
        return false
    }
}

enum AppTab: Hashable { case nearby, plan, favorites }

@MainActor
@Observable
final class AppState {
    var tab: AppTab = .nearby
    let plan = PlanModel()

    func route(to place: SavedPlace) {
        plan.to = .place(place)
        tab = .plan
    }
}
