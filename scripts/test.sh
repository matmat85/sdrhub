#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
shellcheck -x -P "$ROOT/scripts" -P "$ROOT/pi" "$ROOT/scripts/"*.sh "$ROOT/pi/"*.sh
docker run --rm --entrypoint bash -v "$ROOT:/release:ro" \
    ubuntu:24.04 /release/tests/proxmox.test.sh
docker build -f "$ROOT/sources/adsb-feeder-image/tests/installer/Dockerfile" \
    -t loft/feeder-installer-tests:local "$ROOT/sources/adsb-feeder-image"
docker run --rm loft/feeder-installer-tests:local
docker run --rm -e TEST_NO_START=1 loft/feeder-installer-tests:local
docker run --rm --cap-add NET_ADMIN --entrypoint python3 -v "$ROOT:/release:ro" \
    loft/feeder-installer-tests:local /release/tests/receiver.test.py
docker run --rm --entrypoint node -v "$ROOT:/release:ro" \
    node:22-alpine --test /release/sources/sdr-monitor/tests/remote-device.test.cjs
bash "$ROOT/sources/sdr-hub/deploy/loft/tests/remote-smoke.test.sh"
