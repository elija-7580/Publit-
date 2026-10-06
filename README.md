# Publit

**Public transport, without the noise.** A free, open-source transit app for iPhone: live departures near you, trip planning across Europe, and every connection on one timeline.

No ads, no account, no tracking.

![Publit on iPhone](docs/images/hero.jpg)

| Nearby | Plan | Compare | Route |
| --- | --- | --- | --- |
| ![Nearby departures](docs/images/nearby.jpg) | ![Trip planning](docs/images/plan.jpg) | ![Route comparison on a map](docs/images/compare.jpg) | ![Route detail](docs/images/detail.jpg) |

<sub>Prototype renderings of the v0.1 interface, filled with live Transitous data (Munich, October 2026).</sub>

## Status

Early prototype (v0.1). Not on the App Store yet.

## Features

- **Nearby:** live departure boards for every stop within 500 m, grouped by station, refreshed every 30 s, with delays, platforms and cancellations.
- **Plan:** search addresses, stops and places; depart at or arrive by.
- **Compare:** all connections on a shared timeline, plus a map that overlays every option.
- **Route detail:** legs, lines, platforms, stop counts, transfers and service alerts.
- **Saved:** favourite stops and places, stored only on the device.

## Coverage

Publit gets its routing and timetables from [Transitous](https://transitous.org), a community-run service that combines open GTFS and GTFS-Realtime feeds. Where a city's data is missing or broken, the project fixes it upstream so that every open app benefits. Example: [`feeds/amtab-gtfsrt`](feeds/amtab-gtfsrt) converts the real-time data of the Bari city buses (AMTAB) into standard GTFS-Realtime.

## Build

Requirements: macOS, Xcode 15 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Publit.xcodeproj
```

Set your Apple team in Xcode under Signing & Capabilities (or `DEVELOPMENT_TEAM` in `project.yml`). Run the tests with ⌘U.

```
Sources/
  App/        entry point, tabs, app info
  API/        Transitous client
  Models/     API models, line styling
  Location/   CoreLocation wrapper
  Stores/     favourites, trip-planning state
  Util/       polyline decoder, formatting
  Views/      Nearby, Plan, Route detail, Search, Saved
Tests/        decoding and polyline tests with recorded fixtures
feeds/        data converters contributed to Transitous
```

## Data and attribution

Routing and timetables: [Transitous and its data sources](https://transitous.org/sources/). Map data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright). Publit follows the [Transitous API policy](https://transitous.org/api/): open source, non-commercial, identifying User-Agent, visible attribution.

Publit is an independent project and does not use code, assets or data from other transit apps.

## Roadmap

- Live Activities and widgets for the next departure
- watchOS companion
- Line view with live vehicle positions
- More cities with real-time data, starting with Bari

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT, see [LICENSE](LICENSE).
