# Publit

Fast, ad-free public transport for iPhone. Departures near you, trip planning across Europe, and a route overview that lets you compare every connection on one time axis.

Open source (MIT), free, no account, no tracking. watchOS companion planned.

## Why

Mainstream transit apps bury the information you need at the stop behind ads, slow screens, and subscriptions. Publit shows the same core information natively, instantly, and without a paywall.

## Features (v0.1)

- **Nearby:** live departure boards for all stops within 500 m (1.5 km fallback), grouped by station, auto-refresh every 30 s, delay and live indicators, platforms.
- **Plan:** from/to search (addresses, stops, places), depart-at / arrive-by, auto-search on every change.
- **Compare routes:** all connections on a shared timeline bar, plus a map that overlays every route with the selected one highlighted. Earlier/later paging.
- **Route detail:** map, legs with lines, platforms, delays, stop counts, alerts.
- **Saved:** favourite stops and places, stored on the device only.

## How it works

| Layer | Choice |
| --- | --- |
| UI | SwiftUI, iOS 17+, Observation, MapKit for SwiftUI |
| Data | [Transitous](https://transitous.org) MOTIS 2 API (`/api/v6/plan`, `/api/v6/stoptimes`, `/api/v1/geocode`) |
| Coverage | Open GTFS / GTFS-RT feeds aggregated by Transitous. Europe is the launch focus; quality varies by region. |
| State | `AppState` → `PlanModel`, `LocationManager`, `FavoritesStore` injected via `environment` |

```
Sources/
  App/        entry point, tabs, app info
  API/        TransitousClient (User-Agent, decoding, errors)
  Models/     Decodable API models, line styling
  Location/   CoreLocation wrapper
  Stores/     favourites, trip-planning state
  Util/       polyline decoder, formatting
  Views/      Nearby, Plan, Route detail, Search, Saved
Tests/        decoding + polyline tests with recorded API fixtures
```

## Build

Requirements: macOS with Xcode 15 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Publit.xcodeproj
```

Before the first build:

1. Set `PublitContact` in `project.yml` to the public repository URL (sent in the User-Agent, required by Transitous).
2. Set `DEVELOPMENT_TEAM` and, if needed, `PRODUCT_BUNDLE_IDENTIFIER` to values from your Apple developer account.
3. Run `xcodegen generate` again after editing `project.yml`.

Run tests with ⌘U.

## Data use and attribution

Publit uses the community-run Transitous API under its [usage policy](https://transitous.org/api/): open-source code, non-commercial use, an identifying User-Agent, and visible attribution to [Transitous' data sources](https://transitous.org/sources/) and [OpenStreetMap](https://www.openstreetmap.org/copyright). Before a public release with real user numbers, coordinate expected load with the Transitous team on Matrix.

Publit is an independent project. It does not use code, assets, text, data, or APIs from any other transit app.

## Roadmap

- Live Activities and widgets for the next departure
- watchOS companion (nearby departures, saved stops)
- Line and trip view with live vehicle position
- Service alerts on favourites
- Offline cache for saved stops

## License

MIT, see [LICENSE](LICENSE).
