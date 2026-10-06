#!/usr/bin/env python3
"""AMTAB Bari: JSON GTFS-Realtime export -> standard GTFS-Realtime protobuf.

AMTAB publishes real-time data as a JSON rendering of GTFS-Realtime
(https://amtab.bari.it/it/openmobilitydata). Consumers such as Transitous/MOTIS
expect binary protobuf. This service fetches both AMTAB endpoints, converts them
and serves:

  /trip-updates.pb       GTFS-RT TripUpdates
  /vehicle-positions.pb  GTFS-RT VehiclePositions
  /trip-updates.txt      human-readable debug output
  /health                JSON status

IDs (trip_id, route_id, stop_id, stop_sequence) match AMTAB's static GTFS
(http://www.amtabservizio.it/gtfs/google_transit.zip) and are passed through unchanged.
"""
from __future__ import annotations

import datetime as dt
import json
import logging
import os
import threading
import time
import urllib.request
import zoneinfo
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from google.protobuf import text_format
from google.transit import gtfs_realtime_pb2 as rt

SOURCE = os.environ.get("AMTAB_BASE", "https://avl.amtab.it/WSExportGTFS_RT/api/gtfs")
USER_AGENT = os.environ.get("USER_AGENT", "Publit-AMTAB-GTFSRT/0.1 (+https://github.com/elija-7580/Publit-)")
CACHE_SECONDS = int(os.environ.get("CACHE_SECONDS", "20"))
TZ = zoneinfo.ZoneInfo("Europe/Rome")
# AMTAB reports speed in km/h (values up to ~80 for city buses); GTFS-RT expects m/s.
SPEED_DIVISOR = float(os.environ.get("SPEED_DIVISOR", "3.6"))

log = logging.getLogger("amtab-gtfsrt")


def fetch_json(path: str) -> dict:
    req = urllib.request.Request(f"{SOURCE}/{path}", headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def _header(msg: rt.FeedMessage, src: dict) -> None:
    h = src.get("Header") or {}
    msg.header.gtfs_realtime_version = "2.0"
    msg.header.incrementality = rt.FeedHeader.FULL_DATASET
    msg.header.timestamp = int(h.get("Timestamp") or time.time())


def _set_trip(dst: rt.TripDescriptor, trip: dict, start_date: str | None) -> None:
    if trip.get("TripId"):
        dst.trip_id = str(trip["TripId"])
    if trip.get("RouteId"):
        dst.route_id = str(trip["RouteId"])
    sd = trip.get("StartDate") or start_date
    if sd:
        dst.start_date = str(sd)
    sr = trip.get("schedule_relationship")
    if isinstance(sr, int):
        dst.schedule_relationship = sr


def _set_event(dst: rt.TripUpdate.StopTimeEvent, ev: dict | None) -> bool:
    if not ev:
        return False
    used = False
    if ev.get("Delay") is not None:
        dst.delay = int(ev["Delay"])
        used = True
    if ev.get("Time"):
        dst.time = int(ev["Time"])
        used = True
    return used


def start_dates_by_trip(vehicle_json: dict) -> dict[str, str]:
    out: dict[str, str] = {}
    for e in vehicle_json.get("Entities") or []:
        trip = ((e.get("Vehicle") or {}).get("Trip")) or {}
        if trip.get("TripId") and trip.get("StartDate"):
            out[str(trip["TripId"])] = str(trip["StartDate"])
    return out


def vehicles_by_trip(vehicle_json: dict) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for e in vehicle_json.get("Entities") or []:
        v = e.get("Vehicle") or {}
        tid = (v.get("Trip") or {}).get("TripId")
        if tid and v.get("Vehicle"):
            out[str(tid)] = v["Vehicle"]
    return out


def convert_trip_updates(tu_json: dict, vehicle_json: dict | None = None) -> rt.FeedMessage:
    vehicle_json = vehicle_json or {}
    dates = start_dates_by_trip(vehicle_json)
    vehicles = vehicles_by_trip(vehicle_json)
    msg = rt.FeedMessage()
    _header(msg, tu_json)
    today = dt.datetime.fromtimestamp(msg.header.timestamp, TZ).strftime("%Y%m%d")

    for e in tu_json.get("Entities") or []:
        t = e.get("TripUpdate")
        if not t or not (t.get("Trip") or {}).get("TripId"):
            continue
        ent = msg.entity.add()
        ent.id = str(e.get("Id") or t["Trip"]["TripId"])
        tu = ent.trip_update
        tid = str(t["Trip"]["TripId"])
        _set_trip(tu.trip, t["Trip"], dates.get(tid, today))
        veh = t.get("Vehicle") or vehicles.get(tid)
        if veh and veh.get("Id"):
            tu.vehicle.id = str(veh["Id"])
            if veh.get("Label"):
                tu.vehicle.label = str(veh["Label"])
        for u in t.get("StopTimeUpdates") or []:
            stu = tu.stop_time_update.add()
            if u.get("StopSequence") is not None:
                stu.stop_sequence = int(u["StopSequence"])
            if u.get("StopId"):
                stu.stop_id = str(u["StopId"])
            has_arr = _set_event(stu.arrival, u.get("Arrival"))
            has_dep = _set_event(stu.departure, u.get("Departure"))
            if not has_arr:
                stu.ClearField("arrival")
            if not has_dep:
                stu.ClearField("departure")
            sr = u.get("schedule_relationship")
            if isinstance(sr, int):
                stu.schedule_relationship = sr
        if t.get("Delay") is not None:
            tu.delay = int(t["Delay"])
        tu.timestamp = msg.header.timestamp
    return msg


def convert_vehicle_positions(vp_json: dict) -> rt.FeedMessage:
    msg = rt.FeedMessage()
    _header(msg, vp_json)
    today = dt.datetime.fromtimestamp(msg.header.timestamp, TZ).strftime("%Y%m%d")
    for e in vp_json.get("Entities") or []:
        v = e.get("Vehicle")
        if not v or e.get("IsDeleted"):
            continue
        pos = v.get("Position") or {}
        if pos.get("Latitude") is None or pos.get("Longitude") is None:
            continue
        ent = msg.entity.add()
        ent.id = str(e.get("Id") or (v.get("Vehicle") or {}).get("Id"))
        vp = ent.vehicle
        if v.get("Trip"):
            _set_trip(vp.trip, v["Trip"], today)
        if v.get("Vehicle"):
            if v["Vehicle"].get("Id"):
                vp.vehicle.id = str(v["Vehicle"]["Id"])
            if v["Vehicle"].get("Label"):
                vp.vehicle.label = str(v["Vehicle"]["Label"])
        vp.position.latitude = float(pos["Latitude"])
        vp.position.longitude = float(pos["Longitude"])
        if pos.get("Speed") is not None:
            vp.position.speed = float(pos["Speed"]) / SPEED_DIVISOR
        if pos.get("Bearing") is not None:
            vp.position.bearing = float(pos["Bearing"])
        if v.get("CurrentStopSequence") is not None:
            vp.current_stop_sequence = int(v["CurrentStopSequence"])
        if v.get("StopId"):
            vp.stop_id = str(v["StopId"])
        if isinstance(v.get("CurrentStatus"), int):
            vp.current_status = v["CurrentStatus"]
        if isinstance(v.get("congestion_level"), int):
            vp.congestion_level = v["congestion_level"]
        vp.timestamp = int(v.get("Timestamp") or msg.header.timestamp)
    return msg


class Cache:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._at = 0.0
        self.trip_updates: rt.FeedMessage | None = None
        self.vehicle_positions: rt.FeedMessage | None = None
        self.error: str | None = None

    def get(self) -> "Cache":
        with self._lock:
            if time.time() - self._at < CACHE_SECONDS and self.trip_updates is not None:
                return self
            try:
                vp_json = fetch_json("VechiclePosition")  # sic: AMTAB's endpoint spelling
                tu_json = fetch_json("TripUpdates")
                self.vehicle_positions = convert_vehicle_positions(vp_json)
                self.trip_updates = convert_trip_updates(tu_json, vp_json)
                self.error = None
                self._at = time.time()
            except Exception as exc:  # keep serving the last good snapshot
                self.error = f"{type(exc).__name__}: {exc}"
                log.warning("refresh failed: %s", self.error)
            return self


CACHE = Cache()


class Handler(BaseHTTPRequestHandler):
    server_version = "amtab-gtfsrt/0.1"

    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", f"public, max-age={CACHE_SECONDS}")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?")[0].rstrip("/")
        c = CACHE.get()
        feeds = {"/trip-updates": c.trip_updates, "/vehicle-positions": c.vehicle_positions}
        if path == "/health":
            body = {
                "ok": c.trip_updates is not None,
                "error": c.error,
                "trip_updates": len(c.trip_updates.entity) if c.trip_updates else 0,
                "vehicles": len(c.vehicle_positions.entity) if c.vehicle_positions else 0,
                "feed_timestamp": c.trip_updates.header.timestamp if c.trip_updates else None,
            }
            return self._send(200 if body["ok"] else 503, json.dumps(body).encode(), "application/json")
        for base, feed in feeds.items():
            if path in (base + ".pb", base + ".txt"):
                if feed is None:
                    return self._send(503, b"upstream unavailable", "text/plain")
                if path.endswith(".pb"):
                    return self._send(200, feed.SerializeToString(), "application/x-protobuf")
                return self._send(200, text_format.MessageToString(feed).encode(), "text/plain; charset=utf-8")
        self._send(404, b"not found", "text/plain")

    def log_message(self, fmt: str, *args) -> None:
        log.info("%s %s", self.address_string(), fmt % args)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    port = int(os.environ.get("PORT", "8080"))
    log.info("listening on :%d, source %s", port, SOURCE)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
