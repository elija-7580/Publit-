import XCTest
@testable import Publit

final class DecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testPolylineGoogleReferenceExample() {
        let coords = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 5)
        XCTAssertEqual(coords.count, 3)
        XCTAssertEqual(coords[0].lat, 38.5, accuracy: 1e-9)
        XCTAssertEqual(coords[2].lon, -126.453, accuracy: 1e-9)
    }

    func testDecodesPlanResponse() throws {
        let plan = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: fixture("plan"))
        XCTAssertFalse(plan.itineraries.isEmpty)
        let it = plan.itineraries[0]
        XCTAssertGreaterThan(it.transitLegs.count, 0)
        for leg in it.legs {
            XCTAssertEqual(leg.legGeometry.coordinates.count, leg.legGeometry.length)
        }
        XCTAssertNotNil(it.firstTransitLeg?.displayName)
    }

    func testDecodesStopTimes() throws {
        let res = try TransitousClient.makeDecoder().decode(StopTimesResponse.self, from: fixture("stoptimes"))
        XCTAssertFalse(res.stopTimes.isEmpty)
        XCTAssertNotEqual(res.stopTimes[0].departureTime, .distantPast)
    }

    func testDecodesGeocode() throws {
        let matches = try TransitousClient.makeDecoder().decode([GeocodeMatch].self, from: fixture("geocode"))
        XCTAssertFalse(matches.isEmpty)
        XCTAssertFalse(matches[0].subtitle.isEmpty)
    }

    func testDateParsingWithAndWithoutFraction() {
        XCTAssertNotNil(DateParsing.parse("2026-10-06T20:18:00Z"))
        XCTAssertNotNil(DateParsing.parse("2026-10-06T20:18:00.123Z"))
    }
}
