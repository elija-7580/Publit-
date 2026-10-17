import XCTest
@testable import Publit

final class TripGuideTests: XCTestCase {
    private let t0 = 1_791_360_000.0

    private func leg(_ mode: String, _ from: (String, Double), _ to: (String, Double), start: Int, end: Int,
                     stops: [(String, Double, Int)] = []) throws -> Leg {
        func iso(_ m: Int) -> String { DateParsing.format(Date(timeIntervalSince1970: t0 + Double(m) * 60)) }
        let mid = stops.map { s in
            "{\"name\":\"\(s.0)\",\"lat\":48,\"lon\":\(s.1),\"arrival\":\"\(iso(s.2))\",\"departure\":\"\(iso(s.2))\"}"
        }.joined(separator: ",")
        let json = """
        {"mode":"\(mode)","from":{"name":"\(from.0)","lat":48,"lon":\(from.1),"departure":"\(iso(start))"},
         "to":{"name":"\(to.0)","lat":48,"lon":\(to.1),"arrival":"\(iso(end))"},
         "duration":\((end - start) * 60),"startTime":"\(iso(start))","endTime":"\(iso(end))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))",
         "realTime":true,"intermediateStops":[\(mid)],"legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private func at(_ minute: Double) -> Date { Date(timeIntervalSince1970: t0 + minute * 60) }

    private func trip() throws -> Itinerary {
        let legs = [try leg("WALK", ("Home", 11.000), ("A", 11.004), start: 0, end: 5),
                    try leg("SUBWAY", ("A", 11.004), ("D", 11.040), start: 8, end: 20,
                            stops: [("B", 11.016, 12), ("C", 11.028, 16)]),
                    try leg("WALK", ("D", 11.040), ("D", 11.040), start: 20, end: 20),
                    try leg("BUS", ("D", 11.040), ("E", 11.060), start: 24, end: 30),
                    try leg("WALK", ("E", 11.060), ("Office", 11.063), start: 30, end: 34)]
        return Itinerary(id: "g", duration: 34 * 60, startTime: legs[0].startTime, endTime: legs[4].endTime,
                         transfers: 1, legs: legs)
    }

    func testStagesSkipTheShortChangeWalk() throws {
        let kinds = TripGuide.steps(try trip()).map { "\($0.kind.rawValue)\($0.legIndex)" }
        XCTAssertEqual(kinds, ["walk0", "wait1", "ride1", "wait3", "ride3", "walk4", "arrive4"])
    }

    func testStageFollowsTheClock() throws {
        let it = try trip(), steps = TripGuide.steps(it)
        func kind(_ m: Double) -> String { let s = steps[TripGuide.timeIndex(steps, it, at: at(m))]; return "\(s.kind.rawValue)\(s.legIndex)" }
        XCTAssertEqual(kind(-10), "walk0")
        XCTAssertEqual(kind(6), "wait1")
        XCTAssertEqual(kind(10), "ride1")
        XCTAssertEqual(kind(21), "wait3")
        XCTAssertEqual(kind(26), "ride3")
        XCTAssertEqual(kind(31), "walk4")
        XCTAssertEqual(kind(40), "arrive4")
    }

    func testTripEndsAtTheDestinationOrLaterByItself() throws {
        let it = try trip()
        let office = LatLon(lat: 48, lon: 11.063)
        XCTAssertFalse(TripGuide.isFinished(it, at: at(25), location: office), "still riding: not over at the door")
        XCTAssertTrue(TripGuide.isFinished(it, at: at(31), location: office))
        XCTAssertFalse(TripGuide.isFinished(it, at: at(31), location: LatLon(lat: 48, lon: 11.060)))
        XCTAssertFalse(TripGuide.isFinished(it, at: at(40), location: nil))
        XCTAssertTrue(TripGuide.isFinished(it, at: at(45), location: nil))
    }

    func testOnlyCurrentNearbyWalkUsesGPSProgress() throws {
        let route = WalkRoute(leg: try trip().legs[0])
        let halfway = LatLon(lat: 48, lon: 11.002)
        let active = try XCTUnwrap(route.livePosition(of: halfway, isActive: true))
        XCTAssertGreaterThan(active.remaining, 0)
        XCTAssertLessThan(active.remaining, route.length * route.scale)
        XCTAssertNil(route.livePosition(of: halfway, isActive: false), "preview retains its full distance")
        XCTAssertNil(route.livePosition(of: LatLon(lat: 48.1, lon: 11.002), isActive: true), "far-away GPS must not shorten a route")
        XCTAssertNil(route.livePosition(of: nil, isActive: true))
    }

    func testPositionMovesTheStage() throws {
        let it = try trip(), steps = TripGuide.steps(it)
        // Already at the stop while the clock still says walking.
        XCTAssertEqual(steps[TripGuide.current(steps, it, at: at(2), location: LatLon(lat: 48, lon: 11.0042))].kind, .wait)
        // Still far from the stop when the walk should be over.
        XCTAssertEqual(steps[TripGuide.current(steps, it, at: at(6), location: LatLon(lat: 48, lon: 11.0))].kind, .walk)
        XCTAssertEqual(steps[TripGuide.current(steps, it, at: at(6), location: nil)].kind, .wait)
    }

    func testRidePositionFromGPSAndStopsLeft() throws {
        let ride = try trip().legs[1]
        let between = TripGuide.ridePosition(ride, at: at(13), location: LatLon(lat: 48, lon: 11.022))
        XCTAssertTrue(between.fromGPS)
        guard case .between(let i, let f) = between.progress else { return XCTFail("\(between.progress)") }
        XCTAssertEqual(i, 1)
        XCTAssertEqual(f, 0.5, accuracy: 0.1)
        XCTAssertEqual(TripGuide.stopsLeft(between.progress, count: 4), 2)
        let atC = TripGuide.ridePosition(ride, at: at(15), location: LatLon(lat: 48, lon: 11.0281))
        XCTAssertEqual(atC.progress, .atStop(index: 2))
        XCTAssertEqual(TripGuide.stopsLeft(atC.progress, count: 4), 1)
        // Far from the line: the timetable estimate.
        let off = TripGuide.ridePosition(ride, at: at(13), location: LatLon(lat: 48.05, lon: 11.022))
        XCTAssertFalse(off.fromGPS)
    }

    func testMissedWhenStillAtTheStopAfterDeparture() throws {
        let it = try trip(), steps = TripGuide.steps(it)
        let ride = steps[2]
        XCTAssertEqual(TripGuide.check(ride, it, at: at(14), location: LatLon(lat: 48, lon: 11.004), accuracy: 10, walk: nil), .missed)
        XCTAssertEqual(TripGuide.check(ride, it, at: at(14), location: LatLon(lat: 48, lon: 11.028), accuracy: 10, walk: nil), .fine)
    }

    func testTurnKinds() {
        XCTAssertEqual(WalkRoute.turnKind(90), .right)
        XCTAssertEqual(WalkRoute.turnKind(-90), .left)
        XCTAssertEqual(WalkRoute.turnKind(-45), .slightLeft)
        XCTAssertEqual(WalkRoute.turnKind(150), .sharpRight)
        XCTAssertEqual(WalkRoute.turnKind(175), .uTurn)
        XCTAssertNil(WalkRoute.turnKind(20))
    }

    private func walkLeg() throws -> Leg {
        let res = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_walk_steps"))
        return try XCTUnwrap(res.itineraries.first?.legs.first)
    }

    func testStairsFollowTheWalkingDirection() throws {
        let leg = try walkLeg()
        XCTAssertEqual(leg.steps?.count, 13)
        let route = WalkRoute(leg: leg)
        let stairs = route.maneuvers.filter { $0.kind == .stairsDown }
        XCTAssertEqual(stairs.map(\.level), [-1, -2])
        XCTAssertFalse(route.maneuvers.contains { $0.kind == .stairsUp })
        XCTAssertEqual(route.maneuvers.first?.kind, .start)
        XCTAssertEqual(route.maneuvers.last?.kind, .arrive)
        // Entrance codes are not street names.
        XCTAssertFalse(route.maneuvers.contains { $0.street == "HO06" })
        XCTAssertEqual(stairs.first?.instruction(destination: "x"), "Take the stairs down (level −1)")
        // Shown distances follow the router's total, not the flat map line.
        XCTAssertEqual(route.maneuvers.reduce(0) { $0 + $1.distance }, leg.distance ?? 0, accuracy: 1)
    }

    func testPositionOnTheWalk() throws {
        let route = WalkRoute(leg: try walkLeg())
        let p = try XCTUnwrap(PathGeometry.point(at: 60, on: route.path))
        let pos = try XCTUnwrap(route.position(of: p))
        XCTAssertEqual(pos.along, 60, accuracy: 2)
        XCTAssertLessThan(pos.offset, 1)
        XCTAssertEqual(route.maneuvers[pos.index].kind, .stairsDown)
        XCTAssertFalse(WalkRoute.isOffRoute(pos, accuracy: 10))
        let away = try XCTUnwrap(route.position(of: LatLon(lat: p.lat + 0.002, lon: p.lon)))
        XCTAssertTrue(WalkRoute.isOffRoute(away, accuracy: 10))
    }

    func testStepsSurviveSavingATrip() throws {
        let res = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_walk_steps"))
        let it = try XCTUnwrap(res.itineraries.first)
        let data = try JSONFile<Itinerary>.encoder.encode(it)
        let back = try TransitousClient.makeDecoder().decode(Itinerary.self, from: data)
        XCTAssertEqual(back.legs.first?.steps?.count, 13)
        XCTAssertEqual(WalkRoute(leg: back.legs[0]).maneuvers, WalkRoute(leg: it.legs[0]).maneuvers)
    }
}
