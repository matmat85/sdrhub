#!/bin/bash
set -euo pipefail

INSTALLER=/source/src/tools/app-install.sh
before=$(find /source -type f -not -path '*/.git/*' -exec sha256sum {} + | sort | sha256sum)
for args in "-l" "-l /source -b main" "-l /source -t test" "-l /source -s /tmp" "-l /missing-checkout"; do
    # Intentional splitting: these cases exercise separate CLI arguments.
    # shellcheck disable=SC2086
    if bash "$INSTALLER" $args > /tmp/installer-error.log 2>&1; then
        echo "FAIL: accepted invalid arguments: $args" >&2
        exit 1
    fi
    [[ ! -d /opt/adsb ]] || { echo "FAIL: invalid arguments created an installation" >&2; exit 1; }
done
if [[ "${TEST_NO_START:-0}" == 1 ]]; then
    bash "$INSTALLER" -l /source -n
else
    bash "$INSTALLER" -l /source
fi
[[ -f /opt/adsb/adsb-setup/app.py ]]
[[ -f /opt/adsb/app.adsb.feeder.image ]]
[[ -f /usr/lib/systemd/system/adsb-setup.service ]]
[[ ! -f /usr/lib/systemd/system/adsb-bootstrap.service ]]
cmp /source/src/modules/adsb-feeder/filesystem/root/opt/adsb/docker-compose.yml /opt/adsb/docker-compose.yml
after=$(find /source -type f -not -path '*/.git/*' -exec sha256sum {} + | sort | sha256sum)
[[ "$before" == "$after" ]] || { echo "FAIL: installer modified its source checkout" >&2; exit 1; }
if [[ "${TEST_NO_START:-0}" == 1 ]]; then
    grep -q 'enable ' /tmp/installer-services.log
    if grep -q 'enable --now' /tmp/installer-services.log; then
        echo "FAIL: -n started services" >&2
        exit 1
    fi
else
    grep -q 'enable --now' /tmp/installer-services.log
fi
echo "PASS: local install preserves the source checkout and installs its files and services"
