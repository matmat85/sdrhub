import hashlib
import json
from pathlib import Path
import sys
from datetime import date
import lzma


def main():
    tag = sys.argv[1]
    if not tag.startswith("v") or "/" in tag:
        raise ValueError("Expected a version tag")
    image = Path("dist/loft-pi.img.xz")
    size = 0
    digest = hashlib.sha256()
    with lzma.open(image) as file:
        while block := file.read(1024 * 1024):
            digest.update(block)
            size += len(block)
    item = {
        "name": f"Loft SDR receiver {tag}",
        "description": "Pi Zero 2 W: ADS-B Beast and second-radio RTL-TCP receiver",
        "url": f"https://github.com/matmat85/sdrhub/releases/download/{tag}/{image.name}",
        "website": "https://github.com/matmat85/sdrhub",
        "extract_size": size,
        "extract_sha256": digest.hexdigest(),
        "image_download_size": image.stat().st_size,
        "release_date": date.today().isoformat(),
        "init_format": "cloudinit-rpi",
        "devices": ["pi3-64bit", "pi4-64bit", "pi5-64bit"],
    }
    Path("dist/pi-imager.json").write_text(json.dumps({"os_list": [item]}, indent=2) + "\n")


if __name__ == "__main__":
    main()
