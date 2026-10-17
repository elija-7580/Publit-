import SwiftUI

/// A saved trip with its live status. Opened from Plan, from the calendar entry and from the Live Activity.
struct SavedTripView: View {
    let tripId: String
    @Environment(TripStore.self) private var trips
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var errorMessage: String?
    @Environment(\.liveBarInset) private var liveInset

    var body: some View {
        if let trip = trips.trip(tripId) {
            Group {
                // Started by hand: the trip screen becomes the step-by-step guide until it is ended.
                if trips.activeTrip?.id == tripId {
                    LiveTripView(trip: trip)
                } else {
                    ItineraryDetailView(itinerary: trip.itinerary, fromName: trip.fromName, toName: trip.toName,
                                        statusAt: { TripStatus.at($0, trip.itinerary) }, refreshedAt: trip.refreshedAt)
                    .navigationTitle(trip.toName)
                    .screenTrail("Saved trip")
                }
            }
            .environment(\.liveBarInset, errorMessage == nil ? liveInset : 0)
            // On the live trip the panel covers the bottom: the note sits at the top there.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let errorMessage, trips.activeTrip?.id == tripId {
                    Text(errorMessage).font(.caption).padding(8)
                        .matteSurface(in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 12).padding(.top, 4)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let errorMessage, trips.activeTrip?.id != tripId {
                    Text(errorMessage).font(.caption).padding(8)
                        .matteSurface(in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 12).padding(.bottom, 8 + liveInset)
                }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .task(id: "\(tripId)|\(scenePhase)|\(isVisible)") {
                guard isVisible, scenePhase == .active else { return }
                // Live status: refresh now and every minute until the trip is over.
                while !Task.isCancelled {
                    guard let t = trips.trip(tripId), t.endTime.addingTimeInterval(15 * 60) > .now else { break }
                    await refresh(t)
                    try? await Task.sleep(for: Energy.duration(60))
                }
            }
        } else {
            ContentUnavailableView("Trip not found", systemImage: "bookmark.slash",
                                   description: Text("It was removed from this device."))
        }
    }

    private func refresh(_ t: SavedTrip) async {
        errorMessage = await Self.refresh(t, in: trips) ? nil : L10n.t("Live status unavailable. Showing saved times.")
    }

    /// New live times for a saved trip, also for its Live Activity and leave reminder (trip screen and
    /// live bar). False only for a real failure; a cancelled refresh counts as fine.
    @discardableResult
    static func refresh(_ t: SavedTrip, in trips: TripStore) async -> Bool {
        do {
            let fresh = try await TripRefreshCoordinator.shared.refresh(t.itinerary.id)
            try Task.checkCancellation()
            trips.update(t.id, with: fresh)
            if let updated = trips.trip(t.id) {
                await LiveTripActivity.update(updated)
                await LeaveReminder.follow(t, to: updated)
                await GetOffReminder.follow(from: t.itinerary, to: updated.itinerary)
                if trips.activeTripId == t.id || LiveTripActivity.isRunning(t.id) {
                    await TripChangeAlert.follow(t.id, from: t.itinerary, to: updated.itinerary)
                }
            }
            return true
        } catch {
            return error is CancellationError || (error as? URLError)?.code == .cancelled
        }
    }
}

/// One saved trip in a list.
struct SavedTripRow: View {
    let trip: SavedTrip

    var body: some View {
        let tz = trip.itinerary.legs.first?.from.tz
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.toName).font(.headline).lineLimit(1)
                Spacer()
                Text(trip.startTime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text("\(Fmt.time(trip.startTime, tz: tz)) – \(Fmt.time(trip.endTime, tz: trip.itinerary.legs.last?.to.tz))")
                .font(.subheadline.monospacedDigit()).lineLimit(1)
            HStack(spacing: 6) {
                ForEach(Array(trip.itinerary.transitLegs.prefix(4).enumerated()), id: \.offset) { _, leg in
                    LineBadge(leg)
                }
            }
            Text("from \(trip.fromName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
