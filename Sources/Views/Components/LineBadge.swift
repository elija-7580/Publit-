import SwiftUI

struct LineBadge: View {
    let name: String
    let mode: String
    let color: Color
    let textColor: Color

    init(_ route: some RouteStyled) {
        name = route.lineName
        mode = route.mode
        color = route.lineColor
        textColor = route.lineTextColor
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: ModeStyle.symbol(mode))
                .font(.caption2.weight(.bold))
            Text(name)
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .foregroundStyle(textColor)
        .background(color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ModeStyle.label(mode)) \(name)")
    }
}

/// Countdown plus delay and live indicator, refreshed every 15 s.
struct DepartureTimeView: View {
    let actual: Date
    let delayMinutes: Int
    let realTime: Bool
    let cancelled: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let minutes = Int(floor(actual.timeIntervalSince(ctx.date) / 60))
            VStack(alignment: .trailing, spacing: 2) {
                Group {
                    if minutes <= 0 {
                        Text("now")
                    } else if minutes < 60 {
                        Text("\(minutes) min")
                    } else {
                        Text(Fmt.time(actual))
                    }
                }
                .font(.body.weight(.semibold).monospacedDigit())
                .strikethrough(cancelled)
                .foregroundStyle(cancelled ? Color.secondary : (realTime ? Color.green : Color.primary))

                HStack(spacing: 4) {
                    if delayMinutes > 0 {
                        Text("+\(delayMinutes)").foregroundStyle(.orange)
                    }
                    Text(Fmt.time(actual)).foregroundStyle(.secondary)
                }
                .font(.caption2.monospacedDigit())
            }
        }
    }
}

struct AttributionFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link("Routing and timetables: Transitous and its data sources", destination: AppInfo.sourcesURL)
            Link("Map data © OpenStreetMap contributors", destination: AppInfo.osmCopyrightURL)
        }
        .font(.footnote)
    }
}
