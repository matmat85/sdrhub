import ctypes
import fcntl
import json
import logging
import mmap
from pathlib import Path
import socket
import struct
import subprocess
import time

from PIL import Image, ImageDraw, ImageFont


class FixedInfo(ctypes.Structure):
    _fields_ = [
        ("id", ctypes.c_char * 16), ("smem_start", ctypes.c_ulong),
        ("smem_len", ctypes.c_uint32), ("type", ctypes.c_uint32),
        ("type_aux", ctypes.c_uint32), ("visual", ctypes.c_uint32),
        ("xpanstep", ctypes.c_uint16), ("ypanstep", ctypes.c_uint16),
        ("ywrapstep", ctypes.c_uint16), ("line_length", ctypes.c_uint32),
        ("mmio_start", ctypes.c_ulong), ("mmio_len", ctypes.c_uint32),
        ("accel", ctypes.c_uint32), ("capabilities", ctypes.c_uint16),
        ("reserved", ctypes.c_uint16 * 2),
    ]


def find_framebuffer():
    for entry in sorted(Path("/sys/class/graphics").glob("fb[0-9]*")):
        if "ili9486" in (entry / "name").read_text().lower():
            return Path("/dev") / entry.name
    raise RuntimeError("ILI9486 framebuffer not found; check loft-lcd overlay and kernel driver")


def rgb565(image):
    output = bytearray()
    for red, green, blue in image.convert("RGB").getdata():
        output.extend(struct.pack("=H", ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3)))
    return output


class Framebuffer:
    def __init__(self, path):
        self.file = path.open("r+b", buffering=0)
        try:
            fixed = bytearray(ctypes.sizeof(FixedInfo))
            fcntl.ioctl(self.file, 0x4602, fixed)
            info = FixedInfo.from_buffer_copy(fixed)
            variable = bytearray(160)
            fcntl.ioctl(self.file, 0x4600, variable)
            self.width, self.height, _, _, self.xoffset, self.yoffset, bpp = struct.unpack_from("=7I", variable)
            channels = struct.unpack_from("=12I", variable, 32)
            if bpp != 16 or channels != (11, 5, 0, 5, 6, 0, 0, 5, 0, 0, 0, 0):
                raise RuntimeError("LCD framebuffer is not supported RGB565")
            if (self.width, self.height) != (480, 320) or info.visual != 2:
                raise RuntimeError("Expected a landscape 480x320 true-color framebuffer")
            self.stride = info.line_length
            end = (self.yoffset + self.height - 1) * self.stride + (self.xoffset + self.width) * 2
            if self.stride < (self.xoffset + self.width) * 2 or end > info.smem_len:
                raise RuntimeError("Invalid framebuffer stride or memory size")
            self.memory = mmap.mmap(self.file.fileno(), info.smem_len)
        except Exception:
            self.file.close()
            raise

    def draw(self, image):
        pixels = rgb565(image)
        row_bytes = self.width * 2
        for row in range(self.height):
            offset = (row + self.yoffset) * self.stride + self.xoffset * 2
            self.memory[offset:offset + row_bytes] = pixels[row * row_bytes:(row + 1) * row_bytes]

    def close(self):
        self.memory.close()
        self.file.close()


def command(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=5)
    if result.returncode != 0:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.strip()}")
    return result.stdout


def status_lines():
    addresses = json.loads(command(["ip", "-j", "-4", "address", "show"]))
    links = json.loads(command(["ip", "-j", "link", "show"]))
    ips = [
        address["local"] for interface in addresses if interface["ifname"] != "lo"
        for address in interface.get("addr_info", []) if address.get("scope") == "global"
    ]
    wifi = next((link for link in links if link["ifname"] == "wlan0"), None)
    connected = bool(wifi and "LOWER_UP" in wifi.get("flags", []))
    state = command(["systemctl", "show", "--property=SystemState", "--value"]).strip()
    uptime = int(float(Path("/proc/uptime").read_text().split()[0]))
    lines = [
        f"Boot: {state}  Up: {uptime // 60}m",
        f"Wi-Fi: {'connected' if connected else 'disconnected'}",
        f"IP: {', '.join(ips) if ips else 'waiting for network'}",
        f"Setup: http://{ips[0]}:1099" if ips else "Setup: waiting for an IP",
    ]
    for label, service in (("Provision", "loft-firstboot"), ("Web", "adsb-setup"), ("RTL-TCP", "loft-rtl-tcp")):
        active = command(["systemctl", "show", service, "--property=ActiveState", "--value"]).strip()
        lines.append(f"{label}: {active}")
    if Path("/run/docker.sock").exists():
        states = command(["docker", "ps", "-a", "--format", "{{.Names}}: {{.Status}}"]).splitlines()
        adsb = next((state for state in states if state.startswith(("nanofeeder:", "ultrafeeder:"))), "not started")
    else:
        adsb = "Docker starting"
    lines.append(f"ADS-B: {adsb}")
    return lines


def render(lines):
    image = Image.new("RGB", (480, 320), "#101820")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
    draw.text((12, 8), f"LOFT SDR  {socket.gethostname()[:24]}", font=font, fill="#60d0ff")
    for index, line in enumerate(lines[:9]):
        while draw.textlength(line, font=font) > 456:
            line = line[:-4] + "..."
        draw.text((12, 46 + index * 29), line, font=font, fill="white")
    return image


def main():
    logging.basicConfig(level=logging.INFO)
    screen = Framebuffer(find_framebuffer())
    previous = None
    try:
        screen.draw(render(["Booted: starting status monitor", "Network: checking..."]))
        while True:
            try:
                lines = status_lines()
            except (OSError, ValueError, subprocess.SubprocessError, RuntimeError) as error:
                logging.exception("LCD status collection failed")
                lines = ["STATUS ERROR", str(error), "See journalctl -u loft-display"]
            if lines != previous:
                screen.draw(render(lines))
                previous = lines
            time.sleep(5)
    finally:
        screen.close()


if __name__ == "__main__":
    main()
