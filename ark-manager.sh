#!/usr/bin/env bash
#═══════════════════════════════════════════════════════════════════════════════
#  ARK: Survival Ascended — Linux Server Manager  v2.2
#  A clean, map-centered management tool for ASA dedicated servers.
#  https://github.com/lewisQ17/ARK-Server
#═══════════════════════════════════════════════════════════════════════════════
set -u

VERSION="2.2"
export LC_ALL=C.UTF-8 LANG=C.UTF-8

#───────────────────────────── Paths ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
MAPS_DIR="$SCRIPT_DIR/maps"
MAPS_CONF="$CONFIG_DIR/maps.conf"
DEFAULTS_CONF="$CONFIG_DIR/server-defaults.conf"
OPT_CONF="$CONFIG_DIR/optimization.conf"
RCON_SCRIPT="$SCRIPT_DIR/rcon.py"

SERVER_DIR="$SCRIPT_DIR/server-files"
STEAMCMD_DIR="$SCRIPT_DIR/steamcmd"
PROTON_VERSION="GE-Proton10-4"
PROTON_DIR="$SCRIPT_DIR/$PROTON_VERSION"

STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$PROTON_VERSION/$PROTON_VERSION.tar.gz"
ARK_APPID=2430930

#───────────────────────────── Colors ($'...' = real ANSI bytes) ──────────────
R=$'\e[0m'
BLD=$'\e[1m'
DIM=$'\e[2m'
RED=$'\e[31m'
GRN=$'\e[32m'
YEL=$'\e[33m'
BLU=$'\e[34m'
MAG=$'\e[35m'
CYN=$'\e[36m'
WHT=$'\e[97m'
GRY=$'\e[90m'
BG_GRN=$'\e[42m'
BG_RED=$'\e[41m'
BG_YEL=$'\e[43m'
BG_BLU=$'\e[44m'

#───────────────────────────── Known Maps ─────────────────────────────────────
declare -A MAP_NAMES=(
    ["TheIsland"]="TheIsland_WP"
    ["ScorchedEarth"]="ScorchedEarth_WP"
    ["Aberration"]="Aberration_WP"
    ["Extinction"]="Extinction_WP"
    ["TheCenter"]="TheCenter_WP"
    ["Ragnarok"]="Ragnarok_WP"
    ["Valguero"]="Valguero_WP"
    ["CrystalIsles"]="CrystalIsles_WP"
    ["LostIsland"]="LostIsland_WP"
    ["Fjordur"]="Fjordur_WP"
    ["GenesisPart1"]="Genesis_WP"
    ["GenesisPart2"]="Gen2_WP"
)

# Global feedback variable — shown once on next dashboard refresh
FEEDBACK=""

#═══════════════════════════════════════════════════════════════════════════════
#  UTILITY FUNCTIONS
#═══════════════════════════════════════════════════════════════════════════════

log_info()  { echo "${CYN}${BLD}  ℹ ${R} $*"; }
log_ok()    { echo "${GRN}${BLD}  ✔ ${R} $*"; }
log_warn()  { echo "${YEL}${BLD}  ⚠ ${R} $*"; }
log_err()   { echo "${RED}${BLD}  ✖ ${R} $*"; }

separator() { echo "  ${GRY}──────────────────────────────────────────────────────────────────────────────${R}"; }
thin_sep()  { echo "  ${GRY}╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌${R}"; }

# Pad text to exact visible display width (handles multi-byte chars correctly)
pad() {
    local w="$1" t="${2:0:$1}"
    printf "%s" "$t"
    local n=$(( w - ${#t} ))
    (( n > 0 )) && printf "%*s" "$n" ""
}

confirm() {
    local msg="${1:-Continue?}"
    echo -n "  ${YEL}${msg} [y/N]: ${R}"
    read -r ans
    [[ "$ans" =~ ^[Yy] ]]
}

press_enter() {
    echo ""
    echo -n "  ${DIM}Press Enter to continue...${R}"
    read -r
}

read_conf_value() {
    local file="$1" key="$2" default="${3:-}"
    local val
    val=$(grep -E "^${key}=" "$file" 2>/dev/null | tail -1 | cut -d'=' -f2-)
    echo "${val:-$default}"
}

write_conf_value() {
    local file="$1" key="$2" value="$3"
    if grep -qE "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  DEPENDENCY CHECK
#═══════════════════════════════════════════════════════════════════════════════

check_dependencies() {
    local missing=()
    local deps=(wget tar grep python3 curl cron)
    if command -v apt-get &>/dev/null; then
        for pkg in libc6:i386 libstdc++6:i386 libncursesw6:i386 libfreetype6:i386 libfreetype6:amd64; do
            dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || missing+=("$pkg")
        done
    fi
    for cmd in "${deps[@]}"; do
        if [[ "$cmd" == "cron" ]]; then
            command -v crontab &>/dev/null || missing+=("cron")
        else
            command -v "$cmd" &>/dev/null || missing+=("$cmd")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        log_warn "Missing packages: ${missing[*]}"
        if confirm "Install them now? (requires sudo)"; then
            if command -v apt-get &>/dev/null; then
                sudo dpkg --add-architecture i386 2>/dev/null || true
                sudo apt-get update -qq
                sudo apt-get install -y "${missing[@]}"
            fi
            log_ok "Dependencies installed."
        fi
    fi
}

check_cpu_flags() {
    if ! grep -qw avx /proc/cpuinfo || ! grep -qw avx2 /proc/cpuinfo; then
        log_err "CPU missing AVX/AVX2 support. Set CPU type to 'host' in your hypervisor."
        return 1
    fi
    return 0
}

#═══════════════════════════════════════════════════════════════════════════════
#  INSTALL / UPDATE
#═══════════════════════════════════════════════════════════════════════════════

install_server() {
    clear
    log_info "Installing / Updating ARK server..."
    check_cpu_flags || return 1

    local running=0
    for map_dir in "$MAPS_DIR"/*/; do
        [[ -d "$map_dir" ]] || continue
        local mname; mname=$(basename "$map_dir")
        if is_map_running "$mname"; then
            log_err "Map '${BLD}$mname${R}' is running. Stop all maps first."
            ((running++))
        fi
    done
    (( running > 0 )) && return 1

    mkdir -p "$STEAMCMD_DIR" "$PROTON_DIR" "$SERVER_DIR"

    if [[ ! -f "$STEAMCMD_DIR/steamcmd.sh" ]]; then
        log_info "Downloading SteamCMD..."
        wget -q -O "$STEAMCMD_DIR/steamcmd_linux.tar.gz" "$STEAMCMD_URL"
        tar -xzf "$STEAMCMD_DIR/steamcmd_linux.tar.gz" -C "$STEAMCMD_DIR"
        rm -f "$STEAMCMD_DIR/steamcmd_linux.tar.gz"
        log_ok "SteamCMD installed."
    else
        log_ok "SteamCMD already present."
    fi

    mkdir -p "$HOME/.steam/sdk32" "$HOME/.steam/sdk64"
    ln -sf "$STEAMCMD_DIR/linux32/steamclient.so" "$HOME/.steam/sdk32/steamclient.so"
    ln -sf "$STEAMCMD_DIR/linux64/steamclient.so" "$HOME/.steam/sdk64/steamclient.so"

    if [[ ! -d "$PROTON_DIR/files" ]]; then
        log_info "Downloading ${BLD}$PROTON_VERSION${R}..."
        wget -q --show-progress -O "$PROTON_DIR/$PROTON_VERSION.tar.gz" "$PROTON_URL"
        tar -xzf "$PROTON_DIR/$PROTON_VERSION.tar.gz" -C "$PROTON_DIR" --strip-components=1
        rm -f "$PROTON_DIR/$PROTON_VERSION.tar.gz"
        log_ok "Proton installed."
    else
        log_ok "Proton already present."
    fi

    log_info "Downloading / Updating ARK (AppID ${BLD}$ARK_APPID${R})..."
    "$STEAMCMD_DIR/steamcmd.sh" \
        +force_install_dir "$SERVER_DIR" \
        +login anonymous \
        +@sSteamCmdForcePlatformType windows \
        +app_update $ARK_APPID validate \
        +quit

    local pdb_count
    pdb_count=$(find "$SERVER_DIR" -name "*.pdb" 2>/dev/null | wc -l)
    (( pdb_count > 0 )) && {
        log_info "Removing ${BLD}$pdb_count${R} .pdb debug files..."
        find "$SERVER_DIR" -name "*.pdb" -delete
    }

    local compat_dir="$SERVER_DIR/steamapps/compatdata/$ARK_APPID"
    if [[ ! -d "$compat_dir/pfx" ]]; then
        log_info "Initializing Proton prefix..."
        mkdir -p "$compat_dir"
        cp -r "$PROTON_DIR/files/share/default_pfx/." "$compat_dir/"
    fi

    apply_optimizations
    mkdir -p "$HOME/.config/protonfixes"

    log_ok "Server installation/update complete!"
    echo ""
    echo "  ${GRN}Next step:${R} Use ${BLD}'Add Map'${R} to create your first map."
    press_enter
}

#═══════════════════════════════════════════════════════════════════════════════
#  MAP STATUS HELPERS
#═══════════════════════════════════════════════════════════════════════════════

get_maps() {
    local maps=()
    for d in "$MAPS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        maps+=("$(basename "$d")")
    done
    echo "${maps[@]}"
}

is_map_running() {
    local map="$1"
    local save_dir
    save_dir=$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")
    pgrep -f "ArkAscendedServer.exe.*AltSaveDirectoryName=${save_dir}" &>/dev/null
}

get_map_pid() {
    local map="$1"
    local save_dir
    save_dir=$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")
    pgrep -f "ArkAscendedServer.exe.*AltSaveDirectoryName=${save_dir}" 2>/dev/null | head -1
}

get_player_count() {
    local map="$1"
    is_map_running "$map" || { echo "0"; return; }
    # Cache for 30 seconds (RCON call is slow)
    local cache_file="/tmp/.ark-players-${map}"
    if [[ -f "$cache_file" ]]; then
        local age
        age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
        if (( age < 30 )); then
            cat "$cache_file"
            return
        fi
    fi
    local rcon_port admin_pw
    rcon_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "RCONPort" "27020")
    admin_pw=$(read_conf_value "$MAPS_DIR/$map/map.conf" "AdminPassword" "")
    [[ -z "$admin_pw" ]] && admin_pw=$(read_conf_value "$DEFAULTS_CONF" "DefaultAdminPassword" "")
    local count
    count=$(timeout 5 python3 "$RCON_SCRIPT" "localhost:$rcon_port" -p "$admin_pw" -c "ListPlayers" 2>/dev/null | grep -c "^[0-9]" || true)
    count="${count:-0}"
    echo "$count" | tee "$cache_file"
}

check_map_health() {
    local map="$1"
    is_map_running "$map" || { echo "STOPPED"; return; }
    local pid; pid=$(get_map_pid "$map")
    [[ -z "$pid" ]] && { echo "CRASHED"; return; }
    local state; state=$(ps -o state= -p "$pid" 2>/dev/null || echo "?")
    case "$state" in
        Z*) echo "ZOMBIE" ;;
        T*) echo "FROZEN" ;;
        *)
            local game_port
            game_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "GamePort" "7777")
            if ss -lunp 2>/dev/null | grep -q ":${game_port} "; then echo "HEALTHY"; else echo "DEGRADED"; fi
            ;;
    esac
}

get_map_uptime() {
    local map="$1"
    local pid; pid=$(get_map_pid "$map")
    [[ -z "$pid" ]] && { echo "-"; return; }
    local elapsed; elapsed=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -z "$elapsed" ]] && { echo "-"; return; }
    local d=$(( elapsed / 86400 )) h=$(( (elapsed % 86400) / 3600 )) m=$(( (elapsed % 3600) / 60 ))
    if (( d > 0 )); then echo "${d}d ${h}h"
    elif (( h > 0 )); then echo "${h}h ${m}m"
    else echo "${m}m"
    fi
}

# RAM per map — uses systemd cgroup (accurate) or fallback to process tree
get_map_memory() {
    local map="$1"
    is_map_running "$map" || { echo "-"; return; }

    # Method 1: systemd cgroup (all processes in service)
    local service="ark-${map,,}.service"
    local bytes
    bytes=$(systemctl show "$service" --property=MemoryCurrent 2>/dev/null | cut -d= -f2)
    if [[ "$bytes" =~ ^[0-9]+$ ]] && (( bytes > 1048576 )); then
        local mb=$(( bytes / 1048576 ))
        if (( mb > 1024 )); then
            printf "%.1fG" "$(awk "BEGIN{printf \"%.1f\", $mb/1024}")"
        else
            echo "${mb}M"
        fi
        return
    fi

    # Method 2: Sum RSS of all matching processes
    local save_dir; save_dir=$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")
    local total_kb=0
    while IFS= read -r pid; do
        local rss; rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
        (( total_kb += ${rss:-0} ))
    done < <(pgrep -f "AltSaveDirectoryName=${save_dir}" 2>/dev/null)
    (( total_kb == 0 )) && { echo "-"; return; }
    local mb=$(( total_kb / 1024 ))
    if (( mb > 1024 )); then
        printf "%.1fG" "$(awk "BEGIN{printf \"%.1f\", $mb/1024}")"
    else
        echo "${mb}M"
    fi
}

# CPU per map — sum %cpu of all related processes
get_map_cpu() {
    local map="$1"
    is_map_running "$map" || { echo "-"; return; }

    # Method 1: systemd cgroup PIDs
    local service="ark-${map,,}.service"
    local cgroup
    cgroup=$(systemctl show "$service" --property=ControlGroup 2>/dev/null | cut -d= -f2)
    if [[ -n "$cgroup" && -f "/sys/fs/cgroup${cgroup}/cgroup.procs" ]]; then
        local total
        total=$(cat "/sys/fs/cgroup${cgroup}/cgroup.procs" 2>/dev/null | \
            xargs -I{} ps -o %cpu= -p {} 2>/dev/null | \
            awk '{s+=$1}END{printf "%.0f", s}')
        echo "${total:-0}%"
        return
    fi

    # Method 2: pgrep
    local save_dir; save_dir=$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")
    local total
    total=$(pgrep -f "AltSaveDirectoryName=${save_dir}" 2>/dev/null | \
        xargs -I{} ps -o %cpu= -p {} 2>/dev/null | \
        awk '{s+=$1}END{printf "%.0f", s}' 2>/dev/null)
    echo "${total:-0}%"
}

# Check if server is externally joinable (real network test, cached 15s)
check_server_queryable() {
    local map="$1"
    is_map_running "$map" || { echo "-"; return; }

    # Cache result for 15 seconds
    local cache_file="/tmp/.ark-join-${map}"
    if [[ -f "$cache_file" ]]; then
        local age
        age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
        if (( age < 15 )); then
            cat "$cache_file"
            return
        fi
    fi

    local game_port query_port rcon_port
    game_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "GamePort" "7777")
    query_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "QueryPort" "27015")
    rcon_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "RCONPort" "27020")

    local server_ip
    server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -z "$server_ip" ]] && { echo "?" | tee "$cache_file"; return; }

    local result="YES"

    # 1) All ports must be bound on 0.0.0.0 (accessible from network)
    ss -lunp 2>/dev/null | grep ":${game_port} " | grep -q "0\.0\.0\.0" || result="NO"
    [[ "$result" == "YES" ]] && { ss -lunp 2>/dev/null | grep ":${query_port} " | grep -q "0\.0\.0\.0" || result="NO"; }
    [[ "$result" == "YES" ]] && { ss -tlnp 2>/dev/null | grep ":${rcon_port} " | grep -q "0\.0\.0\.0" || result="NO"; }

    # 2) Firewall must allow game port
    if [[ "$result" == "YES" ]] && command -v ufw &>/dev/null; then
        local ufw_out
        ufw_out=$(sudo -n ufw status 2>/dev/null || echo "")
        if echo "$ufw_out" | grep -q "Status: active"; then
            echo "$ufw_out" | grep -qE "${game_port}" || result="NO"
        fi
    fi

    # 3) TCP connect to RCON on server's network IP (proves real reachability)
    if [[ "$result" == "YES" ]]; then
        timeout 1 bash -c "echo >/dev/tcp/${server_ip}/${rcon_port}" 2>/dev/null || result="NO"
    fi

    echo "$result" | tee "$cache_file"
}

# Check if map is included in groep start/stop
is_batch_enabled() {
    local map="$1"
    local val
    val=$(read_conf_value "$MAPS_DIR/$map/map.conf" "BatchEnabled" "true")
    [[ "$val" == "true" ]]
}

# Check if systemd auto-start is enabled
is_autostart_enabled() {
    local map="$1"
    local service="ark-${map,,}.service"
    systemctl is-enabled "$service" 2>/dev/null | grep -q "enabled"
}

#═══════════════════════════════════════════════════════════════════════════════
#  DASHBOARD (live — refreshes every 2s, options always visible)
#═══════════════════════════════════════════════════════════════════════════════

show_dashboard() {
    clear
    local maps; maps=( $(get_maps) )

    # Header
    echo ""
    echo "  ${BLD}${BLU}╔══════════════════════════════════════════════════════════════════════════════╗${R}"
    echo "  ${BLD}${BLU}║${R}  ${BLD}${WHT}  🦖  ARK: Survival Ascended — Server Manager${R}  ${DIM}v${VERSION}${R}                    ${BLD}${BLU}║${R}"
    echo "  ${BLD}${BLU}╚══════════════════════════════════════════════════════════════════════════════╝${R}"
    echo ""

    # System info
    local cpu_use mem_total mem_used disk_free host_uptime
    cpu_use=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1 || echo "?")
    mem_total=$(free -g 2>/dev/null | awk '/Mem:/{print $2}' || echo "?")
    mem_used=$(free -g 2>/dev/null | awk '/Mem:/{print $3}' || echo "?")
    disk_free=$(df -h "$SCRIPT_DIR" 2>/dev/null | awk 'NR==2{print $4}' || echo "?")
    host_uptime=$(uptime -p 2>/dev/null | sed 's/up //' || echo "?")

    echo "  ${GRY}┌─ System ─────────────────────────────────────────────────────────────────────┐${R}"
    printf "  ${GRY}│${R}  CPU ${BLD}%s%%${R}  ${GRY}│${R}  RAM ${BLD}%sG${R}/%sG  ${GRY}│${R}  Disk ${BLD}%s${R} free  ${GRY}│${R}  Up ${BLD}%s${R}\n" \
        "$cpu_use" "$mem_used" "$mem_total" "$disk_free" "$host_uptime"
    echo "  ${GRY}└──────────────────────────────────────────────────────────────────────────────┘${R}"
    echo ""

    if (( ${#maps[@]} == 0 )); then
        echo "  ${DIM}No maps configured yet. Use ${WHT}Add Map${DIM} to get started.${R}"
    else
        # Table header — fixed column widths for perfect alignment
        printf "  ${BLD}${WHT}%s %s %s %s %s %s %s %s %s${R}\n" \
            "$(pad 14 "MAP")" "$(pad 10 "STATUS")" "$(pad 9 "HEALTH")" \
            "$(pad 8 "PLAYERS")" "$(pad 7 "UPTIME")" "$(pad 6 "RAM")" \
            "$(pad 5 "CPU")" "$(pad 4 "JOIN")" "$(pad 4 "AUTO")"
        separator

        for map in "${maps[@]}"; do
            # MAP column
            local p_map; p_map="$(pad 14 "$map")"

            # STATUS column
            local status_col
            if is_map_running "$map"; then
                status_col="${GRN}${BLD}$(pad 10 "● ONLINE")${R}"
            else
                status_col="${RED}$(pad 10 "● OFFLINE")${R}"
            fi

            # HEALTH column
            local health_raw health_col
            health_raw=$(check_map_health "$map")
            case "$health_raw" in
                HEALTHY)  health_col="${GRN}$(pad 9 "$health_raw")${R}" ;;
                DEGRADED) health_col="${YEL}$(pad 9 "$health_raw")${R}" ;;
                CRASHED|ZOMBIE|FROZEN) health_col="${RED}$(pad 9 "$health_raw")${R}" ;;
                *)        health_col="${DIM}$(pad 9 "$health_raw")${R}" ;;
            esac

            # PLAYERS column
            local p_players
            if is_map_running "$map"; then
                local pc max_p
                pc=$(get_player_count "$map" 2>/dev/null || echo "?")
                max_p=$(read_conf_value "$MAPS_DIR/$map/map.conf" "MaxPlayers" "70")
                p_players="$(pad 8 "${pc}/${max_p}")"
            else
                p_players="${DIM}$(pad 8 "-")${R}"
            fi

            # UPTIME, RAM, CPU columns
            local p_uptime p_ram p_cpu
            p_uptime="$(pad 7 "$(get_map_uptime "$map")")"
            p_ram="$(pad 6 "$(get_map_memory "$map")")"
            p_cpu="$(pad 5 "$(get_map_cpu "$map")")"

            # JOIN column — ✔ or ✖
            local join_col
            if is_map_running "$map"; then
                local join_raw
                join_raw=$(check_server_queryable "$map")
                if [[ "$join_raw" == "YES" ]]; then
                    join_col="${GRN}$(pad 4 "✔")${R}"
                else
                    join_col="${RED}$(pad 4 "✖")${R}"
                fi
            else
                join_col="${DIM}$(pad 4 "-")${R}"
            fi

            # AUTO column — YES/NO
            local auto_col
            if is_autostart_enabled "$map" 2>/dev/null; then
                auto_col="${GRN}$(pad 4 "YES")${R}"
            else
                auto_col="${RED}$(pad 4 "NO")${R}"
            fi

            # Print row
            echo "  ${p_map} ${status_col} ${health_col} ${p_players} ${p_uptime} ${p_ram} ${p_cpu} ${join_col} ${auto_col}"
        done
    fi
    echo ""

    # Show feedback if any
    if [[ -n "$FEEDBACK" ]]; then
        thin_sep
        echo "  $FEEDBACK"
        FEEDBACK=""
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  ADD MAP
#═══════════════════════════════════════════════════════════════════════════════

add_map() {
    clear
    echo ""
    echo "  ${BLD}${MAG}═══ Add New Map ═══${R}"
    echo ""

    local i=1
    local map_keys=()
    for key in $(echo "${!MAP_NAMES[@]}" | tr ' ' '\n' | sort); do
        printf "  ${CYN}%2d${R}) %-20s  ${DIM}(%s)${R}\n" "$i" "$key" "${MAP_NAMES[$key]}"
        map_keys+=("$key")
        ((i++))
    done
    printf "  ${CYN}%2d${R}) ${YEL}Custom map name${R}\n" "$i"
    echo ""
    echo "  ${DIM} 0) Back${R}"
    echo ""
    echo -n "  ${WHT}Select map number: ${R}"
    read -r choice

    [[ "$choice" == "0" || -z "$choice" ]] && return 0

    local display_name internal_name
    if (( choice > 0 && choice <= ${#map_keys[@]} )) 2>/dev/null; then
        display_name="${map_keys[$((choice-1))]}"
        internal_name="${MAP_NAMES[$display_name]}"
    elif (( choice == i )) 2>/dev/null; then
        echo -n "  ${WHT}Display name (e.g. MyMap): ${R}"
        read -r display_name
        [[ -z "$display_name" ]] && return 0
        echo -n "  ${WHT}Internal map name (e.g. MyMap_WP): ${R}"
        read -r internal_name
        [[ -z "$internal_name" ]] && return 0
    else
        FEEDBACK="${RED}${BLD}✖${R} Invalid selection."
        return 1
    fi

    if [[ -d "$MAPS_DIR/$display_name" ]]; then
        FEEDBACK="${RED}${BLD}✖${R} Map '${BLD}$display_name${R}' already exists."
        return 1
    fi

    # Defaults
    local def_port def_qport def_rport def_maxp def_adminpw
    def_port=$(read_conf_value "$DEFAULTS_CONF" "DefaultGamePort" "7777")
    def_qport=$(read_conf_value "$DEFAULTS_CONF" "DefaultQueryPort" "27015")
    def_rport=$(read_conf_value "$DEFAULTS_CONF" "DefaultRCONPort" "27020")
    def_maxp=$(read_conf_value "$DEFAULTS_CONF" "DefaultMaxPlayers" "70")
    def_adminpw=$(read_conf_value "$DEFAULTS_CONF" "DefaultAdminPassword" "")

    # Auto-increment ports
    local existing_maps; existing_maps=( $(get_maps) )
    if (( ${#existing_maps[@]} > 0 )); then
        local max_gport=0 max_qport=0 max_rport=0
        for em in "${existing_maps[@]}"; do
            local gp qp rp
            gp=$(read_conf_value "$MAPS_DIR/$em/map.conf" "GamePort" "0")
            qp=$(read_conf_value "$MAPS_DIR/$em/map.conf" "QueryPort" "0")
            rp=$(read_conf_value "$MAPS_DIR/$em/map.conf" "RCONPort" "0")
            (( gp > max_gport )) && max_gport=$gp
            (( qp > max_qport )) && max_qport=$qp
            (( rp > max_rport )) && max_rport=$rp
        done
        def_port=$(( max_gport + 2 ))
        def_qport=$(( max_qport + 1 ))
        def_rport=$(( max_rport + 1 ))
    fi

    echo ""
    echo "  ${BLD}Configure ${CYN}${display_name}${R}${BLD}:${R}  ${DIM}(Enter = default, 0 = cancel)${R}"
    thin_sep

    local game_port query_port rcon_port max_players admin_pw server_pw
    echo -n "  ${WHT}Game Port${R} ${DIM}[$def_port]${R}: "; read -r input; [[ "$input" == "0" ]] && return 0; game_port="${input:-$def_port}"
    echo -n "  ${WHT}Query Port${R} ${DIM}[$def_qport]${R}: "; read -r input; [[ "$input" == "0" ]] && return 0; query_port="${input:-$def_qport}"
    echo -n "  ${WHT}RCON Port${R} ${DIM}[$def_rport]${R}: "; read -r input; [[ "$input" == "0" ]] && return 0; rcon_port="${input:-$def_rport}"
    echo -n "  ${WHT}Max Players${R} ${DIM}[$def_maxp]${R}: "; read -r input; [[ "$input" == "0" ]] && return 0; max_players="${input:-$def_maxp}"
    echo -n "  ${WHT}Admin Password${R} ${DIM}[$def_adminpw]${R}: "; read -r input; [[ "$input" == "0" ]] && return 0; admin_pw="${input:-$def_adminpw}"
    echo -n "  ${WHT}Server Password${R} ${DIM}[empty=public]${R}: "; read -r server_pw; [[ "$server_pw" == "0" ]] && return 0

    mkdir -p "$MAPS_DIR/$display_name/backups"

    cat > "$MAPS_DIR/$display_name/map.conf" <<EOF
MapName=$internal_name
DisplayName=$display_name
SaveDir=$display_name
GamePort=$game_port
QueryPort=$query_port
RCONPort=$rcon_port
MaxPlayers=$max_players
AdminPassword=$admin_pw
ServerPassword=$server_pw
CustomStartParams=$(read_conf_value "$DEFAULTS_CONF" "DefaultStartParams" "-NoBattlEye -crossplay -NoHangDetection")
ClusterID=$(read_conf_value "$DEFAULTS_CONF" "ClusterID" "")
BatchEnabled=true
EOF

    # Create empty mods.conf
    echo "# Mod configuration for $display_name" > "$MAPS_DIR/$display_name/mods.conf"
    echo "# Format: id|name|enabled" >> "$MAPS_DIR/$display_name/mods.conf"

    create_optimized_game_settings "$MAPS_DIR/$display_name" "high"
    [[ ! -f "$MAPS_DIR/$display_name/Game.ini" ]] && touch "$MAPS_DIR/$display_name/Game.ini"
    echo "${display_name}|${internal_name}|enabled" >> "$MAPS_CONF"
    create_systemd_service "$display_name"
    open_firewall_ports "$game_port" "$query_port" "$rcon_port"

    FEEDBACK="${GRN}${BLD}✔${R} Map '${BLD}$display_name${R}' created and ready!"
}

#═══════════════════════════════════════════════════════════════════════════════
#  GAME SETTINGS GENERATION
#═══════════════════════════════════════════════════════════════════════════════

create_optimized_game_settings() {
    local map_dir="$1"
    local preset="${2:-high}"
    local ini_file="$map_dir/GameUserSettings.ini"

    [[ -f "$map_dir/map.conf" ]] && write_conf_value "$map_dir/map.conf" "GraphicsPreset" "$preset"

    local xp taming harvest respawn mating baby hatch
    xp=$(read_conf_value "$DEFAULTS_CONF" "XPMultiplier" "1.0")
    taming=$(read_conf_value "$DEFAULTS_CONF" "TamingSpeedMultiplier" "1.0")
    harvest=$(read_conf_value "$DEFAULTS_CONF" "HarvestAmountMultiplier" "1.0")
    respawn=$(read_conf_value "$DEFAULTS_CONF" "ResourceRespawnPeriodMultiplier" "1.0")
    mating=$(read_conf_value "$DEFAULTS_CONF" "MatingIntervalMultiplier" "1.0")
    baby=$(read_conf_value "$DEFAULTS_CONF" "BabyMatureSpeedMultiplier" "1.0")
    hatch=$(read_conf_value "$DEFAULTS_CONF" "EggHatchSpeedMultiplier" "1.0")
    local show_loc tp cross
    show_loc=$(read_conf_value "$DEFAULTS_CONF" "ShowMapPlayerLocation" "True")
    tp=$(read_conf_value "$DEFAULTS_CONF" "AllowThirdPersonPlayer" "True")
    cross=$(read_conf_value "$DEFAULTS_CONF" "ServerCrosshair" "True")
    local admin_pw rcon_port map_name max_players
    admin_pw=$(read_conf_value "$map_dir/map.conf" "AdminPassword" "")
    rcon_port=$(read_conf_value "$map_dir/map.conf" "RCONPort" "27020")
    map_name=$(read_conf_value "$map_dir/map.conf" "DisplayName" "ARK")
    max_players=$(read_conf_value "$map_dir/map.conf" "MaxPlayers" "70")

    cat > "$ini_file" <<GUSEOF
[ServerSettings]
ShowMapPlayerLocation=$show_loc
AllowThirdPersonPlayer=$tp
ServerCrosshair=$cross
ServerPassword=
ServerAdminPassword=$admin_pw
RCONEnabled=True
RCONPort=$rcon_port
TheMaxStructuresInRange=10500
OxygenSwimSpeedStatMultiplier=1
StructurePreventResourceRadiusMultiplier=1
AlwaysAllowStructurePickup=True
StructurePickupTimeAfterPlacement=30
StructurePickupHoldDuration=0.5
AllowHideDamageSourceFromLogs=True
KickIdlePlayersPeriod=3600
PerPlatformMaxStructuresMultiplier=1
AutoSavePeriodMinutes=15
MaxTamedDinos=5000
MaxTamedDinos_SoftTameLimit=5000
ItemStackSizeMultiplier=1
RCONServerGameLogBuffer=600
AllowHitMarkers=True
XPMultiplier=$xp
TamingSpeedMultiplier=$taming
HarvestAmountMultiplier=$harvest
ResourcesRespawnPeriodMultiplier=$respawn
MatingIntervalMultiplier=$mating
BabyMatureSpeedMultiplier=$baby
EggHatchSpeedMultiplier=$hatch

[ScalabilityGroups]
sg.ResolutionQuality=3
sg.ViewDistanceQuality=3
sg.AntiAliasingQuality=3
sg.ShadowQuality=3
sg.GlobalIlluminationQuality=3
sg.ReflectionQuality=3
sg.PostProcessQuality=3
sg.TextureQuality=3
sg.EffectsQuality=3
sg.FoliageQuality=3
sg.ShadingQuality=3
sg.LandscapeQuality=3

[/Script/ShooterGame.ShooterGameUserSettings]
AdvancedGraphicsQuality=3
MasterAudioVolume=0
SFXAudioVolume=0
MusicAudioVolume=0
bFilmGrain=False
bUserMotionBlur=False
bUseDFAO=True
bUseSSAO=True
bDisableBloom=False
bUseDistanceFieldAmbientOcclusion=True
bHighQualityAnisotropicFiltering=True
bEnableFootstepDecals=True
bEnableFootstepParticles=True
bEnableFluidInteraction=True
bDisableHLOD=False
bLowQualityVFX=False
PreventDetailGraphics=False
GroundClutterDensity=100
GroundClutterRadius=10000
HFSQuality=3
LODScalar=1.0
HighQualityMaterials=True
HighQualitySurfaces=True
bHighQualityLODs=True
bExtraLevelStreamingDistance=True
bEnableColorGrading=True
ScreenPercentage=100.000000
ResolutionSizeX=1920
ResolutionSizeY=1080
FrameRateLimit=0.000000
bUseVSync=False
bUseDynamicResolution=False
bUseLowQualityLevelStreaming=False
FoliageInteractionDistance=1.000000
FoliageInteractionDistanceLimit=1.000000
FoliageInteractionQuantityLimit=1.000000
GUI3DWidgetQuality=100.000000
AudioQualityLevel=2
ActiveLingeringWorldTiles=20
ClientNetQuality=3
bDisableShadows=False

[SessionSettings]
SessionName=${map_name}

[/Script/Engine.GameSession]
MaxPlayers=$max_players

[/Script/Engine.GameUserSettings]
bUseDesiredScreenHeight=False
GUSEOF
}

#═══════════════════════════════════════════════════════════════════════════════
#  GRAPHICS PRESETS
#═══════════════════════════════════════════════════════════════════════════════

apply_graphics_preset() {
    local map="$1" preset="$2"
    local ini="$MAPS_DIR/$map/GameUserSettings.ini"
    [[ ! -f "$ini" ]] && { log_err "GameUserSettings.ini not found for '$map'."; return 1; }

    local sg_val adv_q res_x res_y scr_pct fps_lim
    local b_dfao b_ssao b_bloom b_dist_ao b_hi_aniso b_foot_dec b_foot_part b_fluid
    local b_low_vfx b_prev_det gnd_dens gnd_rad hfs_q lod_s
    local b_hi_mat b_hi_surf b_hi_lod b_ext_stream b_color_grad b_dyn_res b_low_stream
    local fol_dist fol_limit fol_qty gui3d_q aud_q tiles b_dis_shad

    case "$preset" in
        low)
            sg_val=0; adv_q=0; res_x=640; res_y=480; scr_pct="0.100000"; fps_lim="30.000000"
            b_dfao=False; b_ssao=False; b_bloom=True; b_dist_ao=False; b_hi_aniso=False
            b_foot_dec=False; b_foot_part=False; b_fluid=False; b_low_vfx=True; b_prev_det=True
            gnd_dens=0; gnd_rad=0; hfs_q=0; lod_s="0.5"
            b_hi_mat=False; b_hi_surf=False; b_hi_lod=False; b_ext_stream=False; b_color_grad=False
            b_dyn_res=False; b_low_stream=True
            fol_dist="0.010000"; fol_limit="0.100000"; fol_qty="0.100000"
            gui3d_q="0.000000"; aud_q=0; tiles=5; b_dis_shad=True ;;
        medium)
            sg_val=2; adv_q=2; res_x=1280; res_y=720; scr_pct="75.000000"; fps_lim="60.000000"
            b_dfao=False; b_ssao=True; b_bloom=False; b_dist_ao=False; b_hi_aniso=False
            b_foot_dec=True; b_foot_part=True; b_fluid=False; b_low_vfx=False; b_prev_det=False
            gnd_dens=50; gnd_rad=5000; hfs_q=2; lod_s="1.0"
            b_hi_mat=False; b_hi_surf=False; b_hi_lod=False; b_ext_stream=False; b_color_grad=True
            b_dyn_res=False; b_low_stream=False
            fol_dist="0.500000"; fol_limit="1.000000"; fol_qty="0.500000"
            gui3d_q="50.000000"; aud_q=1; tiles=10; b_dis_shad=False ;;
        high)
            sg_val=3; adv_q=3; res_x=1920; res_y=1080; scr_pct="100.000000"; fps_lim="0.000000"
            b_dfao=True; b_ssao=True; b_bloom=False; b_dist_ao=True; b_hi_aniso=True
            b_foot_dec=True; b_foot_part=True; b_fluid=True; b_low_vfx=False; b_prev_det=False
            gnd_dens=100; gnd_rad=10000; hfs_q=3; lod_s="1.0"
            b_hi_mat=True; b_hi_surf=True; b_hi_lod=True; b_ext_stream=True; b_color_grad=True
            b_dyn_res=False; b_low_stream=False
            fol_dist="1.000000"; fol_limit="1.000000"; fol_qty="1.000000"
            gui3d_q="100.000000"; aud_q=2; tiles=20; b_dis_shad=False ;;
        auto)
            sg_val=3; adv_q=3; res_x=1920; res_y=1080; scr_pct="100.000000"; fps_lim="0.000000"
            b_dfao=True; b_ssao=True; b_bloom=False; b_dist_ao=True; b_hi_aniso=True
            b_foot_dec=True; b_foot_part=True; b_fluid=True; b_low_vfx=False; b_prev_det=False
            gnd_dens=100; gnd_rad=10000; hfs_q=3; lod_s="1.0"
            b_hi_mat=True; b_hi_surf=True; b_hi_lod=True; b_ext_stream=True; b_color_grad=True
            b_dyn_res=True; b_low_stream=False
            fol_dist="1.000000"; fol_limit="1.000000"; fol_qty="1.000000"
            gui3d_q="100.000000"; aud_q=2; tiles=20; b_dis_shad=False ;;
        *) log_err "Unknown preset: $preset"; return 1 ;;
    esac

    for key in ResolutionQuality ViewDistanceQuality AntiAliasingQuality ShadowQuality \
               GlobalIlluminationQuality ReflectionQuality PostProcessQuality TextureQuality \
               EffectsQuality FoliageQuality ShadingQuality LandscapeQuality; do
        sed -i "s/^sg\.${key}=.*/sg.${key}=$sg_val/" "$ini"
    done
    sed -i "s/^AdvancedGraphicsQuality=.*/AdvancedGraphicsQuality=$adv_q/" "$ini"
    sed -i "s/^bUseDFAO=.*/bUseDFAO=$b_dfao/" "$ini"
    sed -i "s/^bUseSSAO=.*/bUseSSAO=$b_ssao/" "$ini"
    sed -i "s/^bDisableBloom=.*/bDisableBloom=$b_bloom/" "$ini"
    sed -i "s/^bUseDistanceFieldAmbientOcclusion=.*/bUseDistanceFieldAmbientOcclusion=$b_dist_ao/" "$ini"
    sed -i "s/^bHighQualityAnisotropicFiltering=.*/bHighQualityAnisotropicFiltering=$b_hi_aniso/" "$ini"
    sed -i "s/^bEnableFootstepDecals=.*/bEnableFootstepDecals=$b_foot_dec/" "$ini"
    sed -i "s/^bEnableFootstepParticles=.*/bEnableFootstepParticles=$b_foot_part/" "$ini"
    sed -i "s/^bEnableFluidInteraction=.*/bEnableFluidInteraction=$b_fluid/" "$ini"
    sed -i "s/^bLowQualityVFX=.*/bLowQualityVFX=$b_low_vfx/" "$ini"
    sed -i "s/^PreventDetailGraphics=.*/PreventDetailGraphics=$b_prev_det/" "$ini"
    sed -i "s/^GroundClutterDensity=.*/GroundClutterDensity=$gnd_dens/" "$ini"
    sed -i "s/^GroundClutterRadius=.*/GroundClutterRadius=$gnd_rad/" "$ini"
    sed -i "s/^HFSQuality=.*/HFSQuality=$hfs_q/" "$ini"
    sed -i "s/^LODScalar=.*/LODScalar=$lod_s/" "$ini"
    sed -i "s/^HighQualityMaterials=.*/HighQualityMaterials=$b_hi_mat/" "$ini"
    sed -i "s/^HighQualitySurfaces=.*/HighQualitySurfaces=$b_hi_surf/" "$ini"
    sed -i "s/^bHighQualityLODs=.*/bHighQualityLODs=$b_hi_lod/" "$ini"
    sed -i "s/^bExtraLevelStreamingDistance=.*/bExtraLevelStreamingDistance=$b_ext_stream/" "$ini"
    sed -i "s/^bEnableColorGrading=.*/bEnableColorGrading=$b_color_grad/" "$ini"
    sed -i "s/^ScreenPercentage=.*/ScreenPercentage=$scr_pct/" "$ini"
    sed -i "s/^ResolutionSizeX=.*/ResolutionSizeX=$res_x/" "$ini"
    sed -i "s/^ResolutionSizeY=.*/ResolutionSizeY=$res_y/" "$ini"
    sed -i "s/^FrameRateLimit=.*/FrameRateLimit=$fps_lim/" "$ini"
    sed -i "s/^bUseDynamicResolution=.*/bUseDynamicResolution=$b_dyn_res/" "$ini"
    sed -i "s/^bUseLowQualityLevelStreaming=.*/bUseLowQualityLevelStreaming=$b_low_stream/" "$ini"
    sed -i "s/^FoliageInteractionDistance=.*/FoliageInteractionDistance=$fol_dist/" "$ini"
    sed -i "s/^FoliageInteractionDistanceLimit=.*/FoliageInteractionDistanceLimit=$fol_limit/" "$ini"
    sed -i "s/^FoliageInteractionQuantityLimit=.*/FoliageInteractionQuantityLimit=$fol_qty/" "$ini"
    sed -i "s/^GUI3DWidgetQuality=.*/GUI3DWidgetQuality=$gui3d_q/" "$ini"
    sed -i "s/^AudioQualityLevel=.*/AudioQualityLevel=$aud_q/" "$ini"
    sed -i "s/^ActiveLingeringWorldTiles=.*/ActiveLingeringWorldTiles=$tiles/" "$ini"
    sed -i "s/^bDisableShadows=.*/bDisableShadows=$b_dis_shad/" "$ini"
    [[ -f "$MAPS_DIR/$map/map.conf" ]] && write_conf_value "$MAPS_DIR/$map/map.conf" "GraphicsPreset" "$preset"

    log_ok "Graphics preset '${BLD}$preset${R}${GRN}' applied to ${BLD}$map${R}${GRN}. Restart to take effect."
}

graphics_preset_menu() {
    local map="$1"
    local current; current=$(read_conf_value "$MAPS_DIR/$map/map.conf" "GraphicsPreset" "high")
    clear
    echo ""
    echo "  ${BLD}${MAG}═══ Graphics Preset — ${CYN}$map${MAG} ═══${R}"
    thin_sep
    echo "  Current: ${BLD}${CYN}$current${R}"
    echo ""
    echo "  ${CYN}1${R}) ${RED}Low${R}       ${DIM}— Max performance, 640x480, 30fps cap${R}"
    echo "  ${CYN}2${R}) ${YEL}Medium${R}    ${DIM}— Balanced, 1280x720, 60fps cap${R}"
    echo "  ${CYN}3${R}) ${GRN}High${R}      ${DIM}— Max quality, 1920x1080, unlimited fps${R}"
    echo "  ${CYN}4${R}) ${BLU}Auto${R}      ${DIM}— High + dynamic resolution${R}"
    echo ""
    echo "  ${DIM}0) Back${R}"
    echo ""
    echo -n "  ${WHT}Choice: ${R}"
    read -r choice
    case "$choice" in
        1) apply_graphics_preset "$map" "low" ;;
        2) apply_graphics_preset "$map" "medium" ;;
        3) apply_graphics_preset "$map" "high" ;;
        4) apply_graphics_preset "$map" "auto" ;;
        0|"") return ;;
        *) log_err "Invalid choice." ;;
    esac
    sleep 1
}

#═══════════════════════════════════════════════════════════════════════════════
#  SYSTEMD & FIREWALL
#═══════════════════════════════════════════════════════════════════════════════

create_systemd_service() {
    local map="$1"
    local service_name="ark-${map,,}.service"
    local service_file="/etc/systemd/system/$service_name"
    log_info "Creating systemd service: ${BLD}$service_name${R}"
    sudo tee "$service_file" > /dev/null <<SVCEOF
[Unit]
Description=ARK ASA Server - $map
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=$(whoami)
WorkingDirectory=$SCRIPT_DIR
Environment=PROTON_LOG=1
Environment=PROTON_LOG_DIR=$HOME
ExecStart=$SCRIPT_DIR/ark-manager.sh start $map
ExecStop=$SCRIPT_DIR/ark-manager.sh stop $map
Restart=on-failure
RestartSec=30
TimeoutStartSec=300
TimeoutStopSec=180
MemoryAccounting=true
CPUAccounting=true

[Install]
WantedBy=multi-user.target
SVCEOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name" 2>/dev/null || true
    log_ok "Service '${BLD}$service_name${R}${GRN}' created."
}

open_firewall_ports() {
    local game_port="$1" query_port="$2" rcon_port="$3"
    if command -v ufw &>/dev/null; then
        sudo ufw allow "${game_port}/udp" 2>/dev/null || true
        sudo ufw allow "$(( game_port + 1 ))/udp" 2>/dev/null || true
        sudo ufw allow "${query_port}/udp" 2>/dev/null || true
        sudo ufw allow "${rcon_port}/tcp" 2>/dev/null || true
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  MOD MANAGEMENT (mods.conf per map, with names + toggle)
#═══════════════════════════════════════════════════════════════════════════════

# Fetch mod name from Steam Workshop API
fetch_mod_name() {
    local mod_id="$1"
    local name
    name=$(curl -sf --max-time 5 -X POST \
        "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/" \
        -d "itemcount=1&publishedfileids[0]=$mod_id" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d['response']['publishedfiledetails'][0].get('title',''))" 2>/dev/null)
    echo "${name:-}"
}

# Initialize mods.conf from legacy ModIDs if needed
init_mods_conf() {
    local map="$1"
    local mods_file="$MAPS_DIR/$map/mods.conf"
    [[ -f "$mods_file" ]] && return

    echo "# Mod configuration for $map" > "$mods_file"
    echo "# Format: id|name|enabled" >> "$mods_file"

    local old_ids
    old_ids=$(read_conf_value "$MAPS_DIR/$map/map.conf" "ModIDs" "")
    if [[ -n "$old_ids" ]]; then
        IFS=',' read -ra ids <<< "$old_ids"
        for id in "${ids[@]}"; do
            id=$(echo "$id" | tr -d ' ')
            [[ -z "$id" ]] && continue
            local name; name=$(fetch_mod_name "$id")
            echo "${id}|${name}|true" >> "$mods_file"
        done
    fi
}

# Get comma-separated list of enabled mod IDs
get_enabled_mod_ids() {
    local map="$1"
    local mods_file="$MAPS_DIR/$map/mods.conf"
    if [[ ! -f "$mods_file" ]]; then
        read_conf_value "$MAPS_DIR/$map/map.conf" "ModIDs" ""
        return
    fi
    local ids=()
    while IFS='|' read -r id name enabled; do
        [[ "$id" =~ ^#.*$ || -z "$id" ]] && continue
        [[ "$enabled" == "true" ]] && ids+=("$id")
    done < "$mods_file"
    local IFS=','
    echo "${ids[*]}"
}

manage_mods() {
    local map="$1"
    init_mods_conf "$map"
    local mods_file="$MAPS_DIR/$map/mods.conf"

    while true; do
        clear
        echo ""
        echo "  ${BLD}${MAG}═══ Mod Management — ${CYN}$map${MAG} ═══${R}"
        thin_sep

        # Read and display mods
        local mod_ids=() mod_names=() mod_enabled=() mod_count=0
        while IFS='|' read -r id name enabled; do
            [[ "$id" =~ ^#.*$ || -z "$id" ]] && continue
            mod_ids+=("$id")
            mod_names+=("${name:-???}")
            mod_enabled+=("$enabled")
            ((mod_count++))
        done < "$mods_file"

        if (( mod_count > 0 )); then
            echo ""
            printf "  ${BLD}${WHT}  %-4s %-12s %-30s %s${R}\n" "#" "ID" "Name" "Status"
            thin_sep
            for idx in "${!mod_ids[@]}"; do
                local stat_icon
                if [[ "${mod_enabled[$idx]}" == "true" ]]; then
                    stat_icon="${GRN}${BLD}✔ ON${R}"
                else
                    stat_icon="${RED}✖ OFF${R}"
                fi
                printf "  ${CYN}%3d${R}) %-12s %-30s %s\n" "$((idx+1))" "${mod_ids[$idx]}" "${mod_names[$idx]}" "$stat_icon"
            done
        else
            echo ""
            echo "  ${DIM}No mods installed.${R}"
        fi

        echo ""
        echo "  ${CYN}a${R}) Add mod(s)"
        echo "  ${CYN}r${R}) Remove mod"
        echo "  ${CYN}t${R}) Toggle mod on/off"
        echo "  ${CYN}n${R}) Rename mod"
        echo "  ${CYN}f${R}) Fetch all names from Steam"
        echo ""
        echo "  ${DIM}0) Back${R}"
        echo ""
        echo -n "  ${WHT}Choice: ${R}"
        read -r choice

        case "$choice" in
            a|A)
                echo -n "  ${WHT}Mod ID(s) to add (comma-separated): ${R}"
                read -r new_ids
                [[ -z "$new_ids" ]] && continue
                IFS=',' read -ra id_arr <<< "$new_ids"
                for id in "${id_arr[@]}"; do
                    id=$(echo "$id" | tr -d ' ')
                    [[ -z "$id" ]] && continue
                    # Check if already exists
                    if grep -q "^${id}|" "$mods_file" 2>/dev/null; then
                        log_warn "Mod $id already exists, skipping."
                        continue
                    fi
                    log_info "Fetching name for mod ${BLD}$id${R}..."
                    local name; name=$(fetch_mod_name "$id")
                    echo "${id}|${name}|true" >> "$mods_file"
                    if [[ -n "$name" ]]; then
                        log_ok "Added: ${BLD}$id${R} — ${CYN}$name${R}"
                    else
                        log_ok "Added: ${BLD}$id${R} ${DIM}(no name found)${R}"
                    fi
                done
                sleep 1
                ;;
            r|R)
                (( mod_count == 0 )) && continue
                echo -n "  ${WHT}Mod # to remove: ${R}"
                read -r num
                if (( num > 0 && num <= mod_count )) 2>/dev/null; then
                    local del_id="${mod_ids[$((num-1))]}"
                    sed -i "/^${del_id}|/d" "$mods_file"
                    log_ok "Removed mod ${BLD}$del_id${R}"
                    sleep 1
                fi
                ;;
            t|T)
                (( mod_count == 0 )) && continue
                echo -n "  ${WHT}Mod # to toggle: ${R}"
                read -r num
                if (( num > 0 && num <= mod_count )) 2>/dev/null; then
                    local tog_id="${mod_ids[$((num-1))]}"
                    local cur_state="${mod_enabled[$((num-1))]}"
                    if [[ "$cur_state" == "true" ]]; then
                        sed -i "s/^${tog_id}|\(.*\)|true$/${tog_id}|\1|false/" "$mods_file"
                        log_ok "Mod ${BLD}$tog_id${R} → ${RED}OFF${R}"
                    else
                        sed -i "s/^${tog_id}|\(.*\)|false$/${tog_id}|\1|true/" "$mods_file"
                        log_ok "Mod ${BLD}$tog_id${R} → ${GRN}ON${R}"
                    fi
                    sleep 1
                fi
                ;;
            n|N)
                (( mod_count == 0 )) && continue
                echo -n "  ${WHT}Mod # to rename: ${R}"
                read -r num
                if (( num > 0 && num <= mod_count )) 2>/dev/null; then
                    local ren_id="${mod_ids[$((num-1))]}"
                    local ren_en="${mod_enabled[$((num-1))]}"
                    echo -n "  ${WHT}New name: ${R}"
                    read -r new_name
                    [[ -z "$new_name" ]] && continue
                    sed -i "s/^${ren_id}|.*$/${ren_id}|${new_name}|${ren_en}/" "$mods_file"
                    log_ok "Renamed mod ${BLD}$ren_id${R} → ${CYN}$new_name${R}"
                    sleep 1
                fi
                ;;
            f|F)
                (( mod_count == 0 )) && continue
                log_info "Fetching mod names from Steam Workshop..."
                for idx in "${!mod_ids[@]}"; do
                    local fid="${mod_ids[$idx]}"
                    local fen="${mod_enabled[$idx]}"
                    local fname; fname=$(fetch_mod_name "$fid")
                    if [[ -n "$fname" ]]; then
                        sed -i "s/^${fid}|.*$/${fid}|${fname}|${fen}/" "$mods_file"
                        log_ok "${BLD}$fid${R} → ${CYN}$fname${R}"
                    else
                        log_warn "${BLD}$fid${R} — no name found"
                    fi
                done
                sleep 1
                ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  START / STOP / RESTART
#═══════════════════════════════════════════════════════════════════════════════

start_map() {
    local map="$1"
    local conf="$MAPS_DIR/$map/map.conf"
    [[ ! -f "$conf" ]] && { log_err "Map '$map' not found."; return 1; }
    if is_map_running "$map"; then
        log_warn "Map '${BLD}$map${R}' is already running."
        return 0
    fi
    check_cpu_flags || return 1

    local map_name save_dir game_port query_port rcon_port max_players
    local admin_pw server_pw custom_params cluster_id
    map_name=$(read_conf_value "$conf" "MapName")
    save_dir=$(read_conf_value "$conf" "SaveDir" "$map")
    game_port=$(read_conf_value "$conf" "GamePort" "7777")
    query_port=$(read_conf_value "$conf" "QueryPort" "27015")
    rcon_port=$(read_conf_value "$conf" "RCONPort" "27020")
    max_players=$(read_conf_value "$conf" "MaxPlayers" "70")
    admin_pw=$(read_conf_value "$conf" "AdminPassword" "")
    server_pw=$(read_conf_value "$conf" "ServerPassword" "")
    custom_params=$(read_conf_value "$conf" "CustomStartParams" "-NoBattlEye -crossplay -NoHangDetection")
    cluster_id=$(read_conf_value "$conf" "ClusterID" "")

    # Get enabled mods
    local mod_ids; mod_ids=$(get_enabled_mod_ids "$map")

    if ss -lunp 2>/dev/null | grep -q ":${game_port} "; then
        log_err "Port ${BLD}$game_port${R} is already in use!"
        return 1
    fi

    log_info "Starting map: ${BLD}$map${R} (${CYN}$map_name${R})..."

    export STEAM_COMPAT_DATA_PATH="$SERVER_DIR/steamapps/compatdata/$ARK_APPID"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAMCMD_DIR"
    export SteamAppId=$ARK_APPID
    export SteamGameId=$ARK_APPID

    local config_src="$MAPS_DIR/$map"
    local config_dst="$SERVER_DIR/ShooterGame/Saved/Config/WindowsServer"
    [[ -d "$config_dst" && ! -L "$config_dst" ]] && mv "$config_dst" "${config_dst}.bak.$(date +%s)" || true
    rm -f "$config_dst"
    ln -s "$config_src" "$config_dst"
    mkdir -p "$SERVER_DIR/ShooterGame/Saved/SavedArks/$save_dir"

    local cluster_args=""
    if [[ -n "$cluster_id" ]]; then
        local cluster_dir="$SCRIPT_DIR/clusters/$cluster_id"
        mkdir -p "$cluster_dir"
        cluster_args="-ClusterDirOverride=\"$cluster_dir\" -ClusterId=\"$cluster_id\""
    fi

    local nullrhi=""
    local use_null; use_null=$(read_conf_value "$OPT_CONF" "UseNullRHI" "true")
    [[ "$use_null" == "true" ]] && nullrhi="-nullrhi"
    local nice_lvl; nice_lvl=$(read_conf_value "$OPT_CONF" "ServerNiceLevel" "-5")

    nice $nice_lvl "$PROTON_DIR/proton" run \
        "$SERVER_DIR/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" \
        "${map_name}?listen?SessionName=${map} ?ServerPassword=${server_pw}?RCONEnabled=True?ServerAdminPassword=${admin_pw}?AltSaveDirectoryName=${save_dir}" \
        $custom_params $nullrhi \
        -WinLiveMaxPlayers=$max_players \
        -Port=$game_port -QueryPort=$query_port -RCONPort=$rcon_port \
        -game $cluster_args -server -log \
        -mods="$mod_ids" \
        > "$MAPS_DIR/$map/server.log" 2>&1 &

    log_ok "Map '${BLD}$map${R}${GRN}' starting... ~60 seconds to come online."
}

stop_map() {
    local map="$1"
    local conf="$MAPS_DIR/$map/map.conf"
    [[ ! -f "$conf" ]] && { log_err "Map '$map' not found."; return 1; }
    if ! is_map_running "$map"; then
        log_warn "Map '${BLD}$map${R}' is not running."
        return 0
    fi
    local save_dir admin_pw rcon_port
    save_dir=$(read_conf_value "$conf" "SaveDir" "$map")
    admin_pw=$(read_conf_value "$conf" "AdminPassword" "")
    rcon_port=$(read_conf_value "$conf" "RCONPort" "27020")

    log_info "Stopping map '${BLD}$map${R}'..."
    local response=""
    response=$(python3 "$RCON_SCRIPT" "localhost:$rcon_port" -p "$admin_pw" -c "DoExit" 2>/dev/null || echo "")
    if [[ "$response" == *"Exiting"* ]]; then
        log_info "Waiting for graceful shutdown..."
        local waited=0
        while pgrep -f "ArkAscendedServer.exe.*AltSaveDirectoryName=${save_dir}" &>/dev/null; do
            sleep 2; (( waited += 2 ))
            (( waited >= 120 )) && { log_warn "Timeout. Force killing..."; pkill -9 -f "ArkAscendedServer.exe.*AltSaveDirectoryName=${save_dir}" || true; break; }
        done
    else
        log_warn "RCON failed. Force stopping..."
        pkill -f "ArkAscendedServer.exe.*AltSaveDirectoryName=${save_dir}" || true
        sleep 3
        pkill -9 -f "ArkAscendedServer.exe.*AltSaveDirectoryName=${save_dir}" 2>/dev/null || true
    fi
    pkill -f "wineserver.*${save_dir}" 2>/dev/null || true
    log_ok "Map '${BLD}$map${R}${GRN}' stopped."
}

restart_map() {
    local map="$1"
    stop_map "$map"
    sleep 3
    start_map "$map"
}

start_all_maps() {
    local maps; maps=( $(get_maps) )
    (( ${#maps[@]} == 0 )) && { log_warn "No maps configured."; return; }
    local started=0
    for map in "${maps[@]}"; do
        if is_batch_enabled "$map"; then
            start_map "$map"
            ((started++))
            sleep 5
        else
            log_info "Skipping ${BLD}$map${R} ${DIM}(not in groep)${R}"
        fi
    done
    log_ok "Started ${BLD}$started${R}${GRN} maps in groep."
}

stop_all_maps() {
    local maps; maps=( $(get_maps) )
    local stopped=0
    for map in "${maps[@]}"; do
        if is_batch_enabled "$map" && is_map_running "$map"; then
            stop_map "$map"
            ((stopped++))
        elif is_map_running "$map"; then
            log_info "Skipping ${BLD}$map${R} ${DIM}(not in groep)${R}"
        fi
    done
    log_ok "Stopped ${BLD}$stopped${R}${GRN} maps in groep."
}

#═══════════════════════════════════════════════════════════════════════════════
#  RCON
#═══════════════════════════════════════════════════════════════════════════════

rcon_console() {
    local map="$1"
    if ! is_map_running "$map"; then
        log_err "Map '${BLD}$map${R}' is not running."; return 1
    fi
    local rcon_port admin_pw
    rcon_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "RCONPort" "27020")
    admin_pw=$(read_conf_value "$MAPS_DIR/$map/map.conf" "AdminPassword" "")
    clear
    log_info "RCON connected to ${BLD}$map${R}:${CYN}$rcon_port${R}"
    echo "  ${DIM}Type 'exit' or Ctrl+C to disconnect${R}"
    separator
    python3 "$RCON_SCRIPT" "localhost:$rcon_port" -p "$admin_pw"
}

send_rcon() {
    local map="$1" cmd="$2"
    if ! is_map_running "$map"; then log_err "Map '$map' is not running."; return 1; fi
    local rcon_port admin_pw
    rcon_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "RCONPort" "27020")
    admin_pw=$(read_conf_value "$MAPS_DIR/$map/map.conf" "AdminPassword" "")
    python3 "$RCON_SCRIPT" "localhost:$rcon_port" -p "$admin_pw" -c "$cmd"
}

broadcast_message() {
    local message="$1"
    local maps; maps=( $(get_maps) )
    for map in "${maps[@]}"; do
        is_map_running "$map" && send_rcon "$map" "ServerChat $message" 2>/dev/null || true
    done
    log_ok "Broadcast sent to all running maps."
}

#═══════════════════════════════════════════════════════════════════════════════
#  SERVER SETTINGS (per-map)
#═══════════════════════════════════════════════════════════════════════════════

server_settings_menu() {
    local map="$1"
    local gus="$MAPS_DIR/$map/GameUserSettings.ini"

    while true; do
        clear
        echo ""
        echo "  ${BLD}${MAG}═══ Server Settings — ${CYN}$map${MAG} ═══${R}"

        local xp taming harvest respawn mating baby hatch stack max_tamed auto_save max_struct
        xp=$(read_conf_value "$gus" "XPMultiplier" "1.0")
        taming=$(read_conf_value "$gus" "TamingSpeedMultiplier" "1.0")
        harvest=$(read_conf_value "$gus" "HarvestAmountMultiplier" "1.0")
        respawn=$(read_conf_value "$gus" "ResourcesRespawnPeriodMultiplier" "1.0")
        mating=$(read_conf_value "$gus" "MatingIntervalMultiplier" "1.0")
        baby=$(read_conf_value "$gus" "BabyMatureSpeedMultiplier" "1.0")
        hatch=$(read_conf_value "$gus" "EggHatchSpeedMultiplier" "1.0")
        stack=$(read_conf_value "$gus" "ItemStackSizeMultiplier" "1.0")
        max_tamed=$(read_conf_value "$gus" "MaxTamedDinos" "5000")
        auto_save=$(read_conf_value "$gus" "AutoSavePeriodMinutes" "15")
        max_struct=$(read_conf_value "$gus" "TheMaxStructuresInRange" "10500")

        echo ""
        echo "  ${BLD}${WHT}  Multipliers${R}"
        printf "  ${CYN}%2d${R}) %-30s : ${BLD}${WHT}%s${R}\n" 1 "XP Multiplier" "$xp"
        printf "  ${CYN}%2d${R}) %-30s : ${BLD}${WHT}%s${R}\n" 2 "Taming Speed" "$taming"
        printf "  ${CYN}%2d${R}) %-30s : ${BLD}${WHT}%s${R}\n" 3 "Harvest Amount" "$harvest"
        printf "  ${CYN}%2d${R}) %-30s : ${BLD}${WHT}%s${R}\n" 4 "Resource Respawn" "$respawn"
        printf "  ${CYN}%2d${R}) %-30s : ${BLD}${WHT}%s${R}\n" 5 "Mating Interval" "$mating"
        printf "  ${CYN}%2d${R}) %-30s : ${BLD}${WHT}%s${R}\n" 6 "Baby Mature Speed" "$baby"
        printf "  ${CYN}%2d${R}) %-30s : ${BLD}${WHT}%s${R}\n" 7 "Egg Hatch Speed" "$hatch"
        printf "  ${CYN}%2d${R}) %-30s : ${BLD}${WHT}%s${R}\n" 8 "Item Stack Size" "$stack"
        echo ""
        echo "  ${BLD}${WHT}  Limits${R}"
        printf "  ${CYN}%2d${R}) %-30s : ${BLD}${WHT}%s${R}\n" 9 "Max Tamed Dinos" "$max_tamed"
        printf "  ${CYN}%2d${R}) %-30s : ${BLD}${WHT}%s${R}\n" 10 "Auto-Save Interval (min)" "$auto_save"
        printf "  ${CYN}%2d${R}) %-30s : ${BLD}${WHT}%s${R}\n" 11 "Max Structures In Range" "$max_struct"
        echo ""
        echo "  ${BLD}${WHT}  Advanced${R}"
        printf "  ${CYN}%2d${R}) %-30s   ${DIM}(low/medium/high/auto)${R}\n" 12 "Graphics Preset"
        printf "  ${CYN}%2d${R}) %-30s   ${DIM}(nano)${R}\n" 13 "Edit GameUserSettings.ini"
        printf "  ${CYN}%2d${R}) %-30s   ${DIM}(nano)${R}\n" 14 "Edit Game.ini"
        printf "  ${CYN}%2d${R}) %-30s   ${DIM}(ports/passwords)${R}\n" 15 "Edit map.conf"
        echo ""
        echo "  ${DIM} 0) Back${R}"
        echo ""
        echo -n "  ${WHT}Choice: ${R}"
        read -r choice

        case "$choice" in
            1)  echo -n "  ${WHT}New value ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "XPMultiplier" "$val"; log_ok "Saved."; sleep 0.5; } ;;
            2)  echo -n "  ${WHT}New value ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "TamingSpeedMultiplier" "$val"; log_ok "Saved."; sleep 0.5; } ;;
            3)  echo -n "  ${WHT}New value ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "HarvestAmountMultiplier" "$val"; log_ok "Saved."; sleep 0.5; } ;;
            4)  echo -n "  ${WHT}New value ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "ResourcesRespawnPeriodMultiplier" "$val"; log_ok "Saved."; sleep 0.5; } ;;
            5)  echo -n "  ${WHT}New value ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "MatingIntervalMultiplier" "$val"; log_ok "Saved."; sleep 0.5; } ;;
            6)  echo -n "  ${WHT}New value ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "BabyMatureSpeedMultiplier" "$val"; log_ok "Saved."; sleep 0.5; } ;;
            7)  echo -n "  ${WHT}New value ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "EggHatchSpeedMultiplier" "$val"; log_ok "Saved."; sleep 0.5; } ;;
            8)  echo -n "  ${WHT}New value ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "ItemStackSizeMultiplier" "$val"; log_ok "Saved."; sleep 0.5; } ;;
            9)  echo -n "  ${WHT}New value ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "MaxTamedDinos" "$val"; log_ok "Saved."; sleep 0.5; } ;;
            10) echo -n "  ${WHT}New value ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "AutoSavePeriodMinutes" "$val"; log_ok "Saved."; sleep 0.5; } ;;
            11) echo -n "  ${WHT}New value ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "TheMaxStructuresInRange" "$val"; log_ok "Saved."; sleep 0.5; } ;;
            12) graphics_preset_menu "$map" ;;
            13) ${EDITOR:-nano} "$gus" ;;
            14) ${EDITOR:-nano} "$MAPS_DIR/$map/Game.ini" ;;
            15) ${EDITOR:-nano} "$MAPS_DIR/$map/map.conf" ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  BACKUP & RESTORE
#═══════════════════════════════════════════════════════════════════════════════

backup_map() {
    local map="$1"
    local save_dir; save_dir=$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")
    local source="$SERVER_DIR/ShooterGame/Saved/SavedArks/$save_dir"
    local backup_dir="$MAPS_DIR/$map/backups"
    local backup_file="$backup_dir/${map}_$(date +%Y%m%d_%H%M%S).tar.gz"
    [[ ! -d "$source" ]] && { log_err "No save data for '${BLD}$map${R}'."; return 1; }
    mkdir -p "$backup_dir"
    log_info "Backing up '${BLD}$map${R}'..."
    tar -czf "$backup_file" -C "$SERVER_DIR/ShooterGame/Saved/SavedArks" "$save_dir"
    local size; size=$(du -h "$backup_file" | cut -f1)
    log_ok "Backup: ${DIM}$backup_file${R} (${BLD}$size${R})"
}

restore_map() {
    local map="$1"
    local backup_dir="$MAPS_DIR/$map/backups"
    [[ ! -d "$backup_dir" ]] || [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]] && { log_err "No backups for '${BLD}$map${R}'."; return 1; }
    is_map_running "$map" && { log_err "Stop the map first!"; return 1; }

    clear
    echo ""
    echo "  ${BLD}${MAG}═══ Restore Backup — ${CYN}$map${MAG} ═══${R}"
    thin_sep
    local backups=()
    local i=1
    for f in "$backup_dir"/*.tar.gz; do
        local size fname; size=$(du -h "$f" | cut -f1); fname=$(basename "$f")
        printf "  ${CYN}%2d${R}) %-40s ${DIM}(%s)${R}\n" "$i" "$fname" "$size"
        backups+=("$f"); ((i++))
    done
    echo ""; echo "  ${DIM} 0) Back${R}"; echo ""
    echo -n "  ${WHT}Select backup: ${R}"
    read -r choice
    [[ "$choice" == "0" || -z "$choice" ]] && return 0
    (( choice < 1 || choice > ${#backups[@]} )) 2>/dev/null && return 0

    local save_dir; save_dir=$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")
    if confirm "Overwrite current save data for '${BLD}$map${R}'?"; then
        log_info "Restoring backup..."
        rm -rf "$SERVER_DIR/ShooterGame/Saved/SavedArks/$save_dir"
        tar -xzf "${backups[$((choice-1))]}" -C "$SERVER_DIR/ShooterGame/Saved/SavedArks"
        log_ok "Backup restored!"
    fi
    sleep 1
}

#═══════════════════════════════════════════════════════════════════════════════
#  LOG VIEWER
#═══════════════════════════════════════════════════════════════════════════════

view_logs() {
    local map="$1"
    local log_file="$MAPS_DIR/$map/server.log"
    local steam_log="$HOME/steam-${ARK_APPID}.log"

    while true; do
        clear
        echo ""
        echo "  ${BLD}${MAG}═══ Logs — ${CYN}$map${MAG} ═══${R}"
        thin_sep
        echo "  ${CYN}1${R}) Server log ${DIM}(last 50 lines)${R}"
        echo "  ${CYN}2${R}) Follow log ${DIM}(live — Ctrl+C to stop)${R}"
        echo "  ${CYN}3${R}) Steam/Proton log"
        echo "  ${CYN}4${R}) Errors only"
        echo ""; echo "  ${DIM}0) Back${R}"; echo ""
        echo -n "  ${WHT}Choice: ${R}"
        read -r choice
        case "$choice" in
            1) [[ -f "$log_file" ]] && { echo ""; separator; tail -50 "$log_file"; separator; } || log_warn "No log."; press_enter ;;
            2) [[ -f "$log_file" ]] && { log_info "Ctrl+C to stop..."; tail -f "$log_file" || true; } || log_warn "No log." ;;
            3) [[ -f "$steam_log" ]] && { separator; tail -80 "$steam_log"; separator; } || log_warn "No Steam log."; press_enter ;;
            4) [[ -f "$log_file" ]] && { separator; grep -iE "error|fatal|crash|exception|fail" "$log_file" | tail -30 || log_info "No errors."; separator; } || log_warn "No log."; press_enter ;;
            0|"") return ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  FILE BROWSER
#═══════════════════════════════════════════════════════════════════════════════

browse_files() {
    local map="$1"
    while true; do
        clear
        echo ""
        echo "  ${BLD}${MAG}═══ File Locations — ${CYN}$map${MAG} ═══${R}"
        thin_sep
        echo "  ${CYN}1${R}) Map config dir      ${DIM}$MAPS_DIR/$map/${R}"
        echo "  ${CYN}2${R}) Save data"
        echo "  ${CYN}3${R}) Backups"
        echo "  ${CYN}4${R}) Server files"
        echo "  ${CYN}5${R}) Open shell here"
        echo ""; echo "  ${DIM}0) Back${R}"; echo ""
        echo -n "  ${WHT}Choice: ${R}"
        read -r choice
        case "$choice" in
            1) echo ""; ls -la "$MAPS_DIR/$map/" 2>/dev/null; press_enter ;;
            2) ls -la "$SERVER_DIR/ShooterGame/Saved/SavedArks/$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")/" 2>/dev/null; press_enter ;;
            3) ls -la "$MAPS_DIR/$map/backups/" 2>/dev/null; press_enter ;;
            4) ls -la "$SERVER_DIR/" 2>/dev/null; press_enter ;;
            5) log_info "Shell at: ${BLD}$MAPS_DIR/$map/${R}"; cd "$MAPS_DIR/$map" && exec bash ;;
            0|"") return ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  DELETE MAP
#═══════════════════════════════════════════════════════════════════════════════

delete_map() {
    local map="$1"
    is_map_running "$map" && { log_err "Stop the map first!"; return 1; }
    echo ""
    log_warn "${RED}${BLD}PERMANENTLY DELETE${R} map '${BLD}$map${R}' and all configuration?"
    if confirm "Are you absolutely sure?"; then
        local service_name="ark-${map,,}.service"
        sudo systemctl stop "$service_name" 2>/dev/null || true
        sudo systemctl disable "$service_name" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/$service_name"
        sudo systemctl daemon-reload
        sed -i "/^${map}|/d" "$MAPS_CONF"
        rm -rf "$MAPS_DIR/$map"
        rm -f "/tmp/.ark-players-${map}" "/tmp/.ark-join-${map}"
        FEEDBACK="${GRN}${BLD}✔${R} Map '${BLD}$map${R}' deleted."
        return 0
    fi
    return 1
}

#═══════════════════════════════════════════════════════════════════════════════
#  CHANGE MAP TYPE
#═══════════════════════════════════════════════════════════════════════════════

change_map_type() {
    local map="$1"
    is_map_running "$map" && { log_err "Stop the map first!"; return 1; }
    clear
    echo ""
    echo "  ${BLD}${MAG}═══ Change Map Type — ${CYN}$map${MAG} ═══${R}"
    thin_sep
    local i=1; local map_keys=()
    for key in $(echo "${!MAP_NAMES[@]}" | tr ' ' '\n' | sort); do
        printf "  ${CYN}%2d${R}) %-20s  ${DIM}(%s)${R}\n" "$i" "$key" "${MAP_NAMES[$key]}"
        map_keys+=("$key"); ((i++))
    done
    echo ""; echo "  ${DIM} 0) Back${R}"; echo ""
    echo -n "  ${WHT}Select: ${R}"
    read -r choice
    [[ "$choice" == "0" || -z "$choice" ]] && return 0
    if (( choice > 0 && choice <= ${#map_keys[@]} )) 2>/dev/null; then
        local new_internal="${MAP_NAMES[${map_keys[$((choice-1))]}]}"
        write_conf_value "$MAPS_DIR/$map/map.conf" "MapName" "$new_internal"
        log_ok "Changed to ${BLD}${map_keys[$((choice-1))]}${R}${GRN}. Restart to apply."
        sleep 1
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  TOGGLE GROEP / AUTO-START (return feedback via stdout)
#═══════════════════════════════════════════════════════════════════════════════

toggle_batch() {
    local map="$1"
    local current; current=$(read_conf_value "$MAPS_DIR/$map/map.conf" "BatchEnabled" "true")
    if [[ "$current" == "true" ]]; then
        write_conf_value "$MAPS_DIR/$map/map.conf" "BatchEnabled" "false"
        echo "${GRN}${BLD}✔${R} ${BLD}$map${R}: Groep ${RED}UIT${R} — wordt overgeslagen bij Start All / Stop All"
    else
        write_conf_value "$MAPS_DIR/$map/map.conf" "BatchEnabled" "true"
        echo "${GRN}${BLD}✔${R} ${BLD}$map${R}: Groep ${GRN}AAN${R} — doet mee met Start All / Stop All"
    fi
}

toggle_autostart() {
    local map="$1"
    local service="ark-${map,,}.service"
    if systemctl is-enabled "$service" 2>/dev/null | grep -q "enabled"; then
        sudo systemctl disable "$service" 2>/dev/null
        echo "${GRN}${BLD}✔${R} ${BLD}$map${R}: Auto-start ${RED}UIT${R} — start niet na reboot/stroomstoring"
    else
        sudo systemctl enable "$service" 2>/dev/null
        echo "${GRN}${BLD}✔${R} ${BLD}$map${R}: Auto-start ${GRN}AAN${R} — start automatisch na reboot/stroomstoring"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  OPTIMIZATION / HEALTHCHECK / LOGROTATE
#═══════════════════════════════════════════════════════════════════════════════

apply_optimizations() {
    log_info "Applying system optimizations..."
    if command -v sysctl &>/dev/null; then
        sudo tee "/etc/sysctl.d/99-ark-server.conf" > /dev/null <<'SYSEOF'
vm.swappiness=10
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.ipv4.udp_mem=65536 131072 262144
SYSEOF
        sudo sysctl --system -q 2>/dev/null || true
    fi
    setup_logrotate; setup_healthcheck
    log_ok "All optimizations applied."
}

setup_logrotate() {
    command -v logrotate &>/dev/null || return
    sudo tee "/etc/logrotate.d/ark-server" > /dev/null <<LREOF
$MAPS_DIR/*/server.log
$HOME/steam-*.log
{
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    size 50M
}
LREOF
}

setup_healthcheck() {
    local hc_script="$SCRIPT_DIR/healthcheck.sh"
    cat > "$hc_script" <<'HCEOF'
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
    systemctl is-enabled "$service_name" &>/dev/null || continue
    if ! systemctl is-active "$service_name" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [HEAL] $map down, restarting..." >> "$LOG"
        systemctl restart "$service_name" 2>/dev/null || true
    fi
done
HCEOF
    chmod +x "$hc_script"
    local cron_line="*/5 * * * * $hc_script"
    crontab -l 2>/dev/null | grep -qF "$hc_script" || \
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
}

#═══════════════════════════════════════════════════════════════════════════════
#  SCHEDULED RESTART
#═══════════════════════════════════════════════════════════════════════════════

setup_scheduled_restart() {
    clear
    echo ""
    echo "  ${BLD}${MAG}═══ Scheduled Restart ═══${R}"
    thin_sep
    echo -n "  ${WHT}Restart time (HH:MM, 24h) ${DIM}[04:00]${R}: "
    read -r restart_time
    restart_time="${restart_time:-04:00}"
    [[ "$restart_time" == "0" ]] && return 0

    local hour minute
    hour=$(echo "$restart_time" | cut -d: -f1)
    minute=$(echo "$restart_time" | cut -d: -f2)

    local rs_script="$SCRIPT_DIR/scheduled-restart.sh"
    cat > "$rs_script" <<RSEOF
#!/usr/bin/env bash
SCRIPT_DIR="\$(cd "\$(dirname "\$(realpath "\$0")")" && pwd)"
MANAGER="\$SCRIPT_DIR/ark-manager.sh"
LOG="\$SCRIPT_DIR/restart.log"
announce() { \$MANAGER broadcast "\$1" 2>/dev/null; echo "\$(date '+%Y-%m-%d %H:%M:%S') [RESTART] \$1" >> "\$LOG"; }
announce "Server restart in 30 minutes!"
sleep 1200
announce "Server restart in 10 minutes!"
sleep 420
announce "Server restart in 3 minutes! Save your progress!"
sleep 170
announce "Server restart in 10 seconds!"
sleep 10
\$MANAGER stop-all; sleep 10; \$MANAGER start-all
echo "\$(date '+%Y-%m-%d %H:%M:%S') [RESTART] Complete." >> "\$LOG"
RSEOF
    chmod +x "$rs_script"

    local cron_min=$(( (minute - 30 + 60) % 60 ))
    local cron_hour=$hour
    (( minute < 30 )) && cron_hour=$(( (hour - 1 + 24) % 24 ))
    crontab -l 2>/dev/null | grep -vF "scheduled-restart.sh" | { cat; echo "$cron_min $cron_hour * * * $rs_script"; } | crontab -
    log_ok "Scheduled restart set for ${BLD}$restart_time${R}${GRN} daily."
    sleep 1
}

#═══════════════════════════════════════════════════════════════════════════════
#  SELECT MAP HELPER
#═══════════════════════════════════════════════════════════════════════════════

select_map() {
    local maps; maps=( $(get_maps) )
    (( ${#maps[@]} == 0 )) && { FEEDBACK="${YEL}⚠ No maps configured.${R}"; return 1; }

    clear
    echo ""
    echo "  ${BLD}${WHT}Select a map:${R}"
    thin_sep
    local i=1
    for m in "${maps[@]}"; do
        local icon
        if is_map_running "$m"; then icon="${GRN}●${R}"; else icon="${RED}●${R}"; fi
        printf "  ${icon} ${CYN}%2d${R}) %s\n" "$i" "$m"
        ((i++))
    done
    echo ""; echo "  ${DIM} 0) Back${R}"; echo ""
    echo -n "  ${WHT}Choice: ${R}"
    read -r choice
    [[ "$choice" == "0" || -z "$choice" ]] && return 1
    if (( choice > 0 && choice <= ${#maps[@]} )) 2>/dev/null; then
        SELECTED_MAP="${maps[$((choice-1))]}"
        return 0
    fi
    return 1
}

#═══════════════════════════════════════════════════════════════════════════════
#  MAP MENU (per-map management — live status refreshes every 2s)
#═══════════════════════════════════════════════════════════════════════════════

map_menu() {
    local map="$1"
    local map_feedback=""

    while true; do
        # Guard: if map was deleted, exit this menu
        [[ ! -d "$MAPS_DIR/$map" ]] && return

        clear
        local internal
        internal=$(read_conf_value "$MAPS_DIR/$map/map.conf" "MapName" "?")

        echo ""
        echo "  ${BLD}${BLU}╔═══════════════════════════════════════════════════════════╗${R}"
        echo "  ${BLD}${BLU}║${R}  ${BLD}${WHT}$map${R}  ${DIM}($internal)${R}"
        echo "  ${BLD}${BLU}╚═══════════════════════════════════════════════════════════╝${R}"

        # Live status block
        if is_map_running "$map"; then
            local health_raw
            health_raw=$(check_map_health "$map")
            local status_text="${BG_GRN}${BLD}${WHT} ONLINE ${R}"
            local health_text
            case "$health_raw" in
                HEALTHY)  health_text="${GRN}${BLD}HEALTHY${R}" ;;
                DEGRADED) health_text="${YEL}${BLD}DEGRADED${R}" ;;
                *)        health_text="${RED}${BLD}$health_raw${R}" ;;
            esac
            local pc up mem cpu join_raw
            pc=$(get_player_count "$map" 2>/dev/null || echo "?")
            local max_p; max_p=$(read_conf_value "$MAPS_DIR/$map/map.conf" "MaxPlayers" "70")
            up=$(get_map_uptime "$map")
            mem=$(get_map_memory "$map")
            cpu=$(get_map_cpu "$map")
            join_raw=$(check_server_queryable "$map")
            local join_text
            [[ "$join_raw" == "YES" ]] && join_text="${GRN}${BLD}✔ YES${R}" || join_text="${RED}${BLD}✖ NO${R}"

            echo "  ${status_text}  ${health_text}  │  Players: ${BLD}${pc}/${max_p}${R}  │  Uptime: ${BLD}${up}${R}"
            echo "  RAM: ${BLD}${mem}${R}  │  CPU: ${BLD}${cpu}${R}  │  Join: ${join_text}"
        else
            echo "  ${BG_RED}${BLD}${WHT} OFFLINE ${R}  ${DIM}STOPPED${R}"
        fi

        # Groep / Auto-start status
        local groep_s auto_s
        is_batch_enabled "$map" && groep_s="${GRN}AAN${R}" || groep_s="${RED}UIT${R}"
        is_autostart_enabled "$map" 2>/dev/null && auto_s="${GRN}AAN${R}" || auto_s="${RED}UIT${R}"
        echo "  Groep: ${groep_s}  │  Auto-start: ${auto_s}"

        # Show feedback if any
        if [[ -n "$map_feedback" ]]; then
            echo ""
            echo "  $map_feedback"
            map_feedback=""
        fi
        echo ""

        # Menu options — aligned columns with printf %2d for consistent numbering
        printf "  ${CYN}%2d${R}) ${GRN}%-20s${R}${CYN}%2d${R}) %s\n" 1 "Start" 8 "Restore Backup"
        printf "  ${CYN}%2d${R}) ${RED}%-20s${R}${CYN}%2d${R}) %s\n" 2 "Stop" 9 "View Logs"
        printf "  ${CYN}%2d${R}) ${YEL}%-20s${R}${CYN}%2d${R}) %s\n" 3 "Restart" 10 "Browse Files"
        printf "  ${CYN}%2d${R}) %-20s  ${CYN}%2d${R}) %s\n" 4 "RCON Console" 11 "Change Map Type"
        printf "  ${CYN}%2d${R}) %-20s  ${CYN}%2d${R}) %s\n" 5 "Server Settings" 12 "Toggle Groep"
        printf "  ${CYN}%2d${R}) %-20s  ${CYN}%2d${R}) %s\n" 6 "Mod Management" 13 "Toggle Auto-Start"
        printf "  ${CYN}%2d${R}) %-20s  ${CYN}%2d${R}) ${RED}%s${R}\n" 7 "Backup World" 14 "Delete Map"
        echo ""
        echo "  ${DIM} 0) Back to Dashboard${R}"
        echo ""
        echo -n "  ${GRY}↻ Live 2s │${R} ${WHT}Choice: ${R}"

        # Auto-refresh every 2 seconds
        read -t 2 -r choice 2>/dev/null || true
        [[ -z "$choice" ]] && continue

        case "$choice" in
            1)  clear; start_map "$map"; press_enter ;;
            2)  clear; stop_map "$map"; press_enter ;;
            3)  clear; restart_map "$map"; press_enter ;;
            4)  rcon_console "$map" ;;
            5)  server_settings_menu "$map" ;;
            6)  manage_mods "$map" ;;
            7)  clear; backup_map "$map"; press_enter ;;
            8)  restore_map "$map" ;;
            9)  view_logs "$map" ;;
            10) browse_files "$map" ;;
            11) change_map_type "$map" ;;
            12) map_feedback=$(toggle_batch "$map") ;;
            13) map_feedback=$(toggle_autostart "$map") ;;
            14) clear; delete_map "$map" && return ;;
            0|"") return ;;
            *) ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  MAIN MENU (live dashboard — refreshes every 2s, options always visible)
#═══════════════════════════════════════════════════════════════════════════════

main_menu() {
    while true; do
        show_dashboard

        separator
        echo ""
        echo "  ${BLD}${WHT}Actions:${R}"
        echo ""
        printf "  ${CYN}%2d${R}) ${BLU}%-22s${R}${CYN}%2d${R}) %s\n" 1 "Select Map" 5 "Send RCON Command"
        printf "  ${CYN}%2d${R}) ${GRN}%-22s${R}${CYN}%2d${R}) %s\n" 2 "Add Map" 6 "Broadcast Message"
        printf "  ${CYN}%2d${R}) ${GRN}%-14s${R}${DIM}(groep)${R}  ${CYN}%2d${R}) %s\n" 3 "Start All" 7 "Scheduled Restarts"
        printf "  ${CYN}%2d${R}) ${RED}%-14s${R}${DIM}(groep)${R}  ${CYN}%2d${R}) %s\n" 4 "Stop All" 8 "Install / Update"
        echo ""
        echo "  ${DIM} 0) Exit${R}"
        echo ""
        echo -n "  ${GRY}↻ Live 2s │${R} ${WHT}Choice: ${R}"

        # Auto-refresh every 2 seconds
        read -t 2 -r choice 2>/dev/null || true
        [[ -z "$choice" ]] && continue

        case "$choice" in
            1)  select_map && map_menu "$SELECTED_MAP" ;;
            2)  add_map ;;
            3)  clear; start_all_maps; press_enter ;;
            4)  clear; stop_all_maps; press_enter ;;
            5)
                if select_map; then
                    echo -n "  ${WHT}RCON command: ${R}"
                    read -r cmd
                    [[ -n "$cmd" ]] && { clear; send_rcon "$SELECTED_MAP" "$cmd"; press_enter; }
                fi
                ;;
            6)
                clear
                echo ""
                echo -n "  ${WHT}Message: ${R}"
                read -r msg
                [[ -n "$msg" ]] && broadcast_message "$msg"
                sleep 1
                ;;
            7)  setup_scheduled_restart ;;
            8)  install_server ;;
            0)
                echo ""
                echo "  ${GRN}${BLD}Goodbye! 🦖${R}"
                echo ""
                exit 0
                ;;
            *) ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  CLI INTERFACE
#═══════════════════════════════════════════════════════════════════════════════

cli_status() {
    local maps; maps=( $(get_maps) )
    (( ${#maps[@]} == 0 )) && { echo "No maps configured."; return; }
    printf "${BLD}%-15s %-10s %-9s %-8s %-7s %-6s %-5s %-4s %-4s${R}\n" "MAP" "STATUS" "HEALTH" "PLAYERS" "UPTIME" "RAM" "CPU" "JOIN" "AUTO"
    echo "──────────────────────────────────────────────────────────────────────────"
    for map in "${maps[@]}"; do
        local status health players uptime mem cpu join auto_s
        is_map_running "$map" && status="${GRN}ONLINE${R}" || status="${RED}OFFLINE${R}"
        health=$(check_map_health "$map")
        case "$health" in
            HEALTHY) health="${GRN}${health}${R}" ;;
            DEGRADED) health="${YEL}${health}${R}" ;;
            CRASHED|ZOMBIE|FROZEN) health="${RED}${health}${R}" ;;
            *) health="${DIM}${health}${R}" ;;
        esac
        if is_map_running "$map"; then
            local pc max_p
            pc=$(get_player_count "$map" 2>/dev/null || echo "?")
            max_p=$(read_conf_value "$MAPS_DIR/$map/map.conf" "MaxPlayers" "70")
            players="${pc}/${max_p}"
            local join_raw
            join_raw=$(check_server_queryable "$map")
            [[ "$join_raw" == "YES" ]] && join="${GRN}✔${R}" || join="${RED}✖${R}"
        else
            players="-"; join="${DIM}-${R}"
        fi
        uptime=$(get_map_uptime "$map"); mem=$(get_map_memory "$map"); cpu=$(get_map_cpu "$map")
        is_autostart_enabled "$map" 2>/dev/null && auto_s="${GRN}YES${R}" || auto_s="${RED}NO${R}"
        echo "$(pad 15 "$map") ${status}    ${health}  $(pad 8 "$players") $(pad 7 "$uptime") $(pad 6 "$mem") $(pad 5 "$cpu") ${join}    ${auto_s}"
    done
}

show_help() {
    echo ""
    echo "  ${BLD}ARK: Survival Ascended — Server Manager${R}  ${DIM}v${VERSION}${R}"
    echo ""
    echo "  ${BLD}Usage:${R} $(basename "$0") ${CYN}[command]${R} ${DIM}[arguments]${R}"
    echo ""
    echo "  ${CYN}(none)${R}              Interactive dashboard"
    echo "  ${CYN}install${R}             Install/update server"
    echo "  ${CYN}start${R} <map>         Start a map"
    echo "  ${CYN}stop${R} <map>          Stop a map"
    echo "  ${CYN}restart${R} <map>       Restart a map"
    echo "  ${CYN}start-all${R}           Start all groep maps"
    echo "  ${CYN}stop-all${R}            Stop all groep maps"
    echo "  ${CYN}status${R}              Show all map statuses"
    echo "  ${CYN}rcon${R} <map> \"cmd\"    Send RCON command"
    echo "  ${CYN}backup${R} <map>        Backup map world"
    echo "  ${CYN}broadcast${R} \"msg\"     Send message to all maps"
    echo "  ${CYN}help${R}                Show this help"
    echo ""
}

#═══════════════════════════════════════════════════════════════════════════════
#  MAIN ENTRY POINT
#═══════════════════════════════════════════════════════════════════════════════

mkdir -p "$CONFIG_DIR" "$MAPS_DIR"

[[ -f "$DEFAULTS_CONF" ]] || cat > "$DEFAULTS_CONF" <<'EOF'
DefaultMaxPlayers=70
DefaultServerPassword=
DefaultAdminPassword=
DefaultGamePort=7777
DefaultQueryPort=27015
DefaultRCONPort=27020
DefaultStartParams=-NoBattlEye -crossplay -NoHangDetection
XPMultiplier=1.0
TamingSpeedMultiplier=1.0
HarvestAmountMultiplier=1.0
ClusterID=
EOF

[[ -f "$MAPS_CONF" ]] || touch "$MAPS_CONF"

[[ -f "$OPT_CONF" ]] || cat > "$OPT_CONF" <<'EOF'
UseNullRHI=true
ServerNiceLevel=-5
EOF

if [[ $# -eq 0 ]]; then
    check_dependencies
    main_menu
else
    case "$1" in
        install|update)   install_server ;;
        start)            [[ -n "${2:-}" ]] && start_map "$2" || { echo "Usage: $0 start <map>"; exit 1; } ;;
        stop)             [[ -n "${2:-}" ]] && stop_map "$2"  || { echo "Usage: $0 stop <map>"; exit 1; } ;;
        restart)          [[ -n "${2:-}" ]] && restart_map "$2" || { echo "Usage: $0 restart <map>"; exit 1; } ;;
        start-all)        start_all_maps ;;
        stop-all)         stop_all_maps ;;
        status)           cli_status ;;
        rcon)             [[ -n "${2:-}" ]] && [[ -n "${3:-}" ]] && send_rcon "$2" "${*:3}" || { echo "Usage: $0 rcon <map> \"cmd\""; exit 1; } ;;
        backup)           [[ -n "${2:-}" ]] && backup_map "$2" || { echo "Usage: $0 backup <map>"; exit 1; } ;;
        broadcast)        [[ -n "${2:-}" ]] && broadcast_message "${*:2}" || { echo "Usage: $0 broadcast \"msg\""; exit 1; } ;;
        help|--help|-h)   show_help ;;
        *)                echo "Unknown command: $1"; show_help; exit 1 ;;
    esac
fi
