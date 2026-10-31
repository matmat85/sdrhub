#!/bin/bash
set -euo pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
jq -e '.devices | length == 1' "$DIR/config.example.json" >/dev/null
jq -e '.devices[0] | .serial == "77465553" and .sample_rate == 1024000 and .device_args.driver == "rtltcp" and .device_args.rtltcp == "192.168.1.50:1234"' \
    "$DIR/config.example.json" >/dev/null
LXC_BIND_ADDRESS=127.0.0.1 SDR_HTTP_PASSWORD=test-only-http SDR_MQTT_PASSWORD=test-only-mqtt \
    docker compose -f "$DIR/compose.yml" config --quiet
if LXC_BIND_ADDRESS=127.0.0.1 SDR_HTTP_PASSWORD='' SDR_MQTT_PASSWORD='' \
    docker compose -f "$DIR/compose.yml" config --quiet 2>/dev/null; then
    echo "FAIL: compose accepted empty credentials" >&2
    exit 1
fi
echo "PASS: scanner identity, bandwidth, endpoint and required Compose credentials"
