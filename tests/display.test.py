import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import struct
import tempfile

from PIL import Image

spec = importlib.util.spec_from_file_location("display", Path(__file__).resolve().parents[1] / "pi/display.py")
display = importlib.util.module_from_spec(spec)
spec.loader.exec_module(display)


class DisplayTests(unittest.TestCase):
    def test_exact_rgb565_bytes(self):
        image = Image.new("RGB", (3, 1))
        image.putdata([(255, 0, 0), (0, 255, 0), (0, 0, 255)])
        self.assertEqual(display.rgb565(image), struct.pack("=3H", 0xf800, 0x07e0, 0x001f))

    def test_framebuffer_stride_offsets_and_format_guard(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "framebuffer"
            size = 1024 * 321
            path.write_bytes(bytes(size))

            def ioctl(file, request, data):
                if request == 0x4602:
                    fixed = display.FixedInfo()
                    fixed.smem_len = size
                    fixed.visual = 2
                    fixed.line_length = 1024
                    data[:] = bytes(fixed)
                else:
                    struct.pack_into("=7I", data, 0, 480, 320, 512, 321, 1, 1, 16)
                    struct.pack_into("=12I", data, 32, 11, 5, 0, 5, 6, 0, 0, 5, 0, 0, 0, 0)

            with patch.object(display.fcntl, "ioctl", side_effect=ioctl):
                screen = display.Framebuffer(path)
                try:
                    screen.draw(Image.new("RGB", (480, 320), "red"))
                finally:
                    screen.close()
            data = path.read_bytes()
            self.assertEqual(data[:1026], bytes(1026))
            self.assertEqual(data[1026:1028], struct.pack("=H", 0xf800))
            self.assertEqual(data[1986:2048], bytes(62))
            with patch.object(display.fcntl, "ioctl"):
                with self.assertRaisesRegex(RuntimeError, "RGB565"):
                    display.Framebuffer(path)

    def test_render_size_and_long_lines(self):
        image = display.render(["Boot: running", "IP: " + "192.168.1.50, " * 12])
        self.assertEqual(image.size, (480, 320))
        self.assertEqual(len(display.rgb565(image)), 480 * 320 * 2)

    def test_connected_and_disconnected_status(self):
        def command(args):
            if args[0] == "ip":
                if "address" in args:
                    return '[{"ifname":"wlan0","addr_info":[{"scope":"global","local":"192.168.1.50"}]}]'
                return '[{"ifname":"wlan0","flags":["UP","LOWER_UP"]}]'
            if args[0] == "docker":
                return "nanofeeder: Up 5 minutes\n"
            if "--property=SystemState" in args:
                return "running\n"
            return "active\n"
        with patch.object(display, "command", side_effect=command), patch.object(display.Path, "exists", return_value=True):
            lines = display.status_lines()
        self.assertIn("Wi-Fi: connected", lines)
        self.assertIn("Setup: http://192.168.1.50:1099", lines)
        self.assertIn("ADS-B: nanofeeder: Up 5 minutes", lines)
        with patch.object(display, "command", side_effect=lambda args: "[]" if args[0] == "ip" else "starting"), patch.object(display.Path, "exists", return_value=False):
            lines = display.status_lines()
        self.assertIn("Wi-Fi: disconnected", lines)
        self.assertIn("IP: waiting for network", lines)
        self.assertIn("ADS-B: Docker starting", lines)


if __name__ == "__main__":
    unittest.main()
