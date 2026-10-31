#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ $EUID == 0 ]] || { echo "Run as root on the Pi" >&2; exit 1; }
MODE=${1:---install-only}
[[ "$MODE" == --install-only || "$MODE" == --enable || "$MODE" == --enable-image || "$MODE" == --disable ]] ||
    { echo "Use --install-only, --enable, --enable-image (image builder only) or --disable" >&2; exit 1; }
BOOT=/boot/firmware/config.txt
[[ -f "$BOOT" ]] || { echo "Raspberry Pi boot configuration not found" >&2; exit 1; }
if [[ "$MODE" == --enable ]]; then
    [[ -f /proc/device-tree/model ]] || { echo "Cannot identify Pi model" >&2; exit 1; }
    grep -aq 'Raspberry Pi Zero 2' /proc/device-tree/model ||
        { echo "This experimental display profile supports Zero 2 W only" >&2; exit 1; }
fi
if [[ "$MODE" == --enable-image ]]; then
    # The ARM image chroot has the builder's /proc, not the target Pi's model.
    if [[ ! -f /usr/sbin/policy-rc.d ]] || ! grep -qx 'exit 101' /usr/sbin/policy-rc.d; then
        echo "--enable-image requires the image builder's daemon-start guard" >&2
        exit 1
    fi
fi
if [[ "$MODE" != --disable ]]; then
    apt-get update
    apt-get install -y --no-install-recommends python3-pil fonts-dejavu-core device-tree-compiler
    install -d /usr/local/lib/loft
    install -m 0644 "$ROOT/display.py" /usr/local/lib/loft/display.py
    install -m 0644 "$ROOT/loft-display.service" /etc/systemd/system/
    dtc -@ -I dts -O dtb -o /boot/firmware/overlays/loft-lcd.dtbo "$ROOT/loft-lcd-overlay.dts"
fi
if [[ "$MODE" == --install-only ]]; then exit 0; fi
cp -a "$BOOT" "$BOOT.loft-display-backup-$(date +%s)"
if [[ "$MODE" == --enable || "$MODE" == --enable-image ]]; then
    if ! grep -q '^include loft-display.txt$' "$BOOT"; then
        printf '\n[all]\ninclude loft-display.txt\n' >> "$BOOT"
    fi
    printf 'dtoverlay=loft-lcd,rotate=90,speed=16000000\n' > /boot/firmware/loft-display.txt
    systemctl enable loft-display.service
else
    printf '# Loft display disabled\n' > /boot/firmware/loft-display.txt
    systemctl disable --now loft-display.service
fi
echo "Display configuration updated. Reboot the Pi to apply; radio settings were not changed."
