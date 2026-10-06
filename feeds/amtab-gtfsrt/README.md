# AMTAB Bari → GTFS-Realtime (protobuf)

Converts the real-time data of AMTAB (Bari city buses) into standard GTFS-Realtime so that Transitous, and with it Publit and every other MOTIS-based app, can show live delays and vehicle positions in Bari.

## Why

AMTAB publishes real-time data openly ([OpenMobilityData](https://amtab.bari.it/it/openmobilitydata), [technical spec](https://amtab.bari.it/images/Servizio_Export_GTFS.pdf)), but as a JSON rendering of GTFS-RT. Transitous only reads binary protobuf, so Bari currently shows timetable times only.

Validated on 2026-10-06 against AMTAB's static GTFS (the feed Transitous already imports as `Puglia-Bari`): 100 % of `trip_id`, `route_id`, `stop_id` and `stop_sequence` values match; reported times equal timetable + delay within ±1 min (delay is rounded to whole minutes upstream).

## Endpoints

| Path | Content |
| --- | --- |
| `/trip-updates.pb` | GTFS-RT TripUpdates (protobuf) |
| `/vehicle-positions.pb` | GTFS-RT VehiclePositions (protobuf) |
| `/trip-updates.txt`, `/vehicle-positions.txt` | Same, human-readable |
| `/health` | JSON status, `503` if no snapshot yet |

Upstream is polled at most every `CACHE_SECONDS` (default 20 s); the last good snapshot is served if AMTAB is unreachable.

Conversions:
- `start_date` is filled from the vehicle feed (or today in Europe/Rome), because AMTAB omits it in TripUpdates.
- Vehicle speed is converted from km/h to m/s (`SPEED_DIVISOR`, default 3.6). Assumption based on observed values; adjust if AMTAB documents otherwise.

## Run

```bash
pip install -r requirements.txt
python amtab_gtfsrt.py            # :8080
python -m unittest discover -s tests -v
```

Docker on a server behind Caddy (shared external network `caddy`):

```bash
docker compose up -d --build
```

Caddyfile:

```
rt.example.org {
    reverse_proxy amtab-gtfsrt:8080
}
```

## Transitous entry

See `transitous-it.json.patch`. The real-time source uses the same `name` as the static feed (`Puglia-Bari`), like the existing Messina entry.

## License

Code: MIT (repository license). Data: © AMTAB S.p.A.; license of the real-time export to be confirmed with AMTAB (static GTFS is listed as CC-BY-4.0 in Transitous).
