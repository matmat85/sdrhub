#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../scripts/proxmox.sh
source "$ROOT/scripts/proxmox.sh"
for address in 192.168.1.50 10.0.0.5 172.16.0.1; do ipv4 "$address"; done
for address in 0.0.0.0 127.0.0.1 '1.2.3.999' '1.2.3.4;echo' 'hostname' '1.2.3'; do
    if ipv4 "$address"; then echo "Invalid IPv4 accepted: $address" >&2; exit 1; fi
done
TMP=$(mktemp -d)
trap 'rm -f "$TMP/calls" "$TMP/source.tar.gz" "$TMP/hub-image.txt" "$TMP/hub-image.tar.gz" "$TMP/SHA256SUMS"; rmdir "$TMP"' EXIT
CALLS="$TMP/calls"
printf 'fixture\n' > "$TMP/source.tar.gz"
printf 'archive fixture\n' > "$TMP/hub-image.tar.gz"
printf 'sha256:%064d\n' 0 > "$TMP/hub-image.txt"
(
    cd "$TMP"
    sha256sum source.tar.gz | sed 's/source.tar.gz/sdrhub-source.tar.gz/' > SHA256SUMS
    sha256sum hub-image.txt hub-image.tar.gz >> SHA256SUMS
)
prompt() {
    case "$1" in
        TAG) TAG=v0.1.0 ;;
        PI) PI=192.168.1.50 ;;
        BRIDGE) BRIDGE=vmbr0 ;;
        STORAGE) STORAGE=local-lvm ;;
        TEMPLATE_STORAGE) TEMPLATE_STORAGE=local ;;
        ADSB_ID) ADSB_ID=120 ;;
        HUB_ID) HUB_ID=121 ;;
    esac
}
confirm_create() { return 0; }
bridge_exists() { return 0; }
pveversion() { echo pve-manager/9.2.20; }
ip() { return 0; }
pvesm() { printf 'Name Type Status\nlocal dir active\n'; }
pveam() {
    if [[ "$1" == available ]]; then echo 'system debian-13-standard_13.0-1_amd64.tar.zst'; fi
}
pct() {
    if [[ "$1" == config ]]; then return 1; fi
    printf '%s\n' "$*" >> "$CALLS"
}
curl() {
    local url="" target=""
    while (($#)); do
        case "$1" in
            -o) shift; target=$1 ;;
            https:*) url=$1 ;;
        esac
        shift
    done
    local asset=${url##*/}
    if [[ "$asset" == sdrhub-source.tar.gz ]]; then asset=source.tar.gz; fi
    cp "$TMP/$asset" "$target"
}
( main )
[[ $(grep -c '^create ' "$CALLS") == 2 ]]
grep -q 'create 120 .*--unprivileged 1.*nesting=1,keyctl=1' "$CALLS"
grep -q 'create 121 .*--memory 4096' "$CALLS"
grep -q 'exec 120 -- bash /opt/loft-release/scripts/lxc-install.sh adsb 192.168.1.50 sha256:' "$CALLS"
grep -q 'push 121 .*hub-image.tar.gz /root/hub-image.tar.gz' "$CALLS"
if grep -Eq 'destroy|delete|--unprivileged 0' "$CALLS"; then exit 1; fi
printf 'corrupt\n' > "$TMP/hub-image.tar.gz"
: > "$CALLS"
if ( main ); then echo "Checksum mismatch accepted" >&2; exit 1; fi
[[ ! -s "$CALLS" ]]
echo "PASS: two unprivileged LXCs, release image transfer and checksum failure before creation"
