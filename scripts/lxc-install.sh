#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROLE=${1:?Expected adsb or hub}
PI=${2:?Expected Pi address}
IMAGE=${3:?Expected release image digest}
[[ $EUID == 0 && ( "$ROLE" == adsb || "$ROLE" == hub ) ]] || { echo "Invalid role or not root" >&2; exit 1; }
# shellcheck source=proxmox.sh
source "$ROOT/scripts/proxmox.sh"
ipv4 "$PI" || fail "Invalid Pi address"
[[ "$IMAGE" =~ ^ghcr.io/matmat85/sdrhub@sha256:[a-f0-9]{64}$ ]] || fail "Invalid image digest"
[[ ! -e /opt/adsb && ! -e /opt/loft-hub ]] || fail "Fresh containers only; refusing to overwrite an installation"
export DEBIAN_FRONTEND=noninteractive
# Bootstrap dependencies before using curl on a minimal Debian template.
for attempt in {1..60}; do
    if apt-get update; then break; fi
    if [[ "$attempt" == 60 ]]; then fail "No working network after waiting for DHCP"; fi
    sleep 2
done
apt-get install -y --no-install-recommends ca-certificates curl gnupg openssl jq
curl -fsS --retry 5 --connect-timeout 5 https://download.docker.com/linux/debian/gpg -o /tmp/loft-docker.asc
install -d -m 0755 /etc/apt/keyrings
install -m 0644 /tmp/loft-docker.asc /etc/apt/keyrings/docker.asc
rm /tmp/loft-docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
docker info >/dev/null
ADDRESS=$(ip -4 -o addr show dev eth0 scope global | awk '{split($4,a,"/");print a[1];exit}')
ipv4 "$ADDRESS" || fail "No LAN IPv4 address"
PASSWORD=$(openssl rand -hex 18)
if [[ "$ROLE" == hub ]]; then
    install -d -m 0755 /opt/loft-hub/data /opt/loft-hub/logs
    cp "$ROOT/sources/sdr-hub/deploy/loft/compose.yml" /opt/loft-hub/compose.yml
    jq --arg endpoint "$PI:1234" '.devices[0].device_args.rtltcp=$endpoint' \
        "$ROOT/sources/sdr-hub/deploy/loft/config.example.json" > /opt/loft-hub/data/config.json
    # The monitor/scanner run as ubuntu (UID 1000) in the image.
    chown -R 1000:1000 /opt/loft-hub/data /opt/loft-hub/logs
    umask 077
    printf 'LXC_BIND_ADDRESS=%s\nSDR_HUB_IMAGE=%s\nSDR_HTTP_PASSWORD=%s\nSDR_MQTT_PASSWORD=%s\n' \
        "$ADDRESS" "$IMAGE" "$PASSWORD" "$(openssl rand -hex 18)" > /opt/loft-hub/.env
    cd /opt/loft-hub
    docker compose config --quiet
    docker compose pull
    docker compose up -d
    URL="http://$ADDRESS:8000"
else
    apt-get install -y --no-install-recommends git python3 python3-flask python3-requests \
        python3-cryptography usbutils jq zstd netcat-openbsd socat avahi-utils
    bash "$ROOT/sources/adsb-feeder-image/src/tools/app-install.sh" -l "$ROOT/sources/adsb-feeder-image" -n
    umask 077
    HASH=$(printf '%s' "$PASSWORD" | python3 -c 'import sys; from werkzeug.security import generate_password_hash; print(generate_password_hash(sys.stdin.read()))')
    printf '\n_ADSBIM_STATE_REMOTE_SDR=%s,30005\n_ADSBIM_WEB_AUTH_ENABLED=True\n_ADSBIM_WEB_AUTH_USERNAME=admin\n_ADSBIM_WEB_AUTH_PASSWORD_HASH=%s\n' \
        "$PI" "$HASH" >> /opt/adsb/config/.env
    readarray -t services < /opt/adsb/misc/services
    systemctl enable --now "${services[@]}"
    URL="http://$ADDRESS:1099"
fi
for attempt in {1..90}; do
    if curl --fail --silent --output /dev/null "$URL"; then break; fi
    if [[ "$attempt" == 90 ]]; then fail "$ROLE web service did not become ready; check journalctl / docker compose logs"; fi
    sleep 2
done
echo "$ROLE ready: $URL"
echo "Login: admin  Password: $PASSWORD"
if [[ "$ROLE" == adsb ]]; then
    echo "Complete receiver location and aggregator setup. Remote Beast input is already set to $PI,30005."
else
    echo "Set receiver location and legal scan ranges; FM/DAB controls are under Live radio."
fi
