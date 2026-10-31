#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
for project in sdr-hub rtl-sdr-scanner-cpp sdr-monitor adsb-feeder-image; do
    [[ -d "$ROOT/$project" ]] || { echo "Missing sibling checkout: $ROOT/$project" >&2; exit 1; }
done
command -v docker >/dev/null || { echo "Docker is required" >&2; exit 1; }
docker info >/dev/null

docker build --target test -t loft/sdr-scanner-tests:local "$ROOT/rtl-sdr-scanner-cpp"
docker run --rm --entrypoint /usr/bin/auto_sdr_test loft/sdr-scanner-tests:local --gtest_filter='DeviceArgs.*'
docker build -t loft/sdr-scanner:local "$ROOT/rtl-sdr-scanner-cpp"
docker build -f "$ROOT/sdr-monitor/Dockerfile.remote" -t loft/sdr-monitor:local "$ROOT/sdr-monitor"
docker build --build-arg SDR_SCANNER_IMAGE=loft/sdr-scanner:local \
    --build-arg SDR_MONITOR_IMAGE=loft/sdr-monitor:local \
    -t loft/sdr-hub:local "$ROOT/sdr-hub"
docker run --rm --entrypoint SoapySDRUtil loft/sdr-hub:local --info \
    | grep -E 'Available factories.*rtltcp'
echo "Built loft/sdr-hub:local; configure deploy/loft/.env and data/config.json before starting."
