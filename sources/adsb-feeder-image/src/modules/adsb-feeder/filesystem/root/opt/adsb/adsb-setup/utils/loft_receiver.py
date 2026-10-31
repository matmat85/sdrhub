import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import subprocess

from flask import abort, flash, redirect, render_template, request, session, url_for

CONFIG = Path("/etc/loft-receiver/radio.json")
PRIVATE_NETWORKS = tuple(ipaddress.IPv4Network(network) for network in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))


def validate_config(value):
    if not isinstance(value, dict):
        raise ValueError("Receiver settings must be an object")
    serial = value.get("serial", "")
    if not isinstance(serial, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", serial):
        raise ValueError("Use the dongle's unique USB serial")
    result = {"serial": serial}
    for field in ("listen", "hub_client", "adsb_client"):
        raw_address = value.get(field, "")
        if not isinstance(raw_address, str):
            raise ValueError(f"{field} must be a private LAN IPv4 address")
        address = ipaddress.IPv4Address(raw_address)
        if not any(address in network for network in PRIVATE_NETWORKS):
            raise ValueError(f"{field} must be a private LAN IPv4 address")
        result[field] = str(address)
    return result


def read_config():
    return json.loads(CONFIG.read_text()) if CONFIG.exists() else None


def register_receiver(app, auth, devices):
    @app.context_processor
    def receiver_available():
        return {"loft_receiver_available": CONFIG.parent.is_dir()}

    @app.route("/loft_receiver", methods=["GET", "POST"])
    def loft_receiver():
        if not CONFIG.parent.is_dir():
            abort(404)
        if not auth.is_enabled():
            abort(403, description="Enable feeder web authentication before configuring the receiver")
        if not auth.is_authenticated():
            return redirect(url_for("login", next=request.url))
        if "loft_csrf" not in session:
            session["loft_csrf"] = secrets.token_hex(32)
        settings = read_config() or {
            "serial": "77465553", "listen": "", "hub_client": "", "adsb_client": ""
        }
        if request.method == "POST":
            token = request.form.get("csrf", "")
            if not secrets.compare_digest(token, session["loft_csrf"]):
                abort(403, description="Invalid receiver form token")
            try:
                settings = validate_config(dict(request.form))
            except (ValueError, ipaddress.AddressValueError) as error:
                flash(str(error))
                return render_template("loft_receiver.html", settings=settings), 400
            devices.ensure_populated()
            matches = [sdr for sdr in devices.sdrs if sdr._serial == settings["serial"]]
            if len(matches) != 1 or matches[0]._type != "rtlsdr" or matches[0].purpose != "":
                flash("The stream requires exactly one connected, unassigned RTL-SDR. Free its assignment in SDR Setup first.")
                return render_template("loft_receiver.html", settings=settings), 409
            try:
                subprocess.run(["systemctl", "stop", "loft-rtl-tcp.service"], check=True, timeout=30)
                temporary = CONFIG.with_suffix(".tmp")
                temporary.write_text(json.dumps(settings) + "\n")
                os.chmod(temporary, 0o644)
                temporary.replace(CONFIG)
                subprocess.run(["systemctl", "restart", "loft-firewall.service"], check=True, timeout=30)
                subprocess.run(["systemctl", "start", "loft-rtl-tcp.service"], check=True, timeout=30)
            except (OSError, subprocess.SubprocessError):
                app.logger.exception("Receiver configuration could not be applied")
                flash("Receiver configuration was not fully applied. Previous settings may still be active; inspect journalctl -u loft-rtl-tcp -u loft-firewall and retry.")
                return render_template("loft_receiver.html", settings=settings), 503
            flash("Receiver configured. Check the service journal for USB/tuner errors; settings are retained across reboot.")
            return redirect(url_for("loft_receiver"))
        return render_template("loft_receiver.html", settings=settings)
