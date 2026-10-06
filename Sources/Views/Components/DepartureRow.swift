import SwiftUI

struct DepartureRow: View {
    let stopTime: StopTime

    var body: some View {
        HStack(spacing: 10) {
            LineBadge(stopTime)
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(stopTime.headsign.isEmpty ? "—" : stopTime.headsign)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let track = stopTime.place.track, !track.isEmpty {
                        Text("Platform \(track)")
                    }
                    if stopTime.isCancelled {
                        Text("Cancelled").foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            DepartureTimeView(actual: stopTime.departureTime,
                              delayMinutes: stopTime.delayMinutes,
                              realTime: stopTime.realTime,
                              cancelled: stopTime.isCancelled)
        }
        .padding(.vertical, 2)
    }
}
