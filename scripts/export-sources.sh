#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PARENT=$(dirname "$ROOT")
[[ ! -e "$ROOT/sources" ]] || { echo "sources already exists; move it aside before exporting" >&2; exit 1; }
mkdir "$ROOT/sources"
for project in sdr-hub sdr-monitor rtl-sdr-scanner-cpp adsb-feeder-image; do
    [[ -d "$PARENT/$project/.git" ]] || { echo "Missing checkout: $project" >&2; exit 1; }
    mkdir "$ROOT/sources/$project"
    (
        cd "$PARENT/$project"
        git ls-files -z --cached --others --exclude-standard |
            tar --exclude='.env' --exclude='*/.env' \
                --exclude='data/*' --exclude='logs/*' --exclude='__pycache__/*' \
                --exclude='*/__pycache__/*' --exclude='*.pyc' \
                --exclude='sdrplay/*.run' --null -T - -cf -
    ) | tar -xf - -C "$ROOT/sources/$project"
done
echo "Exported edited checkouts, without Git metadata or local .env files."
echo "Review sources before adding them to your release repository."
