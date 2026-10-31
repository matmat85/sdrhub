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
        TAG) TAG=v0.1.1 ;;
        PI) PI=192.168.1.50 ;;
        ADSB_ID) ADSB_ID=${OVERRIDE_ADSB:-$3} ;;
        *) printf -v "$1" '%s' "$3" ;;
    esac
}
confirm_create() { return 0; }
bridge_exists() { [[ "$1" == vmbr0 || "$1" == vmbr9 ]]; }
list_bridges() { printf 'vmbr0\nvmbr9\n'; }
pveversion() { echo pve-manager/9.2.20; }
ip() { echo 'default via 192.168.1.1 dev vmbr9 proto kernel'; }
pvesm() {
    if [[ "$*" == *vztmpl* ]]; then
        printf 'Name Type Status Total Used Available %%\nlocal dir active 1000 100 900 10%%\n'
    else
        printf 'Name Type Status Total Used Available %%\nlocal-lvm lvmthin active 1000 100 900 10%%\n'
    fi
}
pvesh() {
    case "$2" in
        /cluster/resources)
            echo '[{"vmid":100,"type":"qemu","node":"remote"},{"vmid":101,"type":"lxc"},{"vmid":102,"type":"qemu"}]' ;;
        /cluster/nextid)
            [[ "$4" -ge 103 ]] || return 1
            printf '%s\n' "$4" ;;
        *) return 1 ;;
    esac
}
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
grep -q 'create 103 .*--unprivileged 1.*nesting=1,keyctl=1' "$CALLS"
grep -q 'create 104 .*--memory 4096.*--rootfs local-lvm:24.*bridge=vmbr9' "$CALLS"
grep -q 'exec 103 -- bash /opt/loft-release/scripts/lxc-install.sh adsb 192.168.1.50 sha256:' "$CALLS"
grep -q 'push 104 .*hub-image.tar.gz /root/hub-image.tar.gz' "$CALLS"
if grep -Eq 'destroy|delete|--unprivileged 0' "$CALLS"; then exit 1; fi
: > "$CALLS"
( OVERRIDE_ADSB=104; main )
grep -q '^create 104 ' "$CALLS"
grep -q '^create 103 ' "$CALLS"
: > "$CALLS"
if ( OVERRIDE_ADSB=100; main ); then echo "Occupied cluster ID accepted" >&2; exit 1; fi
[[ ! -s "$CALLS" ]]
[[ $(recommended_storage $'Name Type Status Total Used Available\nsmall zfs active 1000 800 200\nlarge zfs active 10000 500 9500\nlocal-lvm lvmthin inactive 10000 0 10000' local-lvm) == large ]]
[[ $(recommended_storage $'Name Type Status Total Used Available\nlarge zfs active 10000 500 9500\nlocal-lvm lvmthin active 1000 100 900' local-lvm) == local-lvm ]]
if recommended_storage $'Name Type Status Total Used Available\nlocal dir inactive 1000 100 900' local; then
    echo "Inactive storage recommended" >&2; exit 1
fi
(
    ip() { echo 'default via 192.168.1.1 dev eno1'; }
    [[ $(recommended_bridge) == vmbr0 ]]
    # shellcheck disable=SC2329
    list_bridges() { echo vmbr2; }
    [[ $(recommended_bridge) == vmbr2 ]]
)
if ( list_bridges() { return 0; }; recommended_bridge ); then
    echo "Missing bridge accepted" >&2; exit 1
fi
printf 'corrupt\n' > "$TMP/hub-image.tar.gz"
: > "$CALLS"
if ( main ); then echo "Checksum mismatch accepted" >&2; exit 1; fi
[[ ! -s "$CALLS" ]]
echo "PASS: detected defaults, cluster-wide IDs, overrides, missing-resource rejection and verified image transfer"
