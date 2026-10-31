import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import os
import sys
import unittest
from unittest.mock import patch

from flask import Flask, session
from jinja2 import DictLoader

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "sources/adsb-feeder-image/src/modules/adsb-feeder/filesystem/root/opt/adsb/adsb-setup/utils/loft_receiver.py"
spec = importlib.util.spec_from_file_location("loft_receiver", MODULE)
receiver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receiver)
VALID = {"serial": "77465553", "listen": "192.168.1.50",
         "hub_client": "192.168.1.52", "adsb_client": "192.168.1.51"}
sys.path.insert(0, str(MODULE.parent.parent))
firstboot_spec = importlib.util.spec_from_file_location("loft_firstboot", ROOT / "pi/firstboot.py")
firstboot = importlib.util.module_from_spec(firstboot_spec)
firstboot_spec.loader.exec_module(firstboot)


class ReceiverTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config = Path(self.temp.name) / "radio.json"
        self.addCleanup(patch.stopall)
        patch.object(receiver, "CONFIG", self.config).start()
        self.app = Flask(__name__)
        self.app.secret_key = "test-only-session"
        self.app.jinja_loader = DictLoader({"loft_receiver.html": "{{ settings }}", "base.html": ""})
        self.auth = SimpleNamespace(is_enabled=lambda: True, is_authenticated=lambda: session.get("authenticated", False))
        self.devices = SimpleNamespace(ensure_populated=lambda: None, sdrs=[
            SimpleNamespace(_serial="77465553", _type="rtlsdr", purpose="")
        ])
        self.app.add_url_rule("/login", "login", lambda: "login")
        receiver.register_receiver(self.app, self.auth, self.devices)
        self.client = self.app.test_client()

    def login(self):
        with self.client.session_transaction() as state:
            state["authenticated"] = True
            state["loft_csrf"] = "test-token"

    def test_validate_addresses_and_serial(self):
        self.assertEqual(receiver.validate_config(VALID), VALID)
        for key, value in [("serial", "x; touch /tmp/x"), ("listen", "0.0.0.0"),
                           ("listen", "127.0.0.1"), ("hub_client", "8.8.8.8"),
                           ("adsb_client", "224.0.0.1"), ("listen", 123)]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                receiver.validate_config({**VALID, key: value})

    def test_authentication_and_csrf(self):
        self.assertEqual(self.client.get("/loft_receiver").status_code, 302)
        self.login()
        self.assertEqual(self.client.post("/loft_receiver", data=VALID).status_code, 403)
        self.assertFalse(self.config.exists())

    def test_conflicting_and_duplicate_dongles(self):
        self.login()
        self.devices.sdrs[0].purpose = "vdl2"
        self.assertEqual(self.client.post("/loft_receiver", data={**VALID, "csrf": "test-token"}).status_code, 409)
        self.devices.sdrs[0].purpose = ""
        self.devices.sdrs *= 2
        self.assertEqual(self.client.post("/loft_receiver", data={**VALID, "csrf": "test-token"}).status_code, 409)
        self.assertFalse(self.config.exists())

    def test_apply_and_explicit_failure(self):
        self.login()
        with patch.object(receiver.subprocess, "run") as command:
            self.assertEqual(self.client.post("/loft_receiver", data={**VALID, "csrf": "test-token"}).status_code, 302)
            self.assertEqual(json.loads(self.config.read_text()), VALID)
            self.assertEqual(command.call_count, 3)
        with patch.object(receiver.subprocess, "run", side_effect=OSError("test failure")):
            self.assertEqual(self.client.post("/loft_receiver", data={**VALID, "csrf": "test-token"}).status_code, 503)


class FirstBootTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(patch.stopall)
        old_mask = os.umask(0o022)
        self.addCleanup(os.umask, old_mask)
        for name in ("PROVISIONED", "BOOT_CONFIG", "CREDENTIALS", "ENV_FILE", "RADIO_CONFIG"):
            patch.object(firstboot, name, Path(self.temp.name) / name).start()
        firstboot.ENV_FILE.write_text("FEEDER_SERIAL_1090=00000001\n")

    def test_unique_credentials_and_idempotence(self):
        firstboot.main()
        original = firstboot.CREDENTIALS.read_text()
        self.assertIn("Feeder web login: admin", original)
        self.assertIn("_ADSBIM_WEB_AUTH_ENABLED=True", firstboot.ENV_FILE.read_text())
        self.assertEqual(firstboot.CREDENTIALS.stat().st_mode & 0o777, 0o600)
        self.assertEqual(firstboot.ENV_FILE.stat().st_mode & 0o777, 0o600)
        firstboot.main()
        self.assertEqual(firstboot.CREDENTIALS.read_text(), original)

    def test_boot_config_consumed_only_after_validation(self):
        firstboot.BOOT_CONFIG.write_text(json.dumps({"web_password": "short", "receiver": VALID}))
        with self.assertRaises(ValueError):
            firstboot.main()
        self.assertTrue(firstboot.BOOT_CONFIG.exists())
        self.assertFalse(firstboot.PROVISIONED.exists())
        firstboot.BOOT_CONFIG.write_text(json.dumps({"web_password": "test-only-password", "receiver": VALID}))
        firstboot.main()
        self.assertFalse(firstboot.BOOT_CONFIG.exists())
        self.assertEqual(json.loads(firstboot.RADIO_CONFIG.read_text()), VALID)
        self.assertTrue(firstboot.PROVISIONED.exists())


if __name__ == "__main__":
    unittest.main()
