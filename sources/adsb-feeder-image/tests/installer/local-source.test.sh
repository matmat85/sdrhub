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
bash "$INSTALLER" -l /source
[[ -f /opt/adsb/adsb-setup/app.py ]]
[[ -f /opt/adsb/app.adsb.feeder.image ]]
[[ -f /usr/lib/systemd/system/adsb-setup.service ]]
[[ ! -f /usr/lib/systemd/system/adsb-bootstrap.service ]]
cmp /source/src/modules/adsb-feeder/filesystem/root/opt/adsb/docker-compose.yml /opt/adsb/docker-compose.yml
after=$(find /source -type f -not -path '*/.git/*' -exec sha256sum {} + | sort | sha256sum)
[[ "$before" == "$after" ]] || { echo "FAIL: installer modified its source checkout" >&2; exit 1; }
grep -q 'enable --now' /tmp/installer-services.log
echo "PASS: local install preserves the source checkout and installs its files and services"
