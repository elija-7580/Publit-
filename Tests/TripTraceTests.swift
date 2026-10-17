import XCTest
@testable import Publit

/// The light-blue trace behind you on the live-trip map, and route identity across refreshes.
final class TripTraceTests: XCTestCase {
    private let line = [LatLon(lat: 48.0, lon: 11.0), LatLon(lat: 48.0, lon: 11.01), LatLon(lat: 48.0, lon: 11.02)]

    func testLegsBeforeTheLiveOneAreBehindYou() {
        let p = TripTrace.Progress(legIndex: 2, kind: .ride, point: nil)
        XCTAssertEqual(TripTrace.split(line, legIndex: 1, at: p), .init(done: line, ahead: []))
        XCTAssertEqual(TripTrace.split(line, legIndex: 3, at: p), .init(done: [], ahead: line))
    }

    func testWaitingMeansTheRideHasNotStarted() {
        let p = TripTrace.Progress(legIndex: 1, kind: .wait, point: LatLon(lat: 48.0, lon: 11.015))
        XCTAssertEqual(TripTrace.split(line, legIndex: 1, at: p).done, [])
    }

    func testArrivedMeansEverythingIsBehindYou() {
        let p = TripTrace.Progress(legIndex: 1, kind: .arrive, point: nil)
        XCTAssertEqual(TripTrace.split(line, legIndex: 1, at: p).ahead, [])
    }

    func testSplitsTheLiveLegWhereYouAre() {
        let p = TripTrace.Progress(legIndex: 0, kind: .walk, point: LatLon(lat: 48.0001, lon: 11.015))
        let parts = TripTrace.split(line, legIndex: 0, at: p)
        XCTAssertEqual(parts.done.count, 3)
        XCTAssertEqual(parts.ahead.count, 2)
        XCTAssertEqual(parts.done.last!.lon, 11.015, accuracy: 1e-6)
        XCTAssertEqual(parts.done.last!.lat, 48.0, accuracy: 1e-6)
        XCTAssertEqual(parts.done.last, parts.ahead.first)
    }

    func testAFixFarFromTheLineSaysNothing() {
        let p = TripTrace.Progress(legIndex: 0, kind: .walk, point: LatLon(lat: 48.01, lon: 11.015))
        XCTAssertEqual(TripTrace.split(line, legIndex: 0, at: p), .init(done: [], ahead: line))
    }
}
