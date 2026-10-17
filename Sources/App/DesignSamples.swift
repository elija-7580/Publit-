#if DEBUG
import SwiftUI

/// A longer trip for design screenshots (route preview and live trip): walk, U6, change, S8 with a
/// delay and a platform change, walk. Times are minutes from launch; marked as a demo.
enum DesignSamples {
    static let base = Date()
    static let source = #"{"id":"design-sample","duration":3960,"startTime":"DATE:-7","endTime":"DATE:59","transfers":1,"legs":[{"mode":"WALK","from":{"name":"Zuhause","lat":48.166,"lon":11.589,"tz":"Europe/Berlin","departure":"DATE:-7","scheduledDeparture":"DATE:-7"},"to":{"name":"Münchner Freiheit","lat":48.1617,"lon":11.5866,"tz":"Europe/Berlin","arrival":"DATE:-2","scheduledArrival":"DATE:-2"},"duration":300,"startTime":"DATE:-7","endTime":"DATE:-2","scheduledStartTime":"DATE:-7","scheduledEndTime":"DATE:-2","realTime":false,"distance":420,"legGeometry":{"points":"_fyzzAowibUr`@vQp`@vQp`@vQr`@vQr`@vQp`@vQp`@vQr`@vQ","precision":6,"length":9}},{"mode":"SUBWAY","from":{"name":"Münchner Freiheit","lat":48.1617,"lon":11.5866,"tz":"Europe/Berlin","stopId":"d-Münchner Freiheit","departure":"DATE:-1","scheduledDeparture":"DATE:-1","track":"2","scheduledTrack":"2"},"to":{"name":"Marienplatz","lat":48.1372,"lon":11.5755,"tz":"Europe/Berlin","stopId":"d-Marienplatz","arrival":"DATE:8","scheduledArrival":"DATE:8"},"duration":540,"startTime":"DATE:-1","endTime":"DATE:8","scheduledStartTime":"DATE:-1","scheduledEndTime":"DATE:8","realTime":true,"headsign":"Klinikum Großhadern","routeShortName":"U6","routeColor":"0065AE","routeTextColor":"FFFFFF","displayName":"U6","tripId":"d-u6","intermediateStops":[{"name":"Giselastraße","lat":48.1563,"lon":11.5845,"tz":"Europe/Berlin","arrival":"DATE:1","departure":"DATE:1","scheduledArrival":"DATE:1","scheduledDeparture":"DATE:1"},{"name":"Universität","lat":48.15,"lon":11.5803,"tz":"Europe/Berlin","arrival":"DATE:3","departure":"DATE:3","scheduledArrival":"DATE:3","scheduledDeparture":"DATE:3"},{"name":"Odeonsplatz","lat":48.1426,"lon":11.5776,"tz":"Europe/Berlin","arrival":"DATE:5","departure":"DATE:5","scheduledArrival":"DATE:5","scheduledDeparture":"DATE:5"}],"legGeometry":{"points":"gypzzAoaebUnbAfYnbAfYnbAfYnbAfYnbAfYvmAns@vmAns@vmAns@vmAns@vmAns@n{Av`@n{Av`@n{Av`@n{Av`@n{Av`@nbAfYnbAfYnbAfYnbAfYnbAfY","precision":6,"length":25}},{"mode":"WALK","from":{"name":"Marienplatz","lat":48.1372,"lon":11.5755,"tz":"Europe/Berlin","departure":"DATE:8","scheduledDeparture":"DATE:8"},"to":{"name":"Marienplatz","lat":48.137,"lon":11.576,"tz":"Europe/Berlin","arrival":"DATE:11","scheduledArrival":"DATE:11"},"duration":180,"startTime":"DATE:8","endTime":"DATE:11","scheduledStartTime":"DATE:8","scheduledEndTime":"DATE:11","realTime":false,"distance":160,"legGeometry":{"points":"_~`yzAwkoaUp@{Bp@}Bp@}Bp@{Bp@{Bp@}Bp@}Bp@{B","precision":6,"length":9}},{"mode":"SUBURBAN","from":{"name":"Marienplatz","lat":48.137,"lon":11.576,"tz":"Europe/Berlin","stopId":"d-Marienplatz","departure":"DATE:17","scheduledDeparture":"DATE:14","track":"2","scheduledTrack":"1"},"to":{"name":"Flughafen München","lat":48.3537,"lon":11.7861,"tz":"Europe/Berlin","stopId":"d-Flughafen München","arrival":"DATE:55","scheduledArrival":"DATE:55"},"duration":2280,"startTime":"DATE:17","endTime":"DATE:55","scheduledStartTime":"DATE:14","scheduledEndTime":"DATE:52","realTime":true,"headsign":"Flughafen München","routeShortName":"S8","routeColor":"000000","routeTextColor":"FFFFFF","displayName":"S8","tripId":"d-s8","intermediateStops":[{"name":"Ostbahnhof","lat":48.127,"lon":11.605,"tz":"Europe/Berlin","arrival":"DATE:22","departure":"DATE:22","scheduledArrival":"DATE:19","scheduledDeparture":"DATE:19"},{"name":"Unterföhring","lat":48.199,"lon":11.66,"tz":"Europe/Berlin","arrival":"DATE:30","departure":"DATE:30","scheduledArrival":"DATE:27","scheduledDeparture":"DATE:27"},{"name":"Ismaning","lat":48.2265,"lon":11.682,"tz":"Europe/Berlin","arrival":"DATE:36","departure":"DATE:36","scheduledArrival":"DATE:33","scheduledDeparture":"DATE:33"}],"legGeometry":{"points":"oq`yzA_kpaU~{BoiJ~{BoiJ~{BoiJ~{BoiJ~{BoiJ_c[onT_c[onT_c[onT_c[onT_c[onTwvI_rGwvI_rGwvI_rGwvI_rGwvI_rG_up@gtg@_up@gtg@_up@gtg@_up@gtg@_up@gtg@","precision":6,"length":25}},{"mode":"WALK","from":{"name":"Flughafen München","lat":48.3537,"lon":11.7861,"tz":"Europe/Berlin","departure":"DATE:55","scheduledDeparture":"DATE:55"},"to":{"name":"END","lat":48.3547,"lon":11.782,"tz":"Europe/Berlin","arrival":"DATE:59","scheduledArrival":"DATE:59"},"duration":240,"startTime":"DATE:55","endTime":"DATE:59","scheduledStartTime":"DATE:55","scheduledEndTime":"DATE:59","realTime":false,"distance":350,"legGeometry":{"points":"gygf{AgvjnUyF~^yF`_@yF`_@yF~^yF~^yF`_@yF`_@yF~^","precision":6,"length":9}}]}"#

    static var itinerary: Itinerary {
        let raw = try! JSONSerialization.jsonObject(with: Data(source.utf8))
        func dates(_ value: Any) -> Any {
            if let text = value as? String, text.hasPrefix("DATE:"), let minutes = Double(text.dropFirst(5)) {
                return DateParsing.format(base.addingTimeInterval(minutes * 60))
            }
            if let object = value as? [String: Any] { return object.mapValues(dates) }
            if let array = value as? [Any] { return array.map(dates) }
            return value
        }
        let data = try! JSONSerialization.data(withJSONObject: dates(raw))
        return try! TransitousClient.makeDecoder().decode(Itinerary.self, from: data)
    }
}

/// The real trip screens on the sample trip: `PUBLIT_UI_SAMPLE=route` (preview) or `live` (started).
struct DesignSampleView: View {
    let kind: String
    @Environment(TripStore.self) private var trips
    @State private var tripId: String?

    var body: some View {
        NavigationStack {
            if kind.hasPrefix("route") {
                ItineraryDetailView(itinerary: DesignSamples.itinerary, fromName: "Zuhause", toName: "Flughafen München")
            } else if let tripId {
                SavedTripView(tripId: tripId)
            } else {
                ProgressView()
            }
        }
        .task {
            guard kind.hasPrefix("live"), tripId == nil else { return }
            let saved = trips.save(DesignSamples.itinerary, from: "Zuhause", to: "Flughafen München")
            trips.update(saved.id, with: DesignSamples.itinerary)
            _ = trips.start(saved.id)
            tripId = saved.id
        }
    }
}
#endif
