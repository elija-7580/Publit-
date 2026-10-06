import json
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import amtab_gtfsrt as m  # noqa: E402

FIX = pathlib.Path(__file__).parent / "fixtures"


class ConvertTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tu = json.loads((FIX / "trip_updates.json").read_text())
        cls.vp = json.loads((FIX / "vehicle_positions.json").read_text())

    def test_trip_updates_roundtrip(self):
        msg = m.convert_trip_updates(self.tu, self.vp)
        self.assertEqual(len(msg.entity), len(self.tu["Entities"]))
        parsed = m.rt.FeedMessage.FromString(msg.SerializeToString())
        e = parsed.entity[0].trip_update
        src = self.tu["Entities"][0]["TripUpdate"]
        self.assertEqual(e.trip.trip_id, src["Trip"]["TripId"])
        self.assertEqual(e.stop_time_update[0].stop_id, src["StopTimeUpdates"][0]["StopId"])
        self.assertEqual(e.stop_time_update[0].stop_sequence, src["StopTimeUpdates"][0]["StopSequence"])
        self.assertRegex(e.trip.start_date, r"^\d{8}$")

    def test_vehicle_positions(self):
        msg = m.convert_vehicle_positions(self.vp)
        self.assertGreater(len(msg.entity), 0)
        v = msg.entity[0].vehicle
        self.assertTrue(40.9 < v.position.latitude < 41.3)
        self.assertLess(v.position.speed, 40)  # m/s

    def test_missing_time_keeps_delay(self):
        src = {"Header": {"Timestamp": 1791320028}, "Entities": [{"Id": "x", "TripUpdate": {
            "Trip": {"TripId": "1", "RouteId": "01"},
            "StopTimeUpdates": [{"StopSequence": 3, "StopId": "s", "Arrival": {"Delay": 60}, "Departure": None}]}}]}
        msg = m.convert_trip_updates(src)
        stu = msg.entity[0].trip_update.stop_time_update[0]
        self.assertEqual(stu.arrival.delay, 60)
        self.assertFalse(stu.HasField("departure"))


if __name__ == "__main__":
    unittest.main()
