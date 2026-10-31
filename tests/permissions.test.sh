#!/bin/bash
set -euo pipefail
TMP=$(mktemp -d -t loft-permissions.XXXXXXXX)
cleanup() {
    docker run --rm --user 0:0 -v "$TMP:/fixture" ubuntu:24.04 \
        chown -hR "$(id -u):$(id -g)" /fixture
    rm -rf -- "$TMP"
}
trap cleanup EXIT
docker run --rm --user 0:0 -v "$TMP:/fixture" ubuntu:24.04 bash -c \
    'mkdir -p /fixture/data/public /fixture/logs; touch /fixture/data/public/static.txt; chown -R 1000:1000 /fixture/data /fixture/logs; chown 1001:1001 /fixture; chmod 755 /fixture'
if docker run --rm --user 1001:1001 -v "$TMP:/fixture" ubuntu:24.04 \
    rm -rf -- /fixture/data /fixture/logs 2>/dev/null; then
    echo "Fixture did not reproduce the CI ownership failure" >&2
    exit 1
fi
docker run --rm --user 0:0 -v "$TMP:/fixture" ubuntu:24.04 \
    chown -hR 1001:1001 /fixture/data
docker run --rm --user 1001:1001 -v "$TMP:/fixture" ubuntu:24.04 \
    rm -rf -- /fixture/data /fixture/logs
echo "PASS: CI UID 1001 can remove generated files after scoped ownership restoration"
