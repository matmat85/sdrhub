import os
import subprocess
import tempfile
import time
import xmlrpc.client
import numpy as np

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "monitor.settings")
import django
django.setup()
import requests
from django.contrib.auth import get_user_model
from django.test import Client

control = xmlrpc.client.ServerProxy("http://127.0.0.1:8093/RPC2").supervisor
client = Client()
client.force_login(get_user_model().objects.get(username="admin"))
cookies = {name: cookie.value for name, cookie in client.cookies.items()}

anonymous = requests.get("http://127.0.0.1/sdr/radio/fm.mp3", allow_redirects=False)
assert anonymous.status_code == 302, anonymous.status_code
assert requests.get("http://127.0.0.1/_radio/fm.mp3").status_code == 404
csrf_client = Client(enforce_csrf_checks=True)
csrf_client.force_login(get_user_model().objects.get(username="admin"))
assert csrf_client.post("/sdr/radio/", {"mode": "fm", "frequency": "100"}).status_code == 403

response = client.post("/sdr/radio/", {"mode": "fm", "frequency": "100", "channel": "12B"})
assert response.status_code == 302
assert control.getProcessInfo("sdr_scanner")["statename"] == "STOPPED"
assert control.getProcessInfo("radio_player")["statename"] == "RUNNING"
with requests.get("http://127.0.0.1/sdr/radio/fm.mp3", cookies=cookies, stream=True, timeout=20) as audio:
    assert audio.status_code == 200, (audio.status_code, audio.text)
    assert audio.headers["Content-Type"] == "audio/mpeg"
    second = requests.get("http://127.0.0.1/sdr/radio/fm.mp3", cookies=cookies, timeout=5)
    assert second.status_code == 409, second.status_code
    data = bytearray()
    for chunk in audio.iter_content(8192):
        data.extend(chunk)
        if len(data) >= 32768:
            break
    assert len(data) >= 32768, "FM stream ended before producing MP3 audio"
    with tempfile.NamedTemporaryFile(suffix=".mp3") as recording:
        recording.write(data)
        recording.flush()
        subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name", recording.name], check=True)
        decoded = subprocess.run(["ffmpeg", "-v", "error", "-i", recording.name, "-f", "f32le",
                                  "-ar", "32000", "-ac", "1", "pipe:1"], check=True, capture_output=True)
        samples = np.frombuffer(decoded.stdout, dtype=np.float32)[3200:]
        assert len(samples) > 32000, "Less than one second of decoded FM audio"
        assert np.sqrt(np.mean(samples ** 2)) > 0.01, "FM output is silent"
        spectrum = np.abs(np.fft.rfft(samples * np.hanning(len(samples))))
        peak = np.fft.rfftfreq(len(samples), 1 / 32000)[np.argmax(spectrum)]
        assert abs(peak - 1000) < 10, f"Expected 1 kHz FM test tone, got {peak}"
print("PASS: authenticated FM MP3 contains the transmitted 1 kHz tone; scanner stopped and internal path inaccessible")

client.post("/sdr/radio/", {"mode": "dab", "channel": "12B", "frequency": ""})
assert control.getProcessInfo("radio_player")["statename"] == "RUNNING"
assert control.getProcessInfo("sdr_scanner")["statename"] == "STOPPED"
for _ in range(20):
    try:
        mux = requests.get("http://127.0.0.1:8092/mux.json", timeout=3)
        mux.raise_for_status()
        assert "services" in mux.json()
        break
    except requests.RequestException:
        time.sleep(1)
else:
    raise AssertionError("DAB web server failed to expose multiplex status")
response = client.get("/sdr/radio/")
assert response.status_code == 200
assert b"DAB services on 12B" in response.content
print("PASS: real DAB decoder starts and exposes multiplex/service API with scanner stopped")

client.post("/sdr/radio/", {"mode": "scan"})
assert control.getProcessInfo("sdr_scanner")["statename"] == "RUNNING"
assert control.getProcessInfo("radio_player")["statename"] == "STOPPED"
assert client.get("/sdr/radio/fm.mp3").status_code in (409, 503)
print("PASS: scanning resumes and radio stream cannot retune the SDR after mode exit")
