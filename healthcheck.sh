#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
MAPS_DIR="$SCRIPT_DIR/maps"
LOG="$SCRIPT_DIR/healthcheck.log"

for map_dir in "$MAPS_DIR"/*/; do
    [[ -d "$map_dir" ]] || continue
    map=$(basename "$map_dir")
    conf="$map_dir/map.conf"
    [[ -f "$conf" ]] || continue

    service_name="ark-${map,,}.service"
    if ! systemctl is-enabled "$service_name" &>/dev/null; then
        continue
    fi

    if ! systemctl is-active "$service_name" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [HEAL] $map is down, restarting..." >> "$LOG"
        systemctl restart "$service_name" 2>/dev/null || true
    fi
done
