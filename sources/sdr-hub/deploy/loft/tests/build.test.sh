#!/bin/bash
set -euo pipefail

SOURCE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d -t loft-build-test.XXXXXXXX)
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/sdr-hub/deploy/loft" "$TMP/sdr-monitor" "$TMP/rtl-sdr-scanner-cpp" "$TMP/adsb-feeder-image"
cp "$SOURCE/build.sh" "$TMP/sdr-hub/deploy/loft/build.sh"
export DOCKER_LOG="$TMP/docker.log"

docker() {
    printf '%s\n' "$*" >> "$DOCKER_LOG"
    if [[ "${FAIL_TESTS:-0}" == 1 && "$1" == run && "$*" == *sdr-scanner-tests* ]]; then
        return 42
    fi
    if [[ "$1" == run && "$*" == *SoapySDRUtil* ]]; then
        echo "Available factories... rtltcp, rtlsdr"
    fi
}
export -f docker

bash "$TMP/sdr-hub/deploy/loft/build.sh"
grep -q -- '--entrypoint /usr/bin/auto_sdr_test loft/sdr-scanner-tests:local --gtest_filter=DeviceArgs.\*' "$DOCKER_LOG"
grep -q -- '--build-arg SDR_SCANNER_IMAGE=loft/sdr-scanner:local' "$DOCKER_LOG"
grep -q -- '--build-arg SDR_MONITOR_IMAGE=loft/sdr-monitor:local' "$DOCKER_LOG"
grep -q -- '--entrypoint SoapySDRUtil loft/sdr-hub:local --info' "$DOCKER_LOG"
echo "PASS: build uses the custom scanner, custom monitor, regression runner and plugin check"

: > "$DOCKER_LOG"
export FAIL_TESTS=1
if bash "$TMP/sdr-hub/deploy/loft/build.sh"; then
    echo "FAIL: a failed regression test must abort the build" >&2
    exit 1
fi
if grep -q -- '--build-arg SDR_SCANNER_IMAGE' "$DOCKER_LOG"; then
    echo "FAIL: application build continued after failed tests" >&2
    exit 1
fi
echo "PASS: regression failures prevent application builds"
