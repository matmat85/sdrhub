import json
import os
import tempfile
import unittest
import xmlrpc.client
from pathlib import Path
from unittest.mock import patch

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "monitor.settings")
import django
django.setup()
from sdr import radio


class Control:
    def __init__(self):
        self.states = {"sdr_scanner": "RUNNING", "radio_player": "STOPPED"}
        self.events = []
        self.fail = False

    def getProcessInfo(self, name):
        return {"statename": self.states[name]}

    def stopProcess(self, name, wait):
        self.events.append(("stop", name))
        self.states[name] = "STOPPED"

    def startProcess(self, name, wait):
        self.events.append(("start", name))
        if self.fail and name == "radio_player":
            raise xmlrpc.client.Fault(50, "spawn failed")
        self.states[name] = "RUNNING"


class RadioTests(unittest.TestCase):
    def test_frequency_limits_and_invalid_values(self):
        for frequency in ("87.5", "108", "100.123"):
            self.assertEqual(radio.validate_selection("fm", frequency, "")["frequency"], int(float(frequency) * 1000000))
        for frequency in ("NaN", "Infinity", "87.4", "108.1", "bad", ""):
            with self.assertRaises(ValueError):
                radio.validate_selection("fm", frequency, "")
        self.assertEqual(radio.validate_selection("dab", "", "12B")["channel"], "12B")
        with self.assertRaises(ValueError):
            radio.validate_selection("dab", "", "99Z")

    def test_exclusive_mode_switch_and_failure_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state.json"
            config = root / "config.json"
            config.write_text(json.dumps({"devices": [{
                "serial": "77465553", "device_args": {"driver": "rtltcp", "rtltcp": "loft-pi:1234"}
            }]}))
            control = Control()
            with patch.object(radio, "STATE", state), patch.object(radio, "CONFIG", config):
                radio.change_mode(radio.validate_selection("fm", "100", ""), control)
                self.assertEqual(control.events, [("stop", "sdr_scanner"), ("start", "radio_player")])
                self.assertEqual(json.loads(state.read_text())["device_args"]["rtltcp"], "loft-pi:1234")
                radio.change_mode({"mode": "scan"}, control)
                self.assertEqual(control.states, {"sdr_scanner": "RUNNING", "radio_player": "STOPPED"})
                self.assertFalse(state.exists())
                control.fail = True
                with self.assertRaises(RuntimeError):
                    radio.change_mode(radio.validate_selection("dab", "", "12B"), control)
                self.assertEqual(control.states["sdr_scanner"], "RUNNING")
                self.assertFalse(state.exists())

    def test_no_accidental_use_of_adsb_dongle(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.json"
            config.write_text(json.dumps({"devices": [{"serial": "00000001", "driver": "rtlsdr"}]}))
            control = Control()
            with patch.object(radio, "CONFIG", config):
                with self.assertRaises(ValueError):
                    radio.change_mode({"mode": "fm", "frequency": 100000000}, control)
            self.assertEqual(control.events, [])


if __name__ == "__main__":
    unittest.main()
