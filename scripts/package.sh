#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ -d "$ROOT/pi" ]] || { echo "Pi image packaging is not implemented yet; refusing to create an incomplete release" >&2; exit 1; }
for project in sdr-hub sdr-monitor rtl-sdr-scanner-cpp adsb-feeder-image; do
    [[ -d "$ROOT/sources/$project" ]] || { echo "Run scripts/export-sources.sh first" >&2; exit 1; }
done
mkdir -p "$ROOT/dist"
tar -czf "$ROOT/dist/sdrhub-source.tar.gz" -C "$ROOT" \
    README.md upstreams.lock scripts pi sources
cp "$ROOT/scripts/proxmox.sh" "$ROOT/dist/proxmox.sh"
(
    cd "$ROOT/dist"
    sha256sum sdrhub-source.tar.gz proxmox.sh hub-image.txt hub-image.tar.gz loft-pi.img.xz pi-imager.json > SHA256SUMS
)
