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
list_bridges() {
    local path
    for path in /sys/class/net/*/bridge; do
        [[ -d "$path" ]] || continue
        path=${path%/bridge}
        basename "$path"
    done
}
recommended_bridge() {
    local route available
    route=$(ip -4 route show default | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1);exit}}')
    available=$(list_bridges)
    [[ -n "$available" ]] || fail "No Linux bridge detected; configure a LAN bridge in Proxmox first"
    if [[ -n "$route" ]] && bridge_exists "$route"; then
        printf '%s\n' "$route"
    elif grep -qx vmbr0 <<< "$available"; then
        echo vmbr0
    else
        sort <<< "$available" | head -n 1
    fi
}
recommended_storage() {
    local listing=$1 preferred=$2
    awk -v preferred="$preferred" '
        NR>1 && $3=="active" {
            if($1==preferred) selected=$1
            if(best=="" || $6>free){best=$1;free=$6}
        }
        END {if(selected!="") print selected; else if(best!="") print best; else exit 1}
    ' <<< "$listing"
}
recommended_ids() {
    pvesh get /cluster/resources --type vm --output-format json | python3 -c '
import json, sys
resources = json.load(sys.stdin)
used = {int(item["vmid"]) for item in resources}
candidate = 100
for _ in range(2):
    while candidate in used:
        candidate += 1
    if candidate > 999999999:
        raise ValueError("No supported VM/CT ID available")
    print(candidate)
    candidate += 1
'
}
confirm_create() {
    local confirm
    read -r -p "Type CREATE to continue: " confirm </dev/tty
    [[ "$confirm" == CREATE ]] || fail "Cancelled"
}
finish_install() {
    local status=$1 id config state cleanup_failed=0 index
    trap - EXIT INT TERM
    if [[ "$INSTALL_COMPLETE" != true ]]; then
        (( status != 0 )) || status=1
        echo "Installation failed; rolling back only CTs owned by this run." >&2
        for ((index=${#INSTALL_IDS[@]}-1; index>=0; index--)); do
            id=${INSTALL_IDS[index]}
            if ! config=$(pct config "$id"); then
                echo "WARNING: Cannot inspect CT $id; no deletion attempted. Check pct list." >&2
                cleanup_failed=1
                continue
            fi
            if ! grep -Fxq "description: $INSTALL_MARKER" <<< "$config"; then
                echo "WARNING: CT $id ownership marker does not match; leaving it untouched." >&2
                cleanup_failed=1
                continue
            fi
            if ! state=$(pct status "$id"); then
                echo "WARNING: Cannot query CT $id status; leaving it untouched." >&2
                cleanup_failed=1
                continue
            fi
            case "$state" in
                "status: running")
                    if ! pct stop "$id"; then
                        echo "WARNING: Cannot stop CT $id; no deletion attempted." >&2
                        cleanup_failed=1
                        continue
                    fi ;;
                "status: stopped") ;;
                *)
                    echo "WARNING: Unexpected CT $id status; no deletion attempted: $state" >&2
                    cleanup_failed=1
                    continue ;;
            esac
            if ! pct destroy "$id"; then
                echo "WARNING: Cannot remove failed CT $id; inspect it manually." >&2
                cleanup_failed=1
            else
                echo "Removed failed-install CT $id." >&2
            fi
        done
        if (( cleanup_failed )); then
            echo "WARNING: Rollback incomplete. Inspect the reported IDs before retrying; never delete an unverified CT." >&2
        fi
    fi
    if ! rm -f "$WORK/sdrhub-source.tar.gz" "$WORK/SHA256SUMS" "$WORK/hub-image.txt" "$WORK/hub-image.tar.gz" ||
        ! rmdir "$WORK"; then
        echo "WARNING: Cannot fully remove installer temporary files in $WORK." >&2
        (( status != 0 )) || status=1
    fi
    exit "$status"
}
main() {
    [[ $EUID == 0 ]] || fail "Run this on the Proxmox host as root"
    for cmd in pct pveversion pveam pvesm pvesh python3 curl sha256sum tar ip flock; do
        command -v "$cmd" >/dev/null || fail "Missing Proxmox prerequisite: $cmd"
    done
    [[ $(pveversion) == pve-manager/9.* ]] || fail "This installer targets Proxmox VE 9"
    exec {INSTALL_LOCK}>/run/lock/loft-proxmox.lock
    flock -n "$INSTALL_LOCK" || fail "Another loft installer is running on this host"
    prompt TAG "Published release tag (not a branch)" v0.1.3
    [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Use a version tag such as v0.1.0"
    prompt PI "Pi's reserved LAN IPv4 address" ""
    ipv4 "$PI" || fail "Invalid Pi address"
    local detected_bridge disks_listing templates_listing detected_storage detected_templates ids
    detected_bridge=$(recommended_bridge) || fail "Cannot detect a usable bridge"
    echo "Available bridges:"
    list_bridges
    prompt BRIDGE "LAN bridge (detected recommendation; override if needed)" "$detected_bridge"
    [[ "$BRIDGE" =~ ^[a-zA-Z0-9_-]+$ ]] || fail "Invalid bridge"
    bridge_exists "$BRIDGE" || fail "$BRIDGE is not a Linux bridge"
    disks_listing=$(pvesm status --content rootdir) || fail "Cannot query container storage"
    echo "$disks_listing"
    detected_storage=$(recommended_storage "$disks_listing" local-lvm) || fail "No active storage supports container disks"
    prompt STORAGE "Container disk storage (detected recommendation; override if needed)" "$detected_storage"
    templates_listing=$(pvesm status --content vztmpl) || fail "Cannot query template storage"
    echo "$templates_listing"
    detected_templates=$(recommended_storage "$templates_listing" local) || fail "No active storage supports templates"
    prompt TEMPLATE_STORAGE "Template storage (detected recommendation; override if needed)" "$detected_templates"
    for value in "$STORAGE" "$TEMPLATE_STORAGE"; do
        [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || fail "Invalid storage name"
    done
    pvesm status --storage "$STORAGE" --content rootdir | awk 'NR>1 && $3=="active"{found=1} END{exit !found}' ||
        fail "$STORAGE must be active and support rootdir"
    pvesm status --storage "$TEMPLATE_STORAGE" --content vztmpl | awk 'NR>1 && $3=="active"{found=1} END{exit !found}' ||
        fail "$TEMPLATE_STORAGE must be active and support templates"
    ids=$(recommended_ids) || fail "Cannot query cluster-wide VM/CT IDs"
    local detected_adsb detected_hub
    detected_adsb=$(head -n 1 <<< "$ids")
    detected_hub=$(tail -n 1 <<< "$ids")
    prompt ADSB_ID "New ADS-B CT ID (unused cluster-wide)" "$detected_adsb"
    if [[ "$ADSB_ID" == "$detected_hub" ]]; then detected_hub=$detected_adsb; fi
    prompt HUB_ID "New SDR Hub CT ID (unused cluster-wide)" "$detected_hub"
    [[ "$ADSB_ID" =~ ^[1-9][0-9]{2,8}$ && "$HUB_ID" =~ ^[1-9][0-9]{2,8}$ && "$ADSB_ID" != "$HUB_ID" ]] ||
        fail "Use distinct CT IDs >=100"
    for id in "$ADSB_ID" "$HUB_ID"; do
        pvesh get /cluster/nextid --vmid "$id" --output-format json >/dev/null ||
            fail "VM/CT ID $id is unavailable in the cluster"
        if pct config "$id" >/dev/null 2>&1; then fail "CT $id already exists; nothing overwritten"; fi
        if [[ -e "/etc/pve/qemu-server/$id.conf" ]]; then fail "VM $id already exists"; fi
    done
    echo "Create two UNPRIVILEGED Debian 13 LXCs on $BRIDGE, using DHCP:"
    echo "  $ADSB_ID: ADS-B, 2 cores / 2 GiB RAM / 16 GiB disk"
    echo "  $HUB_ID: SDR Hub, 2 cores / 4 GiB RAM / 24 GiB disk"
    echo "  Container storage: $STORAGE; template storage: $TEMPLATE_STORAGE"
    echo "  Release: $TAG; Pi: $PI (Beast 30005, RTL-TCP 1234)"
    echo "The Pi will not be modified. No USB passthrough, host Docker or privileged fallback."
    echo "If either installation fails, only CTs marked as owned by this run will be removed."
    confirm_create

    WORK=$(mktemp -d -t sdrhub-install.XXXXXXXX)
    INSTALL_IDS=()
    INSTALL_MARKER="loft-install:${WORK##*/}"
    INSTALL_COMPLETE=false
    trap 'finish_install "$?"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
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
        pvesh get /cluster/nextid --vmid "$id" --output-format json >/dev/null ||
            fail "VM/CT ID $id was claimed while downloading; choose another ID and retry"
        # Track partial creates too, but delete only if the unique marker is present.
        INSTALL_IDS+=("$id")
        pct create "$id" "$TEMPLATE_STORAGE:vztmpl/$template" --hostname "loft-$role" \
            --description "$INSTALL_MARKER" \
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
    INSTALL_COMPLETE=true
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
