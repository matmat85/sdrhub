import fcntl
import json
import logging
import os
import re
import xmlrpc.client
from contextlib import contextmanager
from decimal import Decimal, InvalidOperation
from pathlib import Path

import requests
from django.contrib import messages
from django.contrib.admin.views.decorators import staff_member_required
from django.http import HttpResponse
from django.shortcuts import redirect, render
from django.views.decorators.http import require_GET

LOG = logging.getLogger("Radio")
STATE = Path("/var/run/sdr/radio.json")
CONFIG = Path("/app/data/config.json")
CHANNELS = [f"{number}{letter}" for number in range(5, 14) for letter in "ABCD"] + ["10N", "11N", "12N"]


def validate_selection(mode, frequency, channel):
    if mode == "scan":
        return {"mode": mode}
    if mode == "fm":
        try:
            mhz = Decimal(frequency)
        except InvalidOperation as error:
            raise ValueError("Enter a valid FM frequency in MHz") from error
        if not mhz.is_finite() or not Decimal("87.5") <= mhz <= Decimal("108"):
            raise ValueError("FM frequency must be between 87.5 and 108 MHz")
        return {"mode": mode, "frequency": int(mhz * 1000000)}
    if mode == "dab" and channel in CHANNELS:
        return {"mode": mode, "channel": channel}
    raise ValueError("Choose FM, DAB or scanning, and a valid DAB channel")


def supervisor():
    return xmlrpc.client.ServerProxy("http://127.0.0.1:8093/RPC2").supervisor


@contextmanager
def locked():
    with open("/var/run/sdr/radio.lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def stop_program(control, name):
    if control.getProcessInfo(name)["statename"] in ("RUNNING", "STARTING"):
        control.stopProcess(name, True)


def change_mode(selection, control=None):
    control = control or supervisor()
    with locked():
        if selection["mode"] != "scan":
            config = json.loads(CONFIG.read_text())
            serial = os.getenv("SDR_RADIO_SERIAL", "77465553")
            devices = [device for device in config["devices"] if device["serial"] == serial]
            if len(devices) != 1 or devices[0].get("device_args", {}).get("driver") != "rtltcp":
                raise ValueError("Radio mode requires one explicit RTL-TCP device with serial " + serial)
            selection = dict(selection, device_args=devices[0]["device_args"])
        stop_program(control, "radio_player")
        stop_program(control, "sdr_scanner")
        try:
            if selection["mode"] == "scan":
                STATE.unlink(missing_ok=True)
                control.startProcess("sdr_scanner", True)
            else:
                temporary = STATE.with_suffix(".tmp")
                temporary.write_text(json.dumps(selection))
                temporary.replace(STATE)
                control.startProcess("radio_player", True)
        except (OSError, xmlrpc.client.Error) as error:
            LOG.exception("Radio mode failed; attempting to restore scanning")
            STATE.unlink(missing_ok=True)
            try:
                if control.getProcessInfo("sdr_scanner")["statename"] != "RUNNING":
                    control.startProcess("sdr_scanner", True)
            except xmlrpc.client.Error:
                LOG.exception("Could not restore scanning")
            raise RuntimeError("Radio could not start. Check radio_player.log and scanner status.") from error


def radio_state():
    state = json.loads(STATE.read_text()) if STATE.exists() else {"mode": "scan"}
    name = "sdr_scanner" if state["mode"] == "scan" else "radio_player"
    state["running"] = supervisor().getProcessInfo(name)["statename"] == "RUNNING"
    return state


@staff_member_required
def radio(request):
    if request.method == "POST":
        try:
            selection = validate_selection(request.POST.get("mode"), request.POST.get("frequency", ""), request.POST.get("channel"))
            change_mode(selection)
            messages.success(request, "Radio mode changed. Scanning is paused while listening." if selection["mode"] != "scan" else "Scanning resumed.")
        except (ValueError, OSError, RuntimeError, xmlrpc.client.Error) as error:
            LOG.exception("Cannot change radio mode")
            messages.error(request, str(error))
        return redirect("sdr_radio")
    state = {"mode": "scan", "running": False}
    stations = []
    try:
        state = radio_state()
        if not state["running"]:
            messages.error(request, "Receiver is not running. Check radio_player.log or resume scanning.")
        elif state["mode"] == "dab":
            response = requests.get("http://127.0.0.1:8092/mux.json", timeout=3)
            response.raise_for_status()
            for service in response.json()["services"]:
                url = service.get("url_mp3")
                if url and re.fullmatch(r"/mp3/[0-9a-fA-F]{4,8}", url):
                    stations.append({"sid": url.rsplit("/", 1)[1], "label": service["label"]["label"]})
    except (OSError, ValueError, KeyError, requests.RequestException, xmlrpc.client.Error) as error:
        LOG.exception("Cannot read radio status or DAB services")
        messages.error(request, "Radio status unavailable: " + str(error))
    frequency = str(Decimal(state.get("frequency", 100000000)) / 1000000)
    return render(request, "radio.html", {"state": state, "stations": stations, "channels": CHANNELS, "frequency": frequency})


@staff_member_required
@require_GET
def stream(request, service=""):
    try:
        state = radio_state()
        if not state["running"]:
            LOG.warning("Stream requested while radio receiver is stopped")
            return HttpResponse("Radio receiver is not running; check radio_player.log", status=503)
        if not service and state["mode"] == "fm":
            path = "fm.mp3"
        elif state["mode"] == "dab" and re.fullmatch(r"[0-9a-fA-F]{4,8}", service):
            path = "mp3/" + service
        else:
            LOG.warning("Stream requested for a different radio mode")
            return HttpResponse("Select the matching radio mode before playing", status=409)
        response = HttpResponse(content_type="audio/mpeg")
        response["X-Accel-Redirect"] = "/_radio/" + path
        response["Cache-Control"] = "no-store"
        return response
    except (OSError, ValueError, xmlrpc.client.Error):
        LOG.exception("Radio stream unavailable")
        return HttpResponse("Radio stream unavailable; check server logs", status=503)
