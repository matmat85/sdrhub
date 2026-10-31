import json
import logging
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

LOG = logging.getLogger("radio")
LISTENER = Lock()


class FMHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/fm.mp3":
            self.send_error(404)
            return
        if not LISTENER.acquire(blocking=False):
            LOG.warning("Rejecting a second concurrent FM listener")
            self.send_error(409, "Another FM listener is active")
            return
        try:
            self.stream_audio()
        finally:
            LISTENER.release()

    def stream_audio(self):
        with subprocess.Popen([sys.executable, "/usr/local/lib/loft-radio/fm.py"], stdout=subprocess.PIPE) as decoder:
            with subprocess.Popen(
                ["ffmpeg", "-nostdin", "-loglevel", "error", "-f", "f32le", "-ar", "32000", "-ac", "1",
                 "-i", "pipe:0", "-c:a", "libmp3lame", "-b:a", "96k", "-f", "mp3", "pipe:1"],
                stdin=decoder.stdout, stdout=subprocess.PIPE,
            ) as encoder:
                decoder.stdout.close()
                try:
                    first = encoder.stdout.read1(4096)
                    if not first:
                        LOG.error("FM decoder produced no audio; check radio_player.log")
                        self.send_error(502, "FM decoder produced no audio")
                        return
                    self.send_response(200)
                    self.send_header("Content-Type", "audio/mpeg")
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Connection", "close")
                    self.end_headers()
                    self.wfile.write(first)
                    while data := encoder.stdout.read1(4096):
                        self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    LOG.info("FM listener disconnected")
                finally:
                    encoder.terminate()
                    decoder.terminate()
                    for process in (encoder, decoder):
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            LOG.error("Radio subprocess did not stop; killing PID %s", process.pid)
                            process.kill()
                            process.wait()


def main():
    logging.basicConfig(level=logging.INFO)
    settings = json.loads(Path("/var/run/sdr/radio.json").read_text())
    if settings["mode"] == "dab":
        import os
        os.execvp("welle-cli", ["welle-cli", "-c", settings["channel"], "-F",
                              "rtl_tcp," + settings["device_args"]["rtltcp"], "-g", "-1", "-w", "8092"])
    elif settings["mode"] == "fm":
        ThreadingHTTPServer(("127.0.0.1", 8092), FMHandler).serve_forever()
    else:
        raise ValueError("Unsupported radio mode")


if __name__ == "__main__":
    main()
