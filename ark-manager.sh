#!/usr/bin/env bash
#═══════════════════════════════════════════════════════════════════════════════
#  ARK: Survival Ascended — Linux Server Manager  v2.0
#  A clean, map-centered management tool for ASA dedicated servers.
#  https://github.com/lewisQ17/ARK-Server
#═══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

VERSION="2.0"
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
ITAL=$'\e[3m'
ULINE=$'\e[4m'
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
BG_MAG=$'\e[45m'
BG_CYN=$'\e[46m'

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

#═══════════════════════════════════════════════════════════════════════════════
#  UTILITY FUNCTIONS
#═══════════════════════════════════════════════════════════════════════════════

log_info()  { echo "${CYN}${BLD}  ℹ ${R} $*"; }
log_ok()    { echo "${GRN}${BLD}  ✔ ${R} $*"; }
log_warn()  { echo "${YEL}${BLD}  ⚠ ${R} $*"; }
log_err()   { echo "${RED}${BLD}  ✖ ${R} $*"; }

separator() {
    echo "  ${GRY}──────────────────────────────────────────────────────────────────────${R}"
}

thin_sep() {
    echo "  ${GRY}╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌${R}"
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

# Read a config value from an INI-style file
read_conf_value() {
    local file="$1" key="$2" default="${3:-}"
    local val
    val=$(grep -E "^${key}=" "$file" 2>/dev/null | tail -1 | cut -d'=' -f2-)
    echo "${val:-$default}"
}

# Write/update a config value
write_conf_value() {
    local file="$1" key="$2" value="$3"
    if grep -qE "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# Prompt for input with default. Empty input = use default. "0" = cancel/back.
# Returns 1 if user wants to go back.
read_input() {
    local prompt="$1" default="$2" varname="$3"
    echo -n "  ${WHT}${prompt}${R} ${DIM}[${default}]${R}: "
    local input
    read -r input
    if [[ "$input" == "0" ]]; then
        return 1
    fi
    printf -v "$varname" '%s' "${input:-$default}"
    return 0
}

#═══════════════════════════════════════════════════════════════════════════════
#  DEPENDENCY CHECK & INSTALL
#═══════════════════════════════════════════════════════════════════════════════

check_dependencies() {
    local missing=()
    local deps=(wget tar grep python3 curl cron)

    if command -v apt-get &>/dev/null; then
        for pkg in libc6:i386 libstdc++6:i386 libncursesw6:i386 libfreetype6:i386 libfreetype6:amd64; do
            if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
                missing+=("$pkg")
            fi
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
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y "${missing[@]}"
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm "${missing[@]}"
            fi
            log_ok "Dependencies installed."
        else
            log_warn "Continuing without all dependencies — some features may fail."
        fi
    fi
}

check_cpu_flags() {
    if ! grep -qw avx /proc/cpuinfo || ! grep -qw avx2 /proc/cpuinfo; then
        log_err "CPU missing AVX/AVX2 support. ARK: Survival Ascended requires these."
        log_err "If running in a VM, set CPU type to 'host' in your hypervisor."
        return 1
    fi
    return 0
}

#═══════════════════════════════════════════════════════════════════════════════
#  INSTALL / UPDATE
#═══════════════════════════════════════════════════════════════════════════════

install_server() {
    log_info "Installing / Updating ARK server..."
    check_cpu_flags || return 1

    # Check no maps are running
    local running=0
    for map_dir in "$MAPS_DIR"/*/; do
        [[ -d "$map_dir" ]] || continue
        local mname
        mname=$(basename "$map_dir")
        if is_map_running "$mname"; then
            log_err "Map '${BLD}$mname${R}' is running. Stop all maps before updating."
            ((running++))
        fi
    done
    (( running > 0 )) && return 1

    mkdir -p "$STEAMCMD_DIR" "$PROTON_DIR" "$SERVER_DIR"

    # ─── SteamCMD ───
    if [[ ! -f "$STEAMCMD_DIR/steamcmd.sh" ]]; then
        log_info "Downloading SteamCMD..."
        wget -q -O "$STEAMCMD_DIR/steamcmd_linux.tar.gz" "$STEAMCMD_URL"
        tar -xzf "$STEAMCMD_DIR/steamcmd_linux.tar.gz" -C "$STEAMCMD_DIR"
        rm -f "$STEAMCMD_DIR/steamcmd_linux.tar.gz"
        log_ok "SteamCMD installed."
    else
        log_ok "SteamCMD already present."
    fi

    # ─── Steam SDK symlinks ───
    mkdir -p "$HOME/.steam/sdk32" "$HOME/.steam/sdk64"
    ln -sf "$STEAMCMD_DIR/linux32/steamclient.so" "$HOME/.steam/sdk32/steamclient.so"
    ln -sf "$STEAMCMD_DIR/linux64/steamclient.so" "$HOME/.steam/sdk64/steamclient.so"

    # ─── GE-Proton ───
    if [[ ! -d "$PROTON_DIR/files" ]]; then
        log_info "Downloading ${BLD}$PROTON_VERSION${R}..."
        wget -q --show-progress -O "$PROTON_DIR/$PROTON_VERSION.tar.gz" "$PROTON_URL"
        tar -xzf "$PROTON_DIR/$PROTON_VERSION.tar.gz" -C "$PROTON_DIR" --strip-components=1
        rm -f "$PROTON_DIR/$PROTON_VERSION.tar.gz"
        log_ok "Proton installed."
    else
        log_ok "Proton already present."
    fi

    # ─── ARK Dedicated Server ───
    log_info "Downloading / Updating ARK (AppID ${BLD}$ARK_APPID${R})..."
    "$STEAMCMD_DIR/steamcmd.sh" \
        +force_install_dir "$SERVER_DIR" \
        +login anonymous \
        +@sSteamCmdForcePlatformType windows \
        +app_update $ARK_APPID validate \
        +quit

    # Delete .pdb files to save space
    local pdb_count
    pdb_count=$(find "$SERVER_DIR" -name "*.pdb" 2>/dev/null | wc -l)
    if (( pdb_count > 0 )); then
        log_info "Removing ${BLD}$pdb_count${R} .pdb debug files..."
        find "$SERVER_DIR" -name "*.pdb" -delete
    fi

    # Initialize Proton Prefix
    local compat_dir="$SERVER_DIR/steamapps/compatdata/$ARK_APPID"
    if [[ ! -d "$compat_dir/pfx" ]]; then
        log_info "Initializing Proton prefix..."
        mkdir -p "$compat_dir"
        cp -r "$PROTON_DIR/files/share/default_pfx/." "$compat_dir/"
        log_ok "Proton prefix initialized."
    fi

    apply_optimizations
    mkdir -p "$HOME/.config/protonfixes"

    log_ok "Server installation/update complete!"
    echo ""
    echo "  ${GRN}Next step:${R} Select ${BLD}'Add Map'${R} from the menu to create your first map."
    echo ""
}

#═══════════════════════════════════════════════════════════════════════════════
#  MAP MANAGEMENT — status helpers
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
    local rcon_port admin_pw
    rcon_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "RCONPort" "27020")
    admin_pw=$(read_conf_value "$MAPS_DIR/$map/map.conf" "AdminPassword" "")
    [[ -z "$admin_pw" ]] && admin_pw=$(read_conf_value "$DEFAULTS_CONF" "DefaultAdminPassword" "")
    local count
    count=$(python3 "$RCON_SCRIPT" "localhost:$rcon_port" -p "$admin_pw" -c "ListPlayers" 2>/dev/null | grep -c "^[0-9]" || true)
    echo "${count:-0}"
}

check_map_health() {
    local map="$1"
    is_map_running "$map" || { echo "STOPPED"; return; }
    local pid
    pid=$(get_map_pid "$map")
    [[ -z "$pid" ]] && { echo "CRASHED"; return; }
    local state
    state=$(ps -o state= -p "$pid" 2>/dev/null || echo "?")
    case "$state" in
        Z*) echo "ZOMBIE" ;;
        T*) echo "FROZEN" ;;
        *)
            local game_port
            game_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "GamePort" "7777")
            if ss -lunp 2>/dev/null | grep -q ":${game_port} "; then
                echo "HEALTHY"
            else
                echo "DEGRADED"
            fi
            ;;
    esac
}

get_map_uptime() {
    local map="$1"
    local pid
    pid=$(get_map_pid "$map")
    [[ -z "$pid" ]] && { echo "-"; return; }
    local elapsed
    elapsed=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -z "$elapsed" ]] && { echo "-"; return; }
    local days=$(( elapsed / 86400 ))
    local hours=$(( (elapsed % 86400) / 3600 ))
    local mins=$(( (elapsed % 3600) / 60 ))
    if (( days > 0 )); then
        echo "${days}d ${hours}h"
    elif (( hours > 0 )); then
        echo "${hours}h ${mins}m"
    else
        echo "${mins}m"
    fi
}

get_map_memory() {
    local map="$1"
    local pid
    pid=$(get_map_pid "$map")
    [[ -z "$pid" ]] && { echo "-"; return; }
    local rss
    rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -z "$rss" ]] || (( rss == 0 )) && { echo "-"; return; }
    local mb=$(( rss / 1024 ))
    if (( mb > 1024 )); then
        printf "%.1fG" "$(echo "scale=1; $mb/1024" | bc)"
    else
        echo "${mb}M"
    fi
}

get_last_backup() {
    local map="$1"
    local backup_dir="$MAPS_DIR/$map/backups"
    local latest
    latest=$(ls -1t "$backup_dir"/*.tar.gz 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
        stat -c '%Y' "$latest" 2>/dev/null | xargs -I{} date -d @{} '+%d/%m %H:%M' 2>/dev/null || echo "-"
    else
        echo "${DIM}never${R}"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  DASHBOARD
#═══════════════════════════════════════════════════════════════════════════════

show_dashboard() {
    clear
    local maps
    maps=( $(get_maps) )

    # ─── Header ───
    echo ""
    echo "  ${BLD}${BLU}╔═══════════════════════════════════════════════════════════════════╗${R}"
    echo "  ${BLD}${BLU}║${R}  ${BLD}${WHT}  🦖  ARK: Survival Ascended — Server Manager${R}  ${DIM}v${VERSION}${R}      ${BLD}${BLU}║${R}"
    echo "  ${BLD}${BLU}╚═══════════════════════════════════════════════════════════════════╝${R}"
    echo ""

    # ─── System info ───
    local cpu_use mem_total mem_used disk_free host_uptime
    cpu_use=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1 || echo "?")
    mem_total=$(free -g 2>/dev/null | awk '/Mem:/{print $2}' || echo "?")
    mem_used=$(free -g 2>/dev/null | awk '/Mem:/{print $3}' || echo "?")
    disk_free=$(df -h "$SCRIPT_DIR" 2>/dev/null | awk 'NR==2{print $4}' || echo "?")
    host_uptime=$(uptime -p 2>/dev/null | sed 's/up //' || echo "?")

    echo "  ${GRY}┌─ System ──────────────────────────────────────────────────────────┐${R}"
    echo "  ${GRY}│${R}  CPU ${BLD}${cpu_use}%${R}  ${GRY}│${R}  RAM ${BLD}${mem_used}G${R}/${mem_total}G  ${GRY}│${R}  Disk ${BLD}${disk_free}${R} free  ${GRY}│${R}  Up ${BLD}${host_uptime}${R}"
    echo "  ${GRY}└───────────────────────────────────────────────────────────────────┘${R}"
    echo ""

    if (( ${#maps[@]} == 0 )); then
        echo "  ${DIM}No maps configured yet. Use ${WHT}Add Map${DIM} to get started.${R}"
    else
        # Table header
        echo "  ${BLD}${WHT}$(printf '%-15s' "MAP") $(printf '%-10s' "STATUS") $(printf '%-10s' "HEALTH") $(printf '%-9s' "PLAYERS") $(printf '%-8s' "UPTIME") $(printf '%-7s' "RAM") $(printf '%-12s' "PORTS")${R}"
        separator

        for map in "${maps[@]}"; do
            local game_port query_port
            game_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "GamePort" "?")
            query_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "QueryPort" "?")

            # Build row — each colored field has a FIXED visible width
            local col_map col_status col_health col_players col_uptime col_mem col_ports

            col_map=$(printf '%-15s' "$map")

            if is_map_running "$map"; then
                col_status="${BG_GRN}${BLD}${WHT} ONLINE  ${R} "
            else
                col_status="${BG_RED}${BLD}${WHT} OFFLINE ${R} "
            fi

            local health_raw
            health_raw=$(check_map_health "$map")
            case "$health_raw" in
                HEALTHY)  col_health="${GRN}${BLD}HEALTHY ${R} " ;;
                DEGRADED) col_health="${YEL}${BLD}DEGRADED${R} " ;;
                CRASHED)  col_health="${RED}${BLD}CRASHED ${R} " ;;
                ZOMBIE)   col_health="${RED}${BLD}ZOMBIE  ${R} " ;;
                FROZEN)   col_health="${RED}${BLD}FROZEN  ${R} " ;;
                STOPPED)  col_health="${DIM}STOPPED ${R} " ;;
                *)        col_health="${DIM}UNKNOWN ${R} " ;;
            esac

            if is_map_running "$map"; then
                local pc max_p
                pc=$(get_player_count "$map" 2>/dev/null || echo "?")
                max_p=$(read_conf_value "$MAPS_DIR/$map/map.conf" "MaxPlayers" "70")
                col_players=$(printf '%-9s' "${pc}/${max_p}")
            else
                col_players="${DIM}$(printf '%-9s' "-")${R}"
            fi

            col_uptime=$(printf '%-8s' "$(get_map_uptime "$map")")
            col_mem=$(printf '%-7s' "$(get_map_memory "$map")")
            col_ports=$(printf '%-12s' "${game_port}/${query_port}")

            echo "  ${col_map} ${col_status}${col_health}${col_players} ${col_uptime} ${col_mem} ${col_ports}"
        done
    fi

    echo ""
}

# Live dashboard — auto-refreshes every N seconds, press any key to go back
live_dashboard() {
    local refresh=5
    while true; do
        show_dashboard
        echo "  ${DIM}${GRY}Auto-refreshing every ${refresh}s — press any key for menu...${R}"
        if read -rsn1 -t "$refresh" 2>/dev/null; then
            break
        fi
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  ADD MAP
#═══════════════════════════════════════════════════════════════════════════════

add_map() {
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
        [[ -z "$display_name" ]] && { log_warn "Cancelled."; return 0; }
        echo -n "  ${WHT}Internal map name (e.g. MyMap_WP): ${R}"
        read -r internal_name
        [[ -z "$internal_name" ]] && { log_warn "Cancelled."; return 0; }
    else
        log_err "Invalid selection."
        return 1
    fi

    # Check if already exists
    if [[ -d "$MAPS_DIR/$display_name" ]]; then
        log_err "Map '${BLD}$display_name${R}' already exists."
        return 1
    fi

    # Defaults
    local def_port def_qport def_rport def_maxp def_adminpw
    def_port=$(read_conf_value "$DEFAULTS_CONF" "DefaultGamePort" "7777")
    def_qport=$(read_conf_value "$DEFAULTS_CONF" "DefaultQueryPort" "27015")
    def_rport=$(read_conf_value "$DEFAULTS_CONF" "DefaultRCONPort" "27020")
    def_maxp=$(read_conf_value "$DEFAULTS_CONF" "DefaultMaxPlayers" "70")
    def_adminpw=$(read_conf_value "$DEFAULTS_CONF" "DefaultAdminPassword" "")

    # Auto-increment ports if other maps exist
    local existing_maps
    existing_maps=( $(get_maps) )
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
    echo "  ${BLD}Configure ${CYN}${display_name}${R}${BLD}:${R}  ${DIM}(press Enter for default, 0 = cancel)${R}"
    thin_sep

    local game_port query_port rcon_port max_players admin_pw server_pw mod_ids
    read_input "Game Port" "$def_port" game_port || return 0
    read_input "Query Port" "$def_qport" query_port || return 0
    read_input "RCON Port" "$def_rport" rcon_port || return 0
    read_input "Max Players" "$def_maxp" max_players || return 0
    read_input "Admin Password" "$def_adminpw" admin_pw || return 0
    read_input "Server Password (empty=public)" "" server_pw || return 0
    read_input "Mod IDs (comma-separated)" "" mod_ids || return 0

    echo ""

    # Create map directory
    mkdir -p "$MAPS_DIR/$display_name/backups"

    cat > "$MAPS_DIR/$display_name/map.conf" <<EOF
# Map Configuration: $display_name
MapName=$internal_name
DisplayName=$display_name
SaveDir=$display_name
GamePort=$game_port
QueryPort=$query_port
RCONPort=$rcon_port
MaxPlayers=$max_players
AdminPassword=$admin_pw
ServerPassword=$server_pw
ModIDs=$mod_ids
CustomStartParams=$(read_conf_value "$DEFAULTS_CONF" "DefaultStartParams" "-NoBattlEye -crossplay -NoHangDetection")
ClusterID=$(read_conf_value "$DEFAULTS_CONF" "ClusterID" "")
EOF

    create_optimized_game_settings "$MAPS_DIR/$display_name" "high"

    [[ ! -f "$MAPS_DIR/$display_name/Game.ini" ]] && touch "$MAPS_DIR/$display_name/Game.ini"

    echo "${display_name}|${internal_name}|enabled" >> "$MAPS_CONF"

    create_systemd_service "$display_name"
    open_firewall_ports "$game_port" "$query_port" "$rcon_port"

    log_ok "Map '${BLD}$display_name${R}${GRN}' created and ready!"
    echo "  ${DIM}Start it from the dashboard or run: ${WHT}./ark-manager.sh start ${display_name}${R}"
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
#  GRAPHICS PRESET MANAGEMENT
#═══════════════════════════════════════════════════════════════════════════════

apply_graphics_preset() {
    local map="$1"
    local preset="$2"
    local ini="$MAPS_DIR/$map/GameUserSettings.ini"

    [[ ! -f "$ini" ]] && { log_err "GameUserSettings.ini not found for '$map'."; return 1; }

    local sg_val adv_q res_x res_y scr_pct fps_lim
    local b_dfao b_ssao b_bloom b_dist_ao b_hi_aniso
    local b_foot_dec b_foot_part b_fluid b_low_vfx b_prev_det
    local gnd_dens gnd_rad hfs_q lod_s
    local b_hi_mat b_hi_surf b_hi_lod b_ext_stream b_color_grad
    local b_dyn_res b_low_stream
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
            gui3d_q="0.000000"; aud_q=0; tiles=5; b_dis_shad=True
            ;;
        medium)
            sg_val=2; adv_q=2; res_x=1280; res_y=720; scr_pct="75.000000"; fps_lim="60.000000"
            b_dfao=False; b_ssao=True; b_bloom=False; b_dist_ao=False; b_hi_aniso=False
            b_foot_dec=True; b_foot_part=True; b_fluid=False; b_low_vfx=False; b_prev_det=False
            gnd_dens=50; gnd_rad=5000; hfs_q=2; lod_s="1.0"
            b_hi_mat=False; b_hi_surf=False; b_hi_lod=False; b_ext_stream=False; b_color_grad=True
            b_dyn_res=False; b_low_stream=False
            fol_dist="0.500000"; fol_limit="1.000000"; fol_qty="0.500000"
            gui3d_q="50.000000"; aud_q=1; tiles=10; b_dis_shad=False
            ;;
        high)
            sg_val=3; adv_q=3; res_x=1920; res_y=1080; scr_pct="100.000000"; fps_lim="0.000000"
            b_dfao=True; b_ssao=True; b_bloom=False; b_dist_ao=True; b_hi_aniso=True
            b_foot_dec=True; b_foot_part=True; b_fluid=True; b_low_vfx=False; b_prev_det=False
            gnd_dens=100; gnd_rad=10000; hfs_q=3; lod_s="1.0"
            b_hi_mat=True; b_hi_surf=True; b_hi_lod=True; b_ext_stream=True; b_color_grad=True
            b_dyn_res=False; b_low_stream=False
            fol_dist="1.000000"; fol_limit="1.000000"; fol_qty="1.000000"
            gui3d_q="100.000000"; aud_q=2; tiles=20; b_dis_shad=False
            ;;
        auto)
            sg_val=3; adv_q=3; res_x=1920; res_y=1080; scr_pct="100.000000"; fps_lim="0.000000"
            b_dfao=True; b_ssao=True; b_bloom=False; b_dist_ao=True; b_hi_aniso=True
            b_foot_dec=True; b_foot_part=True; b_fluid=True; b_low_vfx=False; b_prev_det=False
            gnd_dens=100; gnd_rad=10000; hfs_q=3; lod_s="1.0"
            b_hi_mat=True; b_hi_surf=True; b_hi_lod=True; b_ext_stream=True; b_color_grad=True
            b_dyn_res=True; b_low_stream=False
            fol_dist="1.000000"; fol_limit="1.000000"; fol_qty="1.000000"
            gui3d_q="100.000000"; aud_q=2; tiles=20; b_dis_shad=False
            ;;
        *) log_err "Unknown preset: $preset (use: low, medium, high, auto)"; return 1 ;;
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
    local conf="$MAPS_DIR/$map/map.conf"
    local current_preset
    current_preset=$(read_conf_value "$conf" "GraphicsPreset" "high")

    echo ""
    echo "  ${BLD}${MAG}═══ Graphics Preset — ${CYN}$map${MAG} ═══${R}"
    thin_sep
    echo "  Current: ${BLD}${CYN}$current_preset${R}"
    echo ""
    echo "  ${CYN}1${R}) ${RED}Low${R}       ${DIM}— Max performance, 640×480, 30fps cap, all effects off${R}"
    echo "  ${CYN}2${R}) ${YEL}Medium${R}    ${DIM}— Balanced, 1280×720, 60fps cap${R}"
    echo "  ${CYN}3${R}) ${GRN}High${R}      ${DIM}— Max quality, 1920×1080, unlimited fps${R}"
    echo "  ${CYN}4${R}) ${BLU}Auto${R}      ${DIM}— High + dynamic resolution (auto-adjusts)${R}"
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

[Install]
WantedBy=multi-user.target
SVCEOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name" 2>/dev/null || true
    log_ok "Service '${BLD}$service_name${R}${GRN}' created and enabled."
}

open_firewall_ports() {
    local game_port="$1" query_port="$2" rcon_port="$3"
    if command -v ufw &>/dev/null; then
        sudo ufw allow "${game_port}/udp" 2>/dev/null || true
        sudo ufw allow "$(( game_port + 1 ))/udp" 2>/dev/null || true
        sudo ufw allow "${query_port}/udp" 2>/dev/null || true
        sudo ufw allow "${rcon_port}/tcp" 2>/dev/null || true
        log_ok "Firewall ports opened: ${BLD}${game_port}-$(( game_port + 1 ))/udp, ${query_port}/udp, ${rcon_port}/tcp${R}"
    fi
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
    local admin_pw server_pw mod_ids custom_params cluster_id
    map_name=$(read_conf_value "$conf" "MapName")
    save_dir=$(read_conf_value "$conf" "SaveDir" "$map")
    game_port=$(read_conf_value "$conf" "GamePort" "7777")
    query_port=$(read_conf_value "$conf" "QueryPort" "27015")
    rcon_port=$(read_conf_value "$conf" "RCONPort" "27020")
    max_players=$(read_conf_value "$conf" "MaxPlayers" "70")
    admin_pw=$(read_conf_value "$conf" "AdminPassword" "")
    server_pw=$(read_conf_value "$conf" "ServerPassword" "")
    mod_ids=$(read_conf_value "$conf" "ModIDs" "")
    custom_params=$(read_conf_value "$conf" "CustomStartParams" "-NoBattlEye -crossplay -NoHangDetection")
    cluster_id=$(read_conf_value "$conf" "ClusterID" "")

    if ss -lunp 2>/dev/null | grep -q ":${game_port} "; then
        log_err "Port ${BLD}$game_port${R} is already in use!"
        return 1
    fi

    log_info "Starting map: ${BLD}$map${R} (${CYN}$map_name${R})..."

    export STEAM_COMPAT_DATA_PATH="$SERVER_DIR/steamapps/compatdata/$ARK_APPID"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAMCMD_DIR"
    export SteamAppId=$ARK_APPID
    export SteamGameId=$ARK_APPID

    # Link config directory
    local config_src="$MAPS_DIR/$map"
    local config_dst="$SERVER_DIR/ShooterGame/Saved/Config/WindowsServer"
    if [[ -d "$config_dst" && ! -L "$config_dst" ]]; then
        mv "$config_dst" "${config_dst}.bak.$(date +%s)" || true
    fi
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
    local use_null
    use_null=$(read_conf_value "$OPT_CONF" "UseNullRHI" "true")
    [[ "$use_null" == "true" ]] && nullrhi="-nullrhi"

    local nice_lvl
    nice_lvl=$(read_conf_value "$OPT_CONF" "ServerNiceLevel" "-5")

    nice $nice_lvl "$PROTON_DIR/proton" run \
        "$SERVER_DIR/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" \
        "${map_name}?listen?SessionName=${map} ?ServerPassword=${server_pw}?RCONEnabled=True?ServerAdminPassword=${admin_pw}?AltSaveDirectoryName=${save_dir}" \
        $custom_params \
        $nullrhi \
        -WinLiveMaxPlayers=$max_players \
        -Port=$game_port \
        -QueryPort=$query_port \
        -RCONPort=$rcon_port \
        -game \
        $cluster_args \
        -server \
        -log \
        -mods="$mod_ids" \
        > "$MAPS_DIR/$map/server.log" 2>&1 &

    log_ok "Map '${BLD}$map${R}${GRN}' starting... Should be online in ~60 seconds."
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
        log_info "Server acknowledged exit. Waiting for graceful shutdown..."
        local waited=0
        while pgrep -f "ArkAscendedServer.exe.*AltSaveDirectoryName=${save_dir}" &>/dev/null; do
            sleep 2
            (( waited += 2 ))
            if (( waited >= 120 )); then
                log_warn "Timeout after ${waited}s. Force killing..."
                pkill -9 -f "ArkAscendedServer.exe.*AltSaveDirectoryName=${save_dir}" || true
                break
            fi
        done
    else
        log_warn "RCON graceful exit failed. Force stopping..."
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
    local maps
    maps=( $(get_maps) )
    (( ${#maps[@]} == 0 )) && { log_warn "No maps configured."; return; }
    for map in "${maps[@]}"; do
        start_map "$map"
        sleep 5
    done
}

stop_all_maps() {
    local maps
    maps=( $(get_maps) )
    for map in "${maps[@]}"; do
        is_map_running "$map" && stop_map "$map"
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  RCON
#═══════════════════════════════════════════════════════════════════════════════

rcon_console() {
    local map="$1"
    if ! is_map_running "$map"; then
        log_err "Map '${BLD}$map${R}' is not running."
        return 1
    fi
    local rcon_port admin_pw
    rcon_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "RCONPort" "27020")
    admin_pw=$(read_conf_value "$MAPS_DIR/$map/map.conf" "AdminPassword" "")
    log_info "Connecting RCON to ${BLD}$map${R} on port ${CYN}$rcon_port${R}..."
    echo "  ${DIM}Type 'exit' or Ctrl+C to disconnect${R}"
    python3 "$RCON_SCRIPT" "localhost:$rcon_port" -p "$admin_pw"
}

send_rcon() {
    local map="$1" cmd="$2"
    if ! is_map_running "$map"; then
        log_err "Map '${BLD}$map${R}' is not running."
        return 1
    fi
    local rcon_port admin_pw
    rcon_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "RCONPort" "27020")
    admin_pw=$(read_conf_value "$MAPS_DIR/$map/map.conf" "AdminPassword" "")
    python3 "$RCON_SCRIPT" "localhost:$rcon_port" -p "$admin_pw" -c "$cmd"
}

broadcast_message() {
    local message="$1"
    local maps
    maps=( $(get_maps) )
    for map in "${maps[@]}"; do
        is_map_running "$map" && send_rcon "$map" "ServerChat $message" 2>/dev/null || true
    done
    log_ok "Broadcast sent to all running maps."
}

#═══════════════════════════════════════════════════════════════════════════════
#  MOD MANAGEMENT (proper loop with back)
#═══════════════════════════════════════════════════════════════════════════════

manage_mods() {
    local map="$1"
    local conf="$MAPS_DIR/$map/map.conf"

    while true; do
        local current_mods
        current_mods=$(read_conf_value "$conf" "ModIDs" "")

        echo ""
        echo "  ${BLD}${MAG}═══ Mod Management — ${CYN}$map${MAG} ═══${R}"
        thin_sep
        if [[ -n "$current_mods" ]]; then
            echo "  Installed: ${CYN}${BLD}$current_mods${R}"
        else
            echo "  ${DIM}No mods installed.${R}"
        fi
        echo ""
        echo "  ${CYN}1${R}) Add mod(s)"
        echo "  ${CYN}2${R}) Remove mod(s)"
        echo "  ${CYN}3${R}) Clear all mods"
        echo ""
        echo "  ${DIM}0) Back${R}"
        echo ""
        echo -n "  ${WHT}Choice: ${R}"
        read -r choice

        case "$choice" in
            1)
                echo -n "  ${WHT}Mod ID(s) to add (comma-separated): ${R}"
                read -r new_mods
                [[ -z "$new_mods" ]] && continue
                if [[ -n "$current_mods" ]]; then
                    current_mods="${current_mods},${new_mods}"
                else
                    current_mods="$new_mods"
                fi
                write_conf_value "$conf" "ModIDs" "$current_mods"
                log_ok "Mods updated. Restart to apply."
                ;;
            2)
                echo -n "  ${WHT}Mod ID(s) to remove (comma-separated): ${R}"
                read -r remove_mods
                [[ -z "$remove_mods" ]] && continue
                IFS=',' read -ra remove_arr <<< "$remove_mods"
                IFS=',' read -ra current_arr <<< "$current_mods"
                local new_arr=()
                for mod in "${current_arr[@]}"; do
                    local keep=true
                    for rm_mod in "${remove_arr[@]}"; do
                        [[ "$mod" == "$rm_mod" ]] && keep=false
                    done
                    $keep && new_arr+=("$mod")
                done
                local result
                result=$(IFS=,; echo "${new_arr[*]}")
                write_conf_value "$conf" "ModIDs" "$result"
                log_ok "Mods updated. Restart to apply."
                ;;
            3)
                if confirm "Clear all mods?"; then
                    write_conf_value "$conf" "ModIDs" ""
                    log_ok "All mods cleared. Restart to apply."
                fi
                ;;
            0|"") return ;;
            *) log_err "Invalid choice." ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  SERVER SETTINGS (per-map, with back on empty input + file access)
#═══════════════════════════════════════════════════════════════════════════════

server_settings_menu() {
    local map="$1"
    local gus="$MAPS_DIR/$map/GameUserSettings.ini"

    while true; do
        echo ""
        echo "  ${BLD}${MAG}═══ Server Settings — ${CYN}$map${MAG} ═══${R}"
        thin_sep

        local xp taming harvest respawn mating baby hatch stack
        local max_tamed auto_save max_struct
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
        printf "  ${CYN} 1${R}) XP Multiplier             : ${BLD}${WHT}%s${R}\n" "$xp"
        printf "  ${CYN} 2${R}) Taming Speed               : ${BLD}${WHT}%s${R}\n" "$taming"
        printf "  ${CYN} 3${R}) Harvest Amount              : ${BLD}${WHT}%s${R}\n" "$harvest"
        printf "  ${CYN} 4${R}) Resource Respawn            : ${BLD}${WHT}%s${R}\n" "$respawn"
        printf "  ${CYN} 5${R}) Mating Interval             : ${BLD}${WHT}%s${R}\n" "$mating"
        printf "  ${CYN} 6${R}) Baby Mature Speed           : ${BLD}${WHT}%s${R}\n" "$baby"
        printf "  ${CYN} 7${R}) Egg Hatch Speed             : ${BLD}${WHT}%s${R}\n" "$hatch"
        printf "  ${CYN} 8${R}) Item Stack Size             : ${BLD}${WHT}%s${R}\n" "$stack"
        echo ""
        echo "  ${BLD}${WHT}  Limits${R}"
        printf "  ${CYN} 9${R}) Max Tamed Dinos             : ${BLD}${WHT}%s${R}\n" "$max_tamed"
        printf "  ${CYN}10${R}) Auto-Save Interval (min)    : ${BLD}${WHT}%s${R}\n" "$auto_save"
        printf "  ${CYN}11${R}) Max Structures In Range     : ${BLD}${WHT}%s${R}\n" "$max_struct"
        echo ""
        echo "  ${BLD}${WHT}  Advanced${R}"
        echo "  ${CYN}12${R}) Graphics Preset              ${DIM}(low/medium/high/auto)${R}"
        echo "  ${CYN}13${R}) Edit GameUserSettings.ini    ${DIM}(nano)${R}"
        echo "  ${CYN}14${R}) Edit Game.ini                ${DIM}(nano)${R}"
        echo "  ${CYN}15${R}) Edit map.conf                ${DIM}(ports/passwords/params)${R}"
        echo ""
        echo "  ${DIM} 0) Back${R}"
        echo ""
        echo -n "  ${WHT}Choice: ${R}"
        read -r choice

        case "$choice" in
            1)  echo -n "  ${WHT}New XP Multiplier ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "XPMultiplier" "$val"; log_ok "Saved. Restart to apply."; } ;;
            2)  echo -n "  ${WHT}New Taming Speed ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "TamingSpeedMultiplier" "$val"; log_ok "Saved. Restart to apply."; } ;;
            3)  echo -n "  ${WHT}New Harvest Amount ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "HarvestAmountMultiplier" "$val"; log_ok "Saved. Restart to apply."; } ;;
            4)  echo -n "  ${WHT}New Resource Respawn ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "ResourcesRespawnPeriodMultiplier" "$val"; log_ok "Saved. Restart to apply."; } ;;
            5)  echo -n "  ${WHT}New Mating Interval ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "MatingIntervalMultiplier" "$val"; log_ok "Saved. Restart to apply."; } ;;
            6)  echo -n "  ${WHT}New Baby Mature Speed ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "BabyMatureSpeedMultiplier" "$val"; log_ok "Saved. Restart to apply."; } ;;
            7)  echo -n "  ${WHT}New Egg Hatch Speed ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "EggHatchSpeedMultiplier" "$val"; log_ok "Saved. Restart to apply."; } ;;
            8)  echo -n "  ${WHT}New Item Stack Size ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "ItemStackSizeMultiplier" "$val"; log_ok "Saved. Restart to apply."; } ;;
            9)  echo -n "  ${WHT}New Max Tamed Dinos ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "MaxTamedDinos" "$val"; log_ok "Saved. Restart to apply."; } ;;
            10) echo -n "  ${WHT}New Auto-Save (min) ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "AutoSavePeriodMinutes" "$val"; log_ok "Saved. Restart to apply."; } ;;
            11) echo -n "  ${WHT}New Max Structures ${DIM}(empty=cancel)${R}: "; read -r val
                [[ -n "$val" ]] && { write_conf_value "$gus" "TheMaxStructuresInRange" "$val"; log_ok "Saved. Restart to apply."; } ;;
            12) graphics_preset_menu "$map" ;;
            13) ${EDITOR:-nano} "$gus" ;;
            14) ${EDITOR:-nano} "$MAPS_DIR/$map/Game.ini" ;;
            15) ${EDITOR:-nano} "$MAPS_DIR/$map/map.conf" ;;
            0|"") return ;;
            *) log_err "Invalid choice." ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  BACKUP & RESTORE
#═══════════════════════════════════════════════════════════════════════════════

backup_map() {
    local map="$1"
    local save_dir
    save_dir=$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")
    local source="$SERVER_DIR/ShooterGame/Saved/SavedArks/$save_dir"
    local backup_dir="$MAPS_DIR/$map/backups"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/${map}_${timestamp}.tar.gz"

    [[ ! -d "$source" ]] && { log_err "No save data found for '${BLD}$map${R}'."; return 1; }

    mkdir -p "$backup_dir"
    log_info "Backing up '${BLD}$map${R}' saves..."
    tar -czf "$backup_file" -C "$SERVER_DIR/ShooterGame/Saved/SavedArks" "$save_dir"
    local size
    size=$(du -h "$backup_file" | cut -f1)
    log_ok "Backup created: ${DIM}$backup_file${R} (${BLD}$size${R})"
}

restore_map() {
    local map="$1"
    local backup_dir="$MAPS_DIR/$map/backups"

    if [[ ! -d "$backup_dir" ]] || [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        log_err "No backups found for '${BLD}$map${R}'."
        return 1
    fi

    if is_map_running "$map"; then
        log_err "Stop the map before restoring a backup!"
        return 1
    fi

    echo ""
    echo "  ${BLD}${MAG}═══ Restore Backup — ${CYN}$map${MAG} ═══${R}"
    thin_sep
    local backups=()
    local i=1
    for f in "$backup_dir"/*.tar.gz; do
        local size fname
        size=$(du -h "$f" | cut -f1)
        fname=$(basename "$f")
        printf "  ${CYN}%2d${R}) %-40s ${DIM}(%s)${R}\n" "$i" "$fname" "$size"
        backups+=("$f")
        ((i++))
    done
    echo ""
    echo "  ${DIM} 0) Back${R}"
    echo ""
    echo -n "  ${WHT}Select backup: ${R}"
    read -r choice

    [[ "$choice" == "0" || -z "$choice" ]] && return 0
    (( choice < 1 || choice > ${#backups[@]} )) 2>/dev/null && return 0

    local selected="${backups[$((choice-1))]}"
    local save_dir
    save_dir=$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")
    local target="$SERVER_DIR/ShooterGame/Saved/SavedArks"

    if confirm "This will overwrite current save data for '${BLD}$map${R}'. Continue?"; then
        log_info "Restoring backup..."
        rm -rf "$target/$save_dir"
        tar -xzf "$selected" -C "$target"
        log_ok "Backup restored for '${BLD}$map${R}'!"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  LOG VIEWER
#═══════════════════════════════════════════════════════════════════════════════

view_logs() {
    local map="$1"
    local log_file="$MAPS_DIR/$map/server.log"
    local steam_log="$HOME/steam-${ARK_APPID}.log"

    while true; do
        echo ""
        echo "  ${BLD}${MAG}═══ Logs — ${CYN}$map${MAG} ═══${R}"
        thin_sep
        echo "  ${CYN}1${R}) View server log ${DIM}(last 50 lines)${R}"
        echo "  ${CYN}2${R}) Follow server log ${DIM}(live — Ctrl+C to stop)${R}"
        echo "  ${CYN}3${R}) View Steam/Proton log"
        echo "  ${CYN}4${R}) View errors only"
        echo ""
        echo "  ${DIM}0) Back${R}"
        echo ""
        echo -n "  ${WHT}Choice: ${R}"
        read -r choice

        case "$choice" in
            1)
                if [[ -f "$log_file" ]]; then
                    echo ""; separator
                    tail -50 "$log_file"
                    separator
                else
                    log_warn "No log file found."
                fi
                press_enter
                ;;
            2)
                if [[ -f "$log_file" ]]; then
                    log_info "Press ${BLD}Ctrl+C${R} to stop following..."
                    tail -f "$log_file" || true
                else
                    log_warn "No log file found."
                fi
                ;;
            3)
                if [[ -f "$steam_log" ]]; then
                    separator
                    tail -80 "$steam_log"
                    separator
                else
                    log_warn "No Steam log found."
                fi
                press_enter
                ;;
            4)
                if [[ -f "$log_file" ]]; then
                    separator
                    grep -iE "error|fatal|crash|exception|fail" "$log_file" | tail -30 || log_info "No errors found."
                    separator
                else
                    log_warn "No log file found."
                fi
                press_enter
                ;;
            0|"") return ;;
            *) log_err "Invalid choice." ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  FILE BROWSER
#═══════════════════════════════════════════════════════════════════════════════

browse_files() {
    local map="$1"
    while true; do
        echo ""
        echo "  ${BLD}${MAG}═══ File Locations — ${CYN}$map${MAG} ═══${R}"
        thin_sep
        echo "  ${CYN}1${R}) Map config dir      ${DIM}$MAPS_DIR/$map/${R}"
        echo "  ${CYN}2${R}) Server log           ${DIM}$MAPS_DIR/$map/server.log${R}"
        echo "  ${CYN}3${R}) Save data            ${DIM}$SERVER_DIR/ShooterGame/Saved/SavedArks/$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")/${R}"
        echo "  ${CYN}4${R}) Backups              ${DIM}$MAPS_DIR/$map/backups/${R}"
        echo "  ${CYN}5${R}) Server files         ${DIM}$SERVER_DIR/${R}"
        echo "  ${CYN}6${R}) Open shell here"
        echo ""
        echo "  ${DIM}0) Back${R}"
        echo ""
        echo -n "  ${WHT}Choice: ${R}"
        read -r choice

        case "$choice" in
            1) echo ""; ls -la "$MAPS_DIR/$map/" 2>/dev/null; press_enter ;;
            2) [[ -f "$MAPS_DIR/$map/server.log" ]] && less "$MAPS_DIR/$map/server.log" || log_warn "No log file."; press_enter ;;
            3) ls -la "$SERVER_DIR/ShooterGame/Saved/SavedArks/$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")/" 2>/dev/null; press_enter ;;
            4) ls -la "$MAPS_DIR/$map/backups/" 2>/dev/null; press_enter ;;
            5) ls -la "$SERVER_DIR/" 2>/dev/null; press_enter ;;
            6) log_info "Dropping into shell at: ${BLD}$MAPS_DIR/$map/${R}"; cd "$MAPS_DIR/$map" && exec bash ;;
            0|"") return ;;
            *) log_err "Invalid choice." ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  DELETE MAP
#═══════════════════════════════════════════════════════════════════════════════

delete_map() {
    local map="$1"

    if is_map_running "$map"; then
        log_err "Stop the map first!"
        return 1
    fi

    echo ""
    log_warn "This will ${RED}${BLD}permanently delete${R} map '${BLD}$map${R}' and all its configuration."
    log_warn "Save data in server-files will ${BLD}NOT${R} be deleted."
    echo ""
    if confirm "Are you absolutely sure you want to delete '${BLD}$map${R}'?"; then
        local service_name="ark-${map,,}.service"
        sudo systemctl stop "$service_name" 2>/dev/null || true
        sudo systemctl disable "$service_name" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/$service_name"
        sudo systemctl daemon-reload

        sed -i "/^${map}|/d" "$MAPS_CONF"
        rm -rf "$MAPS_DIR/$map"

        log_ok "Map '${BLD}$map${R}${GRN}' deleted."
        return 0
    fi
    return 1
}

#═══════════════════════════════════════════════════════════════════════════════
#  CHANGE MAP TYPE
#═══════════════════════════════════════════════════════════════════════════════

change_map_type() {
    local map="$1"

    if is_map_running "$map"; then
        log_err "Stop the map before changing the map type!"
        return 1
    fi

    echo ""
    echo "  ${BLD}${MAG}═══ Change Map Type — ${CYN}$map${MAG} ═══${R}"
    thin_sep
    local i=1
    local map_keys=()
    for key in $(echo "${!MAP_NAMES[@]}" | tr ' ' '\n' | sort); do
        printf "  ${CYN}%2d${R}) %-20s  ${DIM}(%s)${R}\n" "$i" "$key" "${MAP_NAMES[$key]}"
        map_keys+=("$key")
        ((i++))
    done
    echo ""
    echo "  ${DIM} 0) Back${R}"
    echo ""
    echo -n "  ${WHT}Select new map: ${R}"
    read -r choice

    [[ "$choice" == "0" || -z "$choice" ]] && return 0

    if (( choice > 0 && choice <= ${#map_keys[@]} )) 2>/dev/null; then
        local new_internal="${MAP_NAMES[${map_keys[$((choice-1))]}]}"
        write_conf_value "$MAPS_DIR/$map/map.conf" "MapName" "$new_internal"
        log_ok "Map changed to ${BLD}${map_keys[$((choice-1))]}${R}${GRN} ($new_internal). Restart to apply."
    else
        log_err "Invalid selection."
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  OPTIMIZATION
#═══════════════════════════════════════════════════════════════════════════════

apply_optimizations() {
    log_info "Applying system optimizations..."

    if command -v sysctl &>/dev/null; then
        local sysctl_file="/etc/sysctl.d/99-ark-server.conf"
        sudo tee "$sysctl_file" > /dev/null <<'SYSEOF'
# ARK Server Optimizations
vm.swappiness=10
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.ipv4.udp_mem=65536 131072 262144
SYSEOF
        sudo sysctl --system -q 2>/dev/null || true
        log_ok "Kernel parameters optimized."
    fi

    setup_logrotate
    setup_healthcheck
    log_ok "All optimizations applied."
}

setup_logrotate() {
    local logrotate_conf="/etc/logrotate.d/ark-server"
    if command -v logrotate &>/dev/null; then
        sudo tee "$logrotate_conf" > /dev/null <<LREOF
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
        log_ok "Logrotate configured."
    fi
}

setup_healthcheck() {
    local hc_script="$SCRIPT_DIR/healthcheck.sh"
    cat > "$hc_script" <<'HCEOF'
#!/usr/bin/env bash
# ARK Server Healthcheck — run via cron every 5 minutes
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') [HEAL] $map is down, restarting..." >> "$LOG"
        systemctl restart "$service_name" 2>/dev/null || true
    fi
done
HCEOF
    chmod +x "$hc_script"

    local cron_line="*/5 * * * * $hc_script"
    if ! crontab -l 2>/dev/null | grep -qF "$hc_script"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        log_ok "Healthcheck cron installed (every 5 min)."
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  SCHEDULED RESTART
#═══════════════════════════════════════════════════════════════════════════════

setup_scheduled_restart() {
    echo ""
    echo "  ${BLD}${MAG}═══ Scheduled Restart Setup ═══${R}"
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
# ARK Scheduled Restart with Player Warnings
SCRIPT_DIR="\$(cd "\$(dirname "\$(realpath "\$0")")" && pwd)"
MANAGER="\$SCRIPT_DIR/ark-manager.sh"
LOG="\$SCRIPT_DIR/restart.log"

announce() {
    \$MANAGER broadcast "\$1" 2>/dev/null
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [RESTART] \$1" >> "\$LOG"
}

announce "Server restart in 30 minutes!"
sleep 1200
announce "Server restart in 10 minutes!"
sleep 420
announce "Server restart in 3 minutes! Save your progress!"
sleep 170
announce "Server restart in 10 seconds!"
sleep 10

echo "\$(date '+%Y-%m-%d %H:%M:%S') [RESTART] Restarting all maps..." >> "\$LOG"
\$MANAGER stop-all
sleep 10
\$MANAGER start-all
echo "\$(date '+%Y-%m-%d %H:%M:%S') [RESTART] All maps restarted." >> "\$LOG"
RSEOF
    chmod +x "$rs_script"

    local cron_min=$(( (minute - 30 + 60) % 60 ))
    local cron_hour=$hour
    (( minute < 30 )) && cron_hour=$(( (hour - 1 + 24) % 24 ))

    local cron_line="$cron_min $cron_hour * * * $rs_script"
    crontab -l 2>/dev/null | grep -vF "scheduled-restart.sh" | { cat; echo "$cron_line"; } | crontab -

    log_ok "Scheduled restart set for ${BLD}$restart_time${R}${GRN} daily (warnings start 30 min before)."
}

#═══════════════════════════════════════════════════════════════════════════════
#  INTERACTIVE MENUS
#═══════════════════════════════════════════════════════════════════════════════

select_map() {
    local maps
    maps=( $(get_maps) )
    if (( ${#maps[@]} == 0 )); then
        log_warn "No maps configured."
        return 1
    fi
    echo ""
    echo "  ${BLD}${WHT}Select a map:${R}"
    thin_sep
    local i=1
    for m in "${maps[@]}"; do
        local status_icon
        if is_map_running "$m"; then
            status_icon="${GRN}●${R}"
        else
            status_icon="${RED}●${R}"
        fi
        printf "  ${status_icon} ${CYN}%2d${R}) %s\n" "$i" "$m"
        ((i++))
    done
    echo ""
    echo "  ${DIM} 0) Back${R}"
    echo ""
    echo -n "  ${WHT}Choice: ${R}"
    read -r choice

    [[ "$choice" == "0" || -z "$choice" ]] && return 1

    if (( choice > 0 && choice <= ${#maps[@]} )) 2>/dev/null; then
        SELECTED_MAP="${maps[$((choice-1))]}"
        return 0
    fi
    log_err "Invalid selection."
    return 1
}

map_menu() {
    local map="$1"
    while true; do
        local internal health_raw status_text health_text
        internal=$(read_conf_value "$MAPS_DIR/$map/map.conf" "MapName" "?")
        health_raw=$(check_map_health "$map")

        if is_map_running "$map"; then
            status_text="${BG_GRN}${BLD}${WHT} ONLINE ${R}"
        else
            status_text="${BG_RED}${BLD}${WHT} OFFLINE ${R}"
        fi

        case "$health_raw" in
            HEALTHY)  health_text="${GRN}${BLD}HEALTHY${R}" ;;
            DEGRADED) health_text="${YEL}${BLD}DEGRADED${R}" ;;
            CRASHED)  health_text="${RED}${BLD}CRASHED${R}" ;;
            ZOMBIE)   health_text="${RED}${BLD}ZOMBIE${R}" ;;
            FROZEN)   health_text="${RED}${BLD}FROZEN${R}" ;;
            STOPPED)  health_text="${DIM}STOPPED${R}" ;;
            *)        health_text="${DIM}UNKNOWN${R}" ;;
        esac

        echo ""
        echo "  ${BLD}${BLU}╔═══════════════════════════════════════════╗${R}"
        echo "  ${BLD}${BLU}║${R}  ${BLD}${WHT}$map${R}  ${DIM}($internal)${R}"
        echo "  ${BLD}${BLU}╚═══════════════════════════════════════════╝${R}"
        echo "  Status: ${status_text}   Health: ${health_text}"

        if is_map_running "$map"; then
            local pc up mem
            pc=$(get_player_count "$map" 2>/dev/null || echo "?")
            up=$(get_map_uptime "$map")
            mem=$(get_map_memory "$map")
            echo "  Players: ${BLD}${pc}${R}  │  Uptime: ${BLD}${up}${R}  │  RAM: ${BLD}${mem}${R}"
        fi
        echo ""

        echo "  ${CYN} 1${R}) ${GRN}Start${R}                ${CYN} 7${R}) Backup World"
        echo "  ${CYN} 2${R}) ${RED}Stop${R}                 ${CYN} 8${R}) Restore Backup"
        echo "  ${CYN} 3${R}) ${YEL}Restart${R}              ${CYN} 9${R}) View Logs"
        echo "  ${CYN} 4${R}) RCON Console          ${CYN}10${R}) Browse Files"
        echo "  ${CYN} 5${R}) Server Settings       ${CYN}11${R}) Change Map Type"
        echo "  ${CYN} 6${R}) Mod Management        ${CYN}12${R}) ${RED}Delete Map${R}"
        echo ""
        echo "  ${DIM} 0) Back to Dashboard${R}"
        echo ""
        echo -n "  ${WHT}Choice: ${R}"
        read -r choice

        case "$choice" in
            1)  start_map "$map"; press_enter ;;
            2)  stop_map "$map"; press_enter ;;
            3)  restart_map "$map"; press_enter ;;
            4)  rcon_console "$map" ;;
            5)  server_settings_menu "$map" ;;
            6)  manage_mods "$map" ;;
            7)  backup_map "$map"; press_enter ;;
            8)  restore_map "$map" ;;
            9)  view_logs "$map" ;;
            10) browse_files "$map" ;;
            11) change_map_type "$map" ;;
            12) delete_map "$map" && return ;;
            0|"") return ;;
            *) log_err "Invalid choice." ;;
        esac
    done
}

main_menu() {
    while true; do
        show_dashboard

        echo "  ${BLD}${WHT}Actions:${R}"
        echo ""
        echo "  ${CYN} 1${R}) ${BLU}Select Map${R}           ${CYN} 7${R}) Broadcast Message"
        echo "  ${CYN} 2${R}) ${GRN}Add Map${R}              ${CYN} 8${R}) Scheduled Restarts"
        echo "  ${CYN} 3${R}) ${GRN}Start All Maps${R}       ${CYN} 9${R}) Apply Optimizations"
        echo "  ${CYN} 4${R}) ${RED}Stop All Maps${R}        ${CYN}10${R}) Global Defaults"
        echo "  ${CYN} 5${R}) Install / Update      ${CYN}11${R}) ${BLU}Live Dashboard${R} ${DIM}(auto-refresh)${R}"
        echo "  ${CYN} 6${R}) Send RCON Command"
        echo ""
        echo "  ${DIM} 0) Exit${R}"
        echo ""
        echo -n "  ${WHT}Choice: ${R}"
        read -r choice

        case "$choice" in
            1)  select_map && map_menu "$SELECTED_MAP" ;;
            2)  add_map; press_enter ;;
            3)  start_all_maps; press_enter ;;
            4)  stop_all_maps; press_enter ;;
            5)  install_server; press_enter ;;
            6)
                if select_map; then
                    echo -n "  ${WHT}RCON command: ${R}"
                    read -r cmd
                    [[ -n "$cmd" ]] && send_rcon "$SELECTED_MAP" "$cmd"
                    press_enter
                fi
                ;;
            7)
                echo -n "  ${WHT}Message: ${R}"
                read -r msg
                [[ -n "$msg" ]] && broadcast_message "$msg"
                press_enter
                ;;
            8)  setup_scheduled_restart; press_enter ;;
            9)  apply_optimizations; press_enter ;;
            10) ${EDITOR:-nano} "$DEFAULTS_CONF" ;;
            11) live_dashboard ;;
            0|"")
                echo ""
                echo "  ${GRN}${BLD}Goodbye! 🦖${R}"
                echo ""
                exit 0
                ;;
            *) log_err "Invalid choice." ;;
        esac
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  CLI INTERFACE (non-interactive)
#═══════════════════════════════════════════════════════════════════════════════

cli_status() {
    local maps
    maps=( $(get_maps) )
    if (( ${#maps[@]} == 0 )); then
        echo "No maps configured."
        return
    fi
    printf "${BLD}%-16s %-10s %-10s %-8s %-8s %-8s${R}\n" "MAP" "STATUS" "HEALTH" "PLAYERS" "UPTIME" "RAM"
    echo "────────────────────────────────────────────────────────────────"
    for map in "${maps[@]}"; do
        local status health players uptime mem
        if is_map_running "$map"; then status="${GRN}ONLINE${R}"; else status="${RED}OFFLINE${R}"; fi
        health=$(check_map_health "$map")
        case "$health" in
            HEALTHY)  health="${GRN}${health}${R}" ;;
            DEGRADED) health="${YEL}${health}${R}" ;;
            CRASHED|ZOMBIE|FROZEN) health="${RED}${health}${R}" ;;
            *)        health="${DIM}${health}${R}" ;;
        esac
        if is_map_running "$map"; then
            players=$(get_player_count "$map" 2>/dev/null || echo "?")
        else
            players="-"
        fi
        uptime=$(get_map_uptime "$map")
        mem=$(get_map_memory "$map")
        # Use echo for colored output — printf %s can't handle ANSI widths correctly
        local padmap padplayers paduptime padmem
        padmap=$(printf '%-16s' "$map")
        padplayers=$(printf '%-8s' "$players")
        paduptime=$(printf '%-8s' "$uptime")
        padmem=$(printf '%-8s' "$mem")
        echo "${padmap} ${status}     ${health}   ${padplayers} ${paduptime} ${padmem}"
    done
}

show_help() {
    echo ""
    echo "  ${BLD}ARK: Survival Ascended — Server Manager${R}  ${DIM}v${VERSION}${R}"
    echo ""
    echo "  ${BLD}Usage:${R} $(basename "$0") ${CYN}[command]${R} ${DIM}[arguments]${R}"
    echo ""
    echo "  ${BLD}Commands:${R}"
    echo "    ${CYN}(none)${R}              Interactive dashboard"
    echo "    ${CYN}install${R}             Install/update server files"
    echo "    ${CYN}start${R} <map>         Start a map"
    echo "    ${CYN}stop${R} <map>          Stop a map"
    echo "    ${CYN}restart${R} <map>       Restart a map"
    echo "    ${CYN}start-all${R}           Start all maps"
    echo "    ${CYN}stop-all${R}            Stop all maps"
    echo "    ${CYN}status${R}              Show all map statuses"
    echo "    ${CYN}update${R}              Alias for install"
    echo "    ${CYN}rcon${R} <map> \"cmd\"    Send RCON command"
    echo "    ${CYN}backup${R} <map>        Backup map world"
    echo "    ${CYN}broadcast${R} \"msg\"     Send message to all maps"
    echo "    ${CYN}help${R}                Show this help"
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
# Optimization Configuration
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
        rcon)
            [[ -n "${2:-}" ]] && [[ -n "${3:-}" ]] && send_rcon "$2" "${*:3}" || { echo "Usage: $0 rcon <map> \"command\""; exit 1; }
            ;;
        backup)           [[ -n "${2:-}" ]] && backup_map "$2" || { echo "Usage: $0 backup <map>"; exit 1; } ;;
        broadcast)        [[ -n "${2:-}" ]] && broadcast_message "${*:2}" || { echo "Usage: $0 broadcast \"message\""; exit 1; } ;;
        help|--help|-h)   show_help ;;
        *)                echo "Unknown command: $1"; show_help; exit 1 ;;
    esac
fi
