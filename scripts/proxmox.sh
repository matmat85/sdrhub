#!/bin/bash
set -euo pipefail
REPOSITORY=matmat85/sdrhub

fail() { echo "ERROR: $*" >&2; exit 1; }
prompt() {
    local name=$1 label=$2 default=$3 answer
    read -r -p "$label [$default]: " answer </dev/tty
    printf -v "$name" '%s' "${answer:-$default}"
}
ipv4() {
    local value=$1 octet
    [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r -a octets <<< "$value"
    for octet in "${octets[@]}"; do
        (( 10#$octet <= 255 )) || return 1
    done
    [[ "$value" != 0.* && "$value" != 127.* ]] || return 1
}
bridge_exists() { [[ -d "/sys/class/net/$1/bridge" ]]; }
confirm_create() {
    local confirm
    read -r -p "Type CREATE to continue: " confirm </dev/tty
    [[ "$confirm" == CREATE ]] || fail "Cancelled"
}
main() {
    [[ $EUID == 0 ]] || fail "Run this on the Proxmox host as root"
    for cmd in pct pveversion pveam pvesm curl sha256sum tar ip; do
        command -v "$cmd" >/dev/null || fail "Missing Proxmox prerequisite: $cmd"
    done
    [[ $(pveversion) == pve-manager/9.* ]] || fail "This installer targets Proxmox VE 9"
    prompt TAG "Published release tag (not a branch)" v0.1.0
    [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Use a version tag such as v0.1.0"
    prompt PI "Pi's reserved LAN IPv4 address" ""
    ipv4 "$PI" || fail "Invalid Pi address"
    prompt BRIDGE "LAN bridge" vmbr0
    [[ "$BRIDGE" =~ ^[a-zA-Z0-9_-]+$ ]] || fail "Invalid bridge"
    bridge_exists "$BRIDGE" || fail "$BRIDGE is not a Linux bridge"
    pvesm status --content rootdir
    prompt STORAGE "Container disk storage (must support rootdir)" local-lvm
    pvesm status --content vztmpl
    prompt TEMPLATE_STORAGE "Template storage (must support vztmpl)" local
    for value in "$STORAGE" "$TEMPLATE_STORAGE"; do
        [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || fail "Invalid storage name"
    done
    pvesm status --storage "$STORAGE" --content rootdir | awk 'NR>1 && $3=="active"{found=1} END{exit !found}' ||
        fail "$STORAGE must be active and support rootdir"
    pvesm status --storage "$TEMPLATE_STORAGE" --content vztmpl | awk 'NR>1 && $3=="active"{found=1} END{exit !found}' ||
        fail "$TEMPLATE_STORAGE must be active and support templates"
    prompt ADSB_ID "New ADS-B CT ID" 120
    prompt HUB_ID "New SDR Hub CT ID" 121
    [[ "$ADSB_ID" =~ ^[1-9][0-9]{2,8}$ && "$HUB_ID" =~ ^[1-9][0-9]{2,8}$ && "$ADSB_ID" != "$HUB_ID" ]] ||
        fail "Use distinct CT IDs >=100"
    for id in "$ADSB_ID" "$HUB_ID"; do
        if pct config "$id" >/dev/null 2>&1; then fail "CT $id already exists; nothing overwritten"; fi
        if [[ -e "/etc/pve/qemu-server/$id.conf" ]]; then fail "VM $id already exists"; fi
    done
    echo "Create two UNPRIVILEGED Debian 13 LXCs on $BRIDGE, using DHCP:"
    echo "  $ADSB_ID: ADS-B, 2 cores / 2 GiB RAM / 16 GiB disk"
    echo "  $HUB_ID: SDR Hub, 2 cores / 4 GiB RAM / 24 GiB disk"
    echo "The Pi will not be modified. No USB passthrough, host Docker or privileged fallback."
    confirm_create

    WORK=$(mktemp -d -t sdrhub-install.XXXXXXXX)
    trap 'rm -f "$WORK/sdrhub-source.tar.gz" "$WORK/SHA256SUMS" "$WORK/hub-image.txt" "$WORK/hub-image.tar.gz"; rmdir "$WORK" 2>/dev/null || true' EXIT
    trap 'echo "Installation failed. Created CTs are retained for diagnosis; inspect them with pct list. No existing CT was removed." >&2' ERR
    local base="https://github.com/$REPOSITORY/releases/download/$TAG"
    for asset in sdrhub-source.tar.gz SHA256SUMS hub-image.txt hub-image.tar.gz; do
        curl --fail --location --proto '=https' "$base/$asset" -o "$WORK/$asset"
    done
    for asset in sdrhub-source.tar.gz hub-image.txt hub-image.tar.gz; do
        local expected actual
        expected=$(awk -v name="$asset" '$2==name {print $1}' "$WORK/SHA256SUMS")
        [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || fail "Missing/invalid checksum for $asset"
        actual=$(sha256sum "$WORK/$asset")
        [[ "${actual%% *}" == "$expected" ]] || fail "$asset checksum mismatch"
    done
    local image template
    image=$(cat "$WORK/hub-image.txt")
    [[ "$image" =~ ^sha256:[a-f0-9]{64}$ ]] || fail "Release must contain an immutable SDR Hub image ID"
    pveam update
    template=$(pveam available --section system | awk '$2 ~ /^debian-13-standard_.*_amd64.tar.zst$/ {print $2}' | sort -V | tail -n 1)
    [[ -n "$template" ]] || fail "No Debian 13 amd64 template available"
    pveam download "$TEMPLATE_STORAGE" "$template"
    local role id memory disk
    for role in adsb hub; do
        if [[ "$role" == adsb ]]; then id=$ADSB_ID; memory=2048; disk=16
        else id=$HUB_ID; memory=4096; disk=24; fi
        pct create "$id" "$TEMPLATE_STORAGE:vztmpl/$template" --hostname "loft-$role" \
            --ostype debian --unprivileged 1 --features nesting=1,keyctl=1 \
            --cores 2 --memory "$memory" --swap 512 --rootfs "$STORAGE:$disk" \
            --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp,type=veth" --onboot 1
        pct start "$id"
        pct push "$id" "$WORK/sdrhub-source.tar.gz" /root/sdrhub-source.tar.gz
        pct exec "$id" -- bash -c 'mkdir -p /opt/loft-release; tar -xzf /root/sdrhub-source.tar.gz -C /opt/loft-release'
        if [[ "$role" == hub ]]; then pct push "$id" "$WORK/hub-image.tar.gz" /root/hub-image.tar.gz; fi
        pct exec "$id" -- bash /opt/loft-release/scripts/lxc-install.sh "$role" "$PI" "$image"
    done
    echo "Both LXCs installed. Reserve their DHCP addresses and restrict Pi ports 1234/30005 to these hosts."
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
