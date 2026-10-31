#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../scripts/pi-image-plan.sh
source "$ROOT/scripts/pi-image-plan.sh"
TMP=$(mktemp -d -t loft-pi-plan.XXXXXXXX)
trap 'rm -rf -- "$TMP"' EXIT
git -C "$TMP" init -q
git -C "$TMP" config user.name Test
git -C "$TMP" config user.email test@example.invalid
mkdir -p "$TMP/pi" "$TMP/sources/adsb-feeder-image" "$TMP/scripts"
printf 'pi\n' > "$TMP/pi/build.sh"
printf 'feeder\n' > "$TMP/sources/adsb-feeder-image/source"
printf 'installer\n' > "$TMP/scripts/lxc-install.sh"
git -C "$TMP" add .
git -C "$TMP" commit -qm baseline
git -C "$TMP" tag v0.1.2
[[ $(plan_pi_image "$TMP" "") == build ]]
[[ $(plan_pi_image "$TMP" v0.1.2) == v0.1.2 ]]
printf 'lxc change\n' >> "$TMP/scripts/lxc-install.sh"
git -C "$TMP" commit -qam lxc
[[ $(plan_pi_image "$TMP" v0.1.2) == v0.1.2 ]]
printf 'new release instructions\n' > "$TMP/pi/README.md"
git -C "$TMP" add pi/README.md
git -C "$TMP" commit -qm docs
[[ $(plan_pi_image "$TMP" v0.1.2) == v0.1.2 ]]
printf 'display change\n' >> "$TMP/pi/build.sh"
git -C "$TMP" commit -qam display
[[ $(plan_pi_image "$TMP" v0.1.2) == build ]]
git -C "$TMP" tag v0.1.3
printf 'feeder change\n' >> "$TMP/sources/adsb-feeder-image/source"
git -C "$TMP" commit -qam feeder
[[ $(plan_pi_image "$TMP" v0.1.3) == build ]]
if ( set -e; plan_pi_image "$TMP" v9.9.9 ); then
    echo "Missing release tag accepted" >&2
    exit 1
fi
echo "PASS: no release, unchanged Pi, LXC/docs-only changes, display/feeder changes and missing tag"
