#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# Prevent package post-install scripts from starting daemons inside the image.
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg python3 \
    python3-flask python3-requests python3-cryptography git usbutils rtl-sdr \
    jq zstd netcat-openbsd socat avahi-utils nftables iproute2 openssl
install -d -m 0755 /etc/apt/keyrings
curl -fsS --retry 5 https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
echo 'deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable' > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-compose-plugin
bash /opt/loft-source/adsb-feeder-image/src/tools/app-install.sh -l /opt/loft-source/adsb-feeder-image -n
cat >> /opt/adsb/config/.env <<'EOF'
_ADSBIM_AGGREGATORS_SELECTION=nano
FEEDER_SERIAL_1090=00000001
FEEDER_ENABLE_BIASTEE=False
_ADSBIM_WEB_AUTH_ENABLED=True
EOF
useradd --system --no-create-home --groups plugdev --shell /usr/sbin/nologin loft-radio
printf 'blacklist dvb_usb_rtl28xxu\nblacklist rtl2832\nblacklist rtl2830\n' > /etc/modprobe.d/loft-rtlsdr.conf
printf 'SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="2838", GROUP="plugdev", MODE="0660"\n' > /etc/udev/rules.d/99-loft-rtlsdr.rules
install -m 0644 /opt/loft-source/pi/*.service /etc/systemd/system/
for service in adsb-setup adsb-docker loft-firewall loft-rtl-tcp; do
    install -d "/etc/systemd/system/$service.service.d"
    printf '[Unit]\nRequires=loft-firstboot.service\nAfter=loft-firstboot.service\n' > "/etc/systemd/system/$service.service.d/provisioning.conf"
done
install -d /etc/systemd/system/adsb-docker.service.d
printf '[Unit]\nRequires=loft-firewall.service\nAfter=loft-firewall.service\n' > /etc/systemd/system/adsb-docker.service.d/firewall.conf
systemctl enable docker loft-firstboot loft-firewall loft-rtl-tcp
# Keep our edited application rather than replacing it with upstream updates.
systemctl disable adsb-update.timer
rm /usr/sbin/policy-rc.d
apt-get clean
cloud-init clean --logs --machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
