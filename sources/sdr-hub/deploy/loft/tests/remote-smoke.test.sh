#!/bin/bash
set -euo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d -t loft-smoke-test.XXXXXXXX)
NETWORK="loft-smoke-$$"
RADIO="$NETWORK-radio"
HUB="$NETWORK-hub"
cleanup() {
    docker rm -f "$HUB" "$RADIO" >/dev/null 2>&1 || true
    docker network rm "$NETWORK" >/dev/null 2>&1 || true
    docker run --rm --user 0:0 -v "$TMP:/cleanup" ubuntu:24.04 \
        chown -hR "$(id -u):$(id -g)" /cleanup/data /cleanup/logs
    rm -rf -- "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/data" "$TMP/logs"
jq '.devices[0].device_args.rtltcp = "mock-radio:1234"' "$DIR/config.example.json" > "$TMP/data/config.json"
docker network create "$NETWORK" >/dev/null
docker run -d --name "$RADIO" --network "$NETWORK" --network-alias mock-radio \
    -v "$DIR/tests/mock-rtl-tcp.cjs:/mock.cjs:ro" node:22-alpine node /mock.cjs >/dev/null
docker run -d --name "$HUB" --network "$NETWORK" \
    -e HTTP_PASSWORD=test-only-http -e MQTT_PASSWORD=test-only-mqtt \
    -v "$TMP/data:/app/data" -v "$TMP/logs:/var/log/sdr" \
    -v "$DIR/tests/radio-smoke.py:/radio-smoke.py:ro" \
    loft/sdr-hub:local >/dev/null

ready=false
for ((attempt=0; attempt<60; attempt++)); do
    if docker logs "$RADIO" 2>&1 | grep -q 'COMMAND 2 1024000' \
        && grep -q 'driver:.*rtltcp.*serial:.*77465553' "$TMP/logs/sdr_scanner_debug.log" 2>/dev/null \
        && docker exec "$HUB" python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1/").close()' >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 2
done
if [[ "$ready" != true ]]; then
    docker logs "$HUB" >&2
    docker logs "$RADIO" >&2
    for log in "$TMP/logs/"*.log; do
        [[ -f "$log" ]] && tail -n 30 "$log" >&2
    done
    echo "FAIL: web UI and remote scanner did not start" >&2
    exit 1
fi
if ! docker logs "$RADIO" 2>&1 | grep -Eq 'COMMAND 1 14[4-6][0-9]{6}'; then
    echo "FAIL: scanner did not tune the mock radio to the configured band" >&2
    exit 1
fi
baseline=$(docker logs "$RADIO" 2>&1 | grep -c 'COMMAND 2 1024000')
docker stop "$RADIO" >/dev/null
sleep 12
docker start "$RADIO" >/dev/null
recovered=false
for ((attempt=0; attempt<30; attempt++)); do
    count=$(docker logs "$RADIO" 2>&1 | grep -c 'COMMAND 2 1024000' || true)
    if ((count > baseline)) && docker exec "$HUB" python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1/").close()' >/dev/null 2>&1; then
        recovered=true
        break
    fi
    sleep 2
done
[[ "$recovered" == true ]] || { echo "FAIL: scanner did not reconnect after radio restart" >&2; exit 1; }
echo "PASS: web UI, explicit remote tuning, sample rate and reconnection without USB devices"
docker exec -e PYTHONPATH=/app -w /app "$HUB" python3 /radio-smoke.py
