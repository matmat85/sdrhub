#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
[[ $EUID == 0 ]] || { echo "Run as root on a dedicated Linux ARM64 build runner" >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || { echo "Use a native ARM64 runner; this builder does not emulate ARM" >&2; exit 1; }
for cmd in curl sha256sum xz losetup mount umount parted e2fsck resize2fs chroot; do
    command -v "$cmd" >/dev/null || { echo "Missing image build tool: $cmd" >&2; exit 1; }
done
# shellcheck source=base.lock
source "$ROOT/pi/base.lock"
mkdir -p "$ROOT/build" "$ROOT/dist"
IMAGE="$ROOT/build/loft-pi.img"
MOUNT="$ROOT/build/mount"
[[ ! -e "$IMAGE" && ! -e "$MOUNT" ]] || { echo "Existing image workspace; refusing to overwrite it" >&2; exit 1; }
curl --fail --location --proto '=https' --retry 5 "$BASE_URL" -o "$ROOT/build/base.img.xz"
printf '%s  %s\n' "$BASE_SHA256" "$ROOT/build/base.img.xz" | sha256sum -c -
xz -dc "$ROOT/build/base.img.xz" > "$IMAGE"
truncate -s +3G "$IMAGE"
LOOP=$(losetup --find --show --partscan "$IMAGE")
cleanup() {
    local path
    for path in dev/pts dev proc sys boot/firmware ""; do
        if mountpoint -q "$MOUNT/$path"; then umount "$MOUNT/$path"; fi
    done
    losetup -d "$LOOP"
}
trap cleanup EXIT
parted -s "$LOOP" resizepart 2 100%
partprobe "$LOOP"
e2fsck -fp "${LOOP}p2" || [[ $? == 1 ]]
resize2fs "${LOOP}p2"
mkdir "$MOUNT"
mount "${LOOP}p2" "$MOUNT"
mount "${LOOP}p1" "$MOUNT/boot/firmware"
for path in dev proc sys; do mount --bind "/$path" "$MOUNT/$path"; done
mount --bind /dev/pts "$MOUNT/dev/pts"
mv "$MOUNT/etc/resolv.conf" "$ROOT/build/original-resolv.conf"
cp -L /etc/resolv.conf "$MOUNT/etc/resolv.conf"
install -d "$MOUNT/opt/loft-source" "$MOUNT/usr/local/lib/loft" "$MOUNT/etc/loft-receiver"
cp -a "$ROOT/sources/adsb-feeder-image" "$MOUNT/opt/loft-source/"
cp -a "$ROOT/pi" "$MOUNT/opt/loft-source/pi"
install -m 0644 "$ROOT/pi/receiver.py" "$ROOT/pi/firstboot.py" "$MOUNT/usr/local/lib/loft/"
chroot "$MOUNT" /bin/bash /opt/loft-source/pi/install.sh
chroot "$MOUNT" python3 -m compileall -q /opt/adsb/adsb-setup /usr/local/lib/loft
chroot "$MOUNT" systemd-analyze verify loft-firstboot.service loft-firewall.service loft-rtl-tcp.service
chroot "$MOUNT" systemd-analyze verify loft-display.service
chroot "$MOUNT" systemctl is-enabled docker loft-firstboot loft-firewall loft-rtl-tcp adsb-setup
rm "$MOUNT/etc/resolv.conf"
mv "$ROOT/build/original-resolv.conf" "$MOUNT/etc/resolv.conf"
[[ ! -e "$MOUNT/etc/loft-receiver/provisioned" && ! -e "$MOUNT/root/loft-credentials.txt" ]] ||
    { echo "Image unexpectedly contains first-boot credentials" >&2; exit 1; }
cleanup
trap - EXIT
rm "$ROOT/build/base.img.xz"
xz -T2 -3 -c "$IMAGE" > "$ROOT/dist/loft-pi.img.xz"
echo "Built $ROOT/dist/loft-pi.img.xz (physical Pi boot still requires verification)"
