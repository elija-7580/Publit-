import Foundation

/// One stage of a trip in the step-by-step guide: walk, wait for the vehicle, ride, arrive.
struct GuideStep: Hashable, Sendable, Identifiable {
    enum Kind: String, Sendable { case walk, wait, ride, arrive }
    let kind: Kind
    /// The walk or transit leg (for `arrive` the last leg).
    let legIndex: Int
    var id: String { "\(kind.rawValue)\(legIndex)" }
}

/// The guide through a started trip: which stage is on now, by the (live) times and, while the
/// screen is open, by the phone's position.
enum TripGuide {
    /// Walks shorter than this between two vehicles are part of the change, not a stage of their own.
    static let minWalk = 45

    static func steps(_ it: Itinerary) -> [GuideStep] {
        var out: [GuideStep] = []
        for (i, leg) in it.legs.enumerated() {
            if leg.isTransit {
                out.append(GuideStep(kind: .wait, legIndex: i))
                out.append(GuideStep(kind: .ride, legIndex: i))
            } else if leg.duration >= minWalk || it.legs.count == 1 {
                out.append(GuideStep(kind: .walk, legIndex: i))
            }
        }
        out.append(GuideStep(kind: .arrive, legIndex: max(it.legs.count - 1, 0)))
        return out
    }

    /// The stage by the clock alone.
    static func timeIndex(_ steps: [GuideStep], _ it: Itinerary, at now: Date) -> Int {
        for (k, s) in steps.enumerated() {
            guard it.legs.indices.contains(s.legIndex) else { continue }
            let leg = it.legs[s.legIndex]
            switch s.kind {
            case .walk, .ride: if now < leg.endTime { return k }
            case .wait: if now < leg.startTime { return k }
            case .arrive: return k
            }
        }
        return max(steps.count - 1, 0)
    }

    /// The stage now. A fix moves it on when the stop is reached early, and back to the walk
    /// while the stop is still far away.
    /// The trip is over: at the destination once the last ride is over, or ten minutes after the arrival.
    static func isFinished(_ it: Itinerary, at now: Date, location: LatLon?) -> Bool {
        guard let last = it.legs.last else { return true }
        if now > it.endTime.addingTimeInterval(10 * 60) { return true }
        let lastRideEnd = it.legs.last(where: \.isTransit)?.endTime ?? it.startTime
        if let location, now >= lastRideEnd, location.distance(to: last.to.coordinate) < 80 { return true }
        return false
    }

    static func current(_ steps: [GuideStep], _ it: Itinerary, at now: Date, location: LatLon?) -> Int {
        let k = timeIndex(steps, it, at: now)
        guard let loc = location, steps.indices.contains(k) else { return k }
        let s = steps[k]
        if s.kind == .walk, k + 1 < steps.count {
            let next = steps[k + 1]
            let target = next.kind == .wait ? it.legs[next.legIndex].from.coordinate : it.legs[s.legIndex].to.coordinate
            if loc.distance(to: target) < (next.kind == .wait ? 50 : 30) { return k + 1 }
        }
        if s.kind == .wait, k > 0, steps[k - 1].kind == .walk,
           loc.distance(to: it.legs[s.legIndex].from.coordinate) > 250 {
            return k - 1
        }
        return k
    }

    /// Position along a ride: from GPS when it fits the timetable (within three stops), else by time.
    static func ridePosition(_ leg: Leg, at now: Date, location: LatLon?) -> (progress: TripProgress, fromGPS: Bool) {
        let stops = leg.allStops
        let byTime = TripProgress.at(now, stops: stops)
        guard let location, now >= leg.startTime.addingTimeInterval(-60), now <= leg.endTime.addingTimeInterval(10 * 60),
              let gps = TripProgress.located(location, stops: stops, path: leg.legGeometry.coordinates) else {
            return (byTime, false)
        }
        guard abs(gps.stopValue(count: stops.count) - byTime.stopValue(count: stops.count)) <= 3 else { return (byTime, false) }
        return (gps, true)
    }

    /// Stops still to come before (and including) the one to get off at.
    static func stopsLeft(_ progress: TripProgress, count: Int) -> Int {
        switch progress {
        case .notStarted: return max(count - 1, 0)
        case .atStop(let i): return max(count - 1 - i, 0)
        case .between(let i, _): return max(count - 1 - i - 1, 0) + 1
        case .finished: return 0
        }
    }

    enum Check: Equatable, Sendable { case fine, offRoute, missed }

    /// Something to offer a new route for: walking away from the path, or still at the stop
    /// well after the vehicle left.
    static func check(_ step: GuideStep, _ it: Itinerary, at now: Date, location: LatLon?, accuracy: Double,
                      walk: WalkRoute?) -> Check {
        guard let location, it.legs.indices.contains(step.legIndex) else { return .fine }
        let leg = it.legs[step.legIndex]
        switch step.kind {
        case .walk:
            guard let walk, let pos = walk.position(of: location) else { return .fine }
            return WalkRoute.isOffRoute(pos, accuracy: accuracy) ? .offRoute : .fine
        case .ride:
            guard now > leg.startTime.addingTimeInterval(120),
                  location.distance(to: leg.from.coordinate) < 150 else { return .fine }
            let stops = leg.allStops
            guard let vehicle = TripProgress.position(TripProgress.at(now, stops: stops), stops: stops) else {
                return now < leg.endTime ? .fine : .missed
            }
            return vehicle.distance(to: leg.from.coordinate) > 600 ? .missed : .fine
        case .wait, .arrive:
            return .fine
        }
    }
}
