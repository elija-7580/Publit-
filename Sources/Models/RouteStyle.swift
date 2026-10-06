import SwiftUI

/// Shared line-styling for legs and departures.
protocol RouteStyled {
    var mode: String { get }
    var routeColor: String? { get }
    var routeTextColor: String? { get }
    var routeShortName: String? { get }
    var displayName: String? { get }
}

extension RouteStyled {
    var lineName: String {
        let name = (displayName?.isEmpty == false ? displayName : routeShortName) ?? ""
        return name.isEmpty ? ModeStyle.label(mode) : name
    }
    var lineColor: Color { Color(hex: routeColor) ?? ModeStyle.color(mode) }
    var lineTextColor: Color {
        if let c = Color(hex: routeTextColor), routeColor != nil { return c }
        return .white
    }
}

enum ModeStyle {
    private static let streetModes: Set<String> = [
        "WALK", "BIKE", "RENTAL", "CAR", "HGV", "CAR_PARKING", "CAR_DROPOFF"
    ]

    static func isTransit(_ mode: String) -> Bool { !streetModes.contains(mode) }

    static func symbol(_ mode: String) -> String {
        switch mode {
        case "WALK": return "figure.walk"
        case "BIKE", "RENTAL": return "bicycle"
        case "CAR", "CAR_PARKING", "CAR_DROPOFF", "ODM", "RIDE_SHARING", "HGV": return "car.fill"
        case "BUS", "COACH", "FLEX": return "bus.fill"
        case "TRAM": return "tram.fill"
        case "SUBWAY", "METRO": return "tram.fill.tunnel"
        case "FERRY": return "ferry.fill"
        case "AIRPLANE": return "airplane"
        case "FUNICULAR", "AERIAL_LIFT", "AREAL_LIFT", "CABLE_CAR": return "cablecar.fill"
        default: return "train.side.front.car"
        }
    }

    static func label(_ mode: String) -> String {
        switch mode {
        case "WALK": return "Walk"
        case "BIKE": return "Bike"
        case "RENTAL": return "Rental"
        case "BUS": return "Bus"
        case "COACH": return "Coach"
        case "TRAM": return "Tram"
        case "SUBWAY", "METRO": return "Metro"
        case "FERRY": return "Ferry"
        case "AIRPLANE": return "Flight"
        case "SUBURBAN": return "S-Bahn"
        case "HIGHSPEED_RAIL": return "High-speed"
        case "NIGHT_RAIL": return "Night train"
        default: return "Train"
        }
    }

    static func color(_ mode: String) -> Color {
        switch mode {
        case "BUS", "COACH", "FLEX": return Color(red: 0.16, green: 0.45, blue: 0.80)
        case "TRAM": return Color(red: 0.80, green: 0.15, blue: 0.20)
        case "SUBWAY", "METRO": return Color(red: 0.35, green: 0.25, blue: 0.70)
        case "FERRY": return Color(red: 0.05, green: 0.55, blue: 0.65)
        case "SUBURBAN": return Color(red: 0.10, green: 0.55, blue: 0.30)
        case "WALK", "BIKE", "RENTAL", "CAR": return .gray
        default: return Color(red: 0.30, green: 0.30, blue: 0.35)
        }
    }
}
