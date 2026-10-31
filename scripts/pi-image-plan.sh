#!/bin/bash
set -euo pipefail

plan_pi_image() {
    local root=$1 previous=$2 status
    if [[ -z "$previous" ]]; then
        echo build
        return
    fi
    git -C "$root" rev-parse --verify "refs/tags/$previous^{commit}" >/dev/null || return "$?"
    # These are the files copied into or executed while constructing the Pi image.
    if git -C "$root" diff --quiet "refs/tags/$previous" HEAD -- \
        pi sources/adsb-feeder-image ':(exclude)pi/*.md'; then
        echo "$previous"
    else
        status=$?
        [[ "$status" == 1 ]] || return "$status"
        echo build
    fi
}

main() {
    local root previous
    root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
    previous=$(gh api "repos/${GITHUB_REPOSITORY:?}/releases?per_page=100" --jq '
        [.[] | select(.draft == false)
         | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
         | select(any(.assets[]; .name == "loft-pi.img.xz"))
         | select(any(.assets[]; .name == "SHA256SUMS"))]
        | sort_by(.published_at) | reverse | .[0].tag_name // empty')
    plan_pi_image "$root" "$previous"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
