import Foundation

enum Polyline {
    /// Decodes a Google encoded polyline with the given decimal precision.
    static func decode(_ encoded: String, precision: Int) -> [LatLon] {
        let bytes = Array(encoded.utf8)
        let factor = pow(10.0, Double(precision))
        var coords: [LatLon] = []
        var index = 0
        var lat = 0
        var lon = 0

        func next() -> Int? {
            var result = 0
            var shift = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil
        }

        while index < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            coords.append(LatLon(lat: Double(lat) / factor, lon: Double(lon) / factor))
        }
        return coords
    }
}
