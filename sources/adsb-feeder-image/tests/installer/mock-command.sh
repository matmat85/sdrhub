#!/bin/bash
set -euo pipefail
case "$(basename "$0")" in
    docker)
        if [[ "${1:-}" == --version ]]; then
            echo "Docker version 29.1.3, build test"
        elif [[ "${1:-}" == compose && "${2:-}" == version ]]; then
            echo "Docker Compose version v2.40.3"
        else
            echo "Unexpected Docker invocation in installer test: $*" >&2
            exit 1
        fi
        ;;
    systemctl|systemd-run)
        printf '%s %s\n' "$(basename "$0")" "$*" >> /tmp/installer-services.log
        ;;
    *) exit 1 ;;
esac
