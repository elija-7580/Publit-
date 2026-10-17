import Foundation

/// Splits a started trip's route into the part already behind you and the part ahead,
/// like the light-blue trace in Apple Maps. Pure geometry, no MapKit: testable.
enum TripTrace {
    /// The live stage: which leg, what is happening on it, and the best known position.
    struct Progress: Equatable, Sendable {
        let legIndex: Int
        let kind: GuideStep.Kind
        /// GPS fix, or the vehicle's estimated position while riding. Nil: split at stage borders only.
        let point: LatLon?
    }

    struct Parts: Equatable {
        let done: [LatLon]
        let ahead: [LatLon]
    }

    /// Farther from the line than this, the fix says nothing about progress on it.
    static let maxOffsetMeters = 300.0

    static func split(_ points: [LatLon], legIndex: Int, at progress: Progress) -> Parts {
        if legIndex < progress.legIndex || progress.kind == .arrive { return Parts(done: points, ahead: []) }
        if legIndex > progress.legIndex || progress.kind == .wait { return Parts(done: [], ahead: points) }
        guard points.count > 1, let p = progress.point, let hit = nearest(on: points, to: p),
              hit.offset <= maxOffsetMeters else { return Parts(done: [], ahead: points) }
        return Parts(done: Array(points[...hit.segment]) + [hit.point],
                     ahead: [hit.point] + Array(points[(hit.segment + 1)...]))
    }

    /// Closest point on the polyline: segment index (start vertex), the point itself and its distance.
    static func nearest(on points: [LatLon], to p: LatLon) -> (segment: Int, point: LatLon, offset: Double)? {
        guard points.count > 1 else { return nil }
        let mx = 111_320 * cos(p.lat * .pi / 180), my = 110_540.0
        func xy(_ c: LatLon) -> (Double, Double) { ((c.lon - p.lon) * mx, (c.lat - p.lat) * my) }
        var best: (segment: Int, point: LatLon, offset: Double)?
        var a = xy(points[0])
        for i in 0..<(points.count - 1) {
            let b = xy(points[i + 1])
            let dx = b.0 - a.0, dy = b.1 - a.1
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, -(a.0 * dx + a.1 * dy) / len2)) : 0
            let qx = a.0 + t * dx, qy = a.1 + t * dy
            let d = (qx * qx + qy * qy).squareRoot()
            if best == nil || d < best!.offset {
                let q = LatLon(lat: p.lat + qy / my, lon: p.lon + qx / mx)
                best = (i, q, d)
            }
            a = b
        }
        return best
    }
}
