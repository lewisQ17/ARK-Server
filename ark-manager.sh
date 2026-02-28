#!/usr/bin/env bash
#═══════════════════════════════════════════════════════════════════════════════
#  ARK: Survival Ascended — Linux Server Manager
#  A clean, map-centered management tool for ASA dedicated servers.
#  https://github.com/lewisQ17/ARK-Server
#═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail
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

#───────────────────────────── Colors ─────────────────────────────────────────
R='\e[0m'       # Reset
RED='\e[31m'
GRN='\e[32m'
YEL='\e[33m'
BLU='\e[34m'
MAG='\e[35m'
CYN='\e[36m'
WHT='\e[97m'
DIM='\e[2m'
BOLD='\e[1m'
BG_GRN='\e[42m'
BG_RED='\e[41m'
BG_YEL='\e[43m'
BG_BLU='\e[44m'

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

log_info()  { echo -e "${CYN}[INFO]${R}  $*"; }
log_ok()    { echo -e "${GRN}[OK]${R}    $*"; }
log_warn()  { echo -e "${YEL}[WARN]${R}  $*"; }
log_err()   { echo -e "${RED}[ERROR]${R} $*"; }

separator() {
    echo -e "${DIM}────────────────────────────────────────────────────────────────${R}"
}

confirm() {
    local msg="${1:-Continue?}"
    echo -ne "${YEL}${msg} [y/N]: ${R}"
    read -r ans
    [[ "$ans" =~ ^[Yy] ]]
}

press_enter() {
    echo -ne "${DIM}Press Enter to continue...${R}"
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
#  DEPENDENCY CHECK & INSTALL
#═══════════════════════════════════════════════════════════════════════════════

check_dependencies() {
    local missing=()
    local deps=(wget tar grep python3 curl cron)

    # Check for 32-bit libs on apt systems
    if command -v apt-get &>/dev/null; then
        for pkg in libc6:i386 libstdc++6:i386 libncursesw6:i386 libfreetype6:i386 libfreetype6:amd64; do
            if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
                missing+=("$pkg")
            fi
        done
    fi

    for cmd in "${deps[@]}"; do
        if [[ "$cmd" == "cron" ]]; then
            if ! command -v crontab &>/dev/null; then
                missing+=("cron")
            fi
        elif ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
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
            log_err "Map '$mname' is running. Stop all maps before updating."
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
        log_info "Downloading $PROTON_VERSION..."
        wget -q --show-progress -O "$PROTON_DIR/$PROTON_VERSION.tar.gz" "$PROTON_URL"
        tar -xzf "$PROTON_DIR/$PROTON_VERSION.tar.gz" -C "$PROTON_DIR" --strip-components=1
        rm -f "$PROTON_DIR/$PROTON_VERSION.tar.gz"
        log_ok "Proton installed."
    else
        log_ok "Proton already present."
    fi

    # ─── ARK Dedicated Server ───
    log_info "Downloading / Updating ARK dedicated server (AppID $ARK_APPID)..."
    "$STEAMCMD_DIR/steamcmd.sh" \
        +force_install_dir "$SERVER_DIR" \
        +login anonymous \
        +@sSteamCmdForcePlatformType windows \
        +app_update $ARK_APPID validate \
        +quit

    # ─── Delete .pdb files to save space ───
    local pdb_count
    pdb_count=$(find "$SERVER_DIR" -name "*.pdb" 2>/dev/null | wc -l)
    if (( pdb_count > 0 )); then
        log_info "Removing $pdb_count .pdb debug files to save disk space..."
        find "$SERVER_DIR" -name "*.pdb" -delete
    fi

    # ─── Initialize Proton Prefix ───
    local compat_dir="$SERVER_DIR/steamapps/compatdata/$ARK_APPID"
    if [[ ! -d "$compat_dir/pfx" ]]; then
        log_info "Initializing Proton prefix..."
        mkdir -p "$compat_dir"
        cp -r "$PROTON_DIR/files/share/default_pfx/." "$compat_dir/"
        log_ok "Proton prefix initialized."
    fi

    # ─── Apply Optimizations ───
    apply_optimizations

    # ─── Create protonfixes config dir ───
    mkdir -p "$HOME/.config/protonfixes"

    log_ok "Server installation/update complete!"
    separator
    echo -e "  ${GRN}Next step:${R} Select ${BOLD}'Add Map'${R} from the menu to create your first map."
    separator
}

#═══════════════════════════════════════════════════════════════════════════════
#  MAP MANAGEMENT
#═══════════════════════════════════════════════════════════════════════════════

get_maps() {
    # Returns list of map directory names
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
    if ! is_map_running "$map"; then
        echo "0"
        return
    fi
    local rcon_port admin_pw
    rcon_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "RCONPort" "27020")
    admin_pw=$(read_conf_value "$MAPS_DIR/$map/map.conf" "AdminPassword" "")
    if [[ -z "$admin_pw" ]]; then
        admin_pw=$(read_conf_value "$DEFAULTS_CONF" "DefaultAdminPassword" "")
    fi
    local count
    count=$(python3 "$RCON_SCRIPT" "localhost:$rcon_port" -p "$admin_pw" -c "ListPlayers" 2>/dev/null | grep -c "^[0-9]" || echo "0")
    echo "$count"
}

check_map_health() {
    local map="$1"
    if ! is_map_running "$map"; then
        echo "STOPPED"
        return
    fi
    local pid
    pid=$(get_map_pid "$map")
    if [[ -z "$pid" ]]; then
        echo "CRASHED"
        return
    fi
    # Check if process is a zombie
    local state
    state=$(ps -o state= -p "$pid" 2>/dev/null || echo "?")
    case "$state" in
        Z*) echo "ZOMBIE" ;;
        T*) echo "FROZEN" ;;
        *)
            # Check ports
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
    if [[ -z "$pid" ]]; then
        echo "-"
        return
    fi
    local elapsed
    elapsed=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ -z "$elapsed" ]]; then
        echo "-"
        return
    fi
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
    if [[ -z "$pid" ]]; then
        echo "-"
        return
    fi
    # Get RSS in KB, convert to GB
    local rss
    rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ -z "$rss" ]] || (( rss == 0 )); then
        echo "-"
        return
    fi
    local mb=$(( rss / 1024 ))
    if (( mb > 1024 )); then
        printf "%.1fG" "$(echo "scale=1; $mb/1024" | bc)"
    else
        echo "${mb}M"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  DASHBOARD — the main view
#═══════════════════════════════════════════════════════════════════════════════

show_dashboard() {
    clear
    local maps
    maps=( $(get_maps) )

    # Header
    echo
    echo -e "  ${BOLD}${BLU}╔═══════════════════════════════════════════════════════════════╗${R}"
    echo -e "  ${BOLD}${BLU}║${R}     ${BOLD}${WHT}ARK: Survival Ascended — Server Manager${R}              ${BOLD}${BLU}║${R}"
    echo -e "  ${BOLD}${BLU}╚═══════════════════════════════════════════════════════════════╝${R}"
    echo

    # System info line
    local cpu_use mem_total mem_used disk_free
    cpu_use=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1 || echo "?")
    mem_total=$(free -g 2>/dev/null | awk '/Mem:/{print $2}' || echo "?")
    mem_used=$(free -g 2>/dev/null | awk '/Mem:/{print $3}' || echo "?")
    disk_free=$(df -h "$SCRIPT_DIR" 2>/dev/null | awk 'NR==2{print $4}' || echo "?")
    echo -e "  ${DIM}System: CPU ${cpu_use}% │ RAM ${mem_used}G/${mem_total}G │ Disk Free: ${disk_free}${R}"
    echo

    if (( ${#maps[@]} == 0 )); then
        echo -e "  ${DIM}No maps configured yet. Use 'Add Map' to get started.${R}"
    else
        # Table header
        printf "  ${BOLD}%-16s %-10s %-10s %-8s %-8s %-8s %-12s${R}\n" \
            "MAP" "STATUS" "HEALTH" "PLAYERS" "UPTIME" "RAM" "PORTS"
        separator

        for map in "${maps[@]}"; do
            local internal_map game_port query_port rcon_port
            internal_map=$(read_conf_value "$MAPS_DIR/$map/map.conf" "MapName" "?")
            game_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "GamePort" "?")
            query_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "QueryPort" "?")
            rcon_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "RCONPort" "?")

            local status health players uptime mem_use ports
            if is_map_running "$map"; then
                status="${BG_GRN}${WHT} ONLINE ${R}"
            else
                status="${BG_RED}${WHT}OFFLINE${R} "
            fi
            health=$(check_map_health "$map")
            case "$health" in
                HEALTHY)  health="${GRN}${health}${R}" ;;
                DEGRADED) health="${YEL}${health}${R}" ;;
                CRASHED|ZOMBIE|FROZEN) health="${RED}${health}${R}" ;;
                STOPPED)  health="${DIM}${health}${R}" ;;
            esac

            if is_map_running "$map"; then
                players=$(get_player_count "$map" 2>/dev/null || echo "?")
                local max_p
                max_p=$(read_conf_value "$MAPS_DIR/$map/map.conf" "MaxPlayers" "70")
                players="${players}/${max_p}"
            else
                players="${DIM}-${R}"
            fi

            uptime=$(get_map_uptime "$map")
            mem_use=$(get_map_memory "$map")
            ports="${game_port}/${query_port}"

            printf "  %-16s %-19s %-19s %-8s %-8s %-8s %-12s\n" \
                "$map" "$status" "$health" "$players" "$uptime" "$mem_use" "$ports"
        done
    fi

    echo
    separator
}

#═══════════════════════════════════════════════════════════════════════════════
#  ADD MAP
#═══════════════════════════════════════════════════════════════════════════════

add_map() {
    echo
    log_info "Available ARK maps:"
    echo
    local i=1
    local map_keys=()
    for key in $(echo "${!MAP_NAMES[@]}" | tr ' ' '\n' | sort); do
        printf "  ${CYN}%2d${R}) %-20s  ${DIM}(%s)${R}\n" "$i" "$key" "${MAP_NAMES[$key]}"
        map_keys+=("$key")
        ((i++))
    done
    echo -e "  ${CYN}%2d${R}) Custom map name\n" "$i"
    echo

    echo -ne "  ${WHT}Select map number: ${R}"
    read -r choice

    local display_name internal_name
    if (( choice > 0 && choice <= ${#map_keys[@]} )); then
        display_name="${map_keys[$((choice-1))]}"
        internal_name="${MAP_NAMES[$display_name]}"
    elif (( choice == i )); then
        echo -ne "  ${WHT}Enter custom map name (display): ${R}"
        read -r display_name
        echo -ne "  ${WHT}Enter internal map name (e.g. MyMap_WP): ${R}"
        read -r internal_name
    else
        log_err "Invalid selection."
        return 1
    fi

    # Check if already exists
    if [[ -d "$MAPS_DIR/$display_name" ]]; then
        log_err "Map '$display_name' already exists."
        return 1
    fi

    # Get defaults
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
        # Next available ports (increment by 2 for game port since it uses port and port+1)
        def_port=$(( max_gport + 2 ))
        def_qport=$(( max_qport + 1 ))
        def_rport=$(( max_rport + 1 ))
    fi

    echo
    echo -e "  ${BOLD}Configure ${display_name}:${R}"
    echo -ne "  Game Port [$def_port]: "; read -r input; local game_port="${input:-$def_port}"
    echo -ne "  Query Port [$def_qport]: "; read -r input; local query_port="${input:-$def_qport}"
    echo -ne "  RCON Port [$def_rport]: "; read -r input; local rcon_port="${input:-$def_rport}"
    echo -ne "  Max Players [$def_maxp]: "; read -r input; local max_players="${input:-$def_maxp}"
    echo -ne "  Admin Password [$def_adminpw]: "; read -r input; local admin_pw="${input:-$def_adminpw}"
    echo -ne "  Server Password (empty=public) []: "; read -r server_pw
    echo -ne "  Mod IDs (comma-separated) []: "; read -r mod_ids
    echo

    # Create map directory
    mkdir -p "$MAPS_DIR/$display_name/backups"

    # Create map.conf
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

    # Copy/create GameUserSettings.ini with optimized defaults
    create_optimized_game_settings "$MAPS_DIR/$display_name" "high"

    # Create empty Game.ini
    if [[ ! -f "$MAPS_DIR/$display_name/Game.ini" ]]; then
        touch "$MAPS_DIR/$display_name/Game.ini"
    fi

    # Register in maps.conf
    echo "${display_name}|${internal_name}|enabled" >> "$MAPS_CONF"

    # Create systemd service
    create_systemd_service "$display_name"

    # Open firewall ports
    open_firewall_ports "$game_port" "$query_port" "$rcon_port"

    log_ok "Map '$display_name' created and ready!"
    echo -e "  ${DIM}Start it from the dashboard or run: ${SCRIPT_DIR}/ark-manager.sh start ${display_name}${R}"
}

create_optimized_game_settings() {
    local map_dir="$1"
    local preset="${2:-high}"   # Graphics preset: low, medium, high, auto
    local ini_file="$map_dir/GameUserSettings.ini"

    # Store preset in map.conf
    if [[ -f "$map_dir/map.conf" ]]; then
        write_conf_value "$map_dir/map.conf" "GraphicsPreset" "$preset"
    fi

    # Load rates from defaults
    local xp taming harvest respawn mating baby hatch
    xp=$(read_conf_value "$DEFAULTS_CONF" "XPMultiplier" "1.0")
    taming=$(read_conf_value "$DEFAULTS_CONF" "TamingSpeedMultiplier" "1.0")
    harvest=$(read_conf_value "$DEFAULTS_CONF" "HarvestAmountMultiplier" "1.0")
    respawn=$(read_conf_value "$DEFAULTS_CONF" "ResourceRespawnPeriodMultiplier" "1.0")
    mating=$(read_conf_value "$DEFAULTS_CONF" "MatingIntervalMultiplier" "1.0")
    baby=$(read_conf_value "$DEFAULTS_CONF" "BabyMatureSpeedMultiplier" "1.0")
    hatch=$(read_conf_value "$DEFAULTS_CONF" "EggHatchSpeedMultiplier" "1.0")

    # Load display settings
    local show_loc tp cross
    show_loc=$(read_conf_value "$DEFAULTS_CONF" "ShowMapPlayerLocation" "True")
    tp=$(read_conf_value "$DEFAULTS_CONF" "AllowThirdPersonPlayer" "True")
    cross=$(read_conf_value "$DEFAULTS_CONF" "ServerCrosshair" "True")

    # Load admin password and RCON port from map config
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

    if [[ ! -f "$ini" ]]; then
        log_err "GameUserSettings.ini not found for '$map'."
        return 1
    fi

    local sg_val adv_q res_x res_y scr_pct fps_lim
    local b_dfao b_ssao b_bloom b_dist_ao b_hi_aniso
    local b_foot_dec b_foot_part b_fluid b_low_vfx b_prev_det
    local gnd_dens gnd_rad hfs_q lod_s
    local b_hi_mat b_hi_surf b_hi_lod b_ext_stream b_color_grad
    local b_dyn_res b_low_stream
    local fol_dist fol_limit fol_qty gui3d_q aud_q tiles b_dis_shad

    case "$preset" in
        low)
            sg_val=0; adv_q=0
            res_x=640; res_y=480; scr_pct="0.100000"; fps_lim="30.000000"
            b_dfao=False; b_ssao=False; b_bloom=True; b_dist_ao=False
            b_hi_aniso=False; b_foot_dec=False; b_foot_part=False; b_fluid=False
            b_low_vfx=True; b_prev_det=True; gnd_dens=0; gnd_rad=0; hfs_q=0; lod_s="0.5"
            b_hi_mat=False; b_hi_surf=False; b_hi_lod=False; b_ext_stream=False; b_color_grad=False
            b_dyn_res=False; b_low_stream=True
            fol_dist="0.010000"; fol_limit="0.100000"; fol_qty="0.100000"
            gui3d_q="0.000000"; aud_q=0; tiles=5; b_dis_shad=True
            ;;
        medium)
            sg_val=2; adv_q=2
            res_x=1280; res_y=720; scr_pct="75.000000"; fps_lim="60.000000"
            b_dfao=False; b_ssao=True; b_bloom=False; b_dist_ao=False
            b_hi_aniso=False; b_foot_dec=True; b_foot_part=True; b_fluid=False
            b_low_vfx=False; b_prev_det=False; gnd_dens=50; gnd_rad=5000; hfs_q=2; lod_s="1.0"
            b_hi_mat=False; b_hi_surf=False; b_hi_lod=False; b_ext_stream=False; b_color_grad=True
            b_dyn_res=False; b_low_stream=False
            fol_dist="0.500000"; fol_limit="1.000000"; fol_qty="0.500000"
            gui3d_q="50.000000"; aud_q=1; tiles=10; b_dis_shad=False
            ;;
        high)
            sg_val=3; adv_q=3
            res_x=1920; res_y=1080; scr_pct="100.000000"; fps_lim="0.000000"
            b_dfao=True; b_ssao=True; b_bloom=False; b_dist_ao=True
            b_hi_aniso=True; b_foot_dec=True; b_foot_part=True; b_fluid=True
            b_low_vfx=False; b_prev_det=False; gnd_dens=100; gnd_rad=10000; hfs_q=3; lod_s="1.0"
            b_hi_mat=True; b_hi_surf=True; b_hi_lod=True; b_ext_stream=True; b_color_grad=True
            b_dyn_res=False; b_low_stream=False
            fol_dist="1.000000"; fol_limit="1.000000"; fol_qty="1.000000"
            gui3d_q="100.000000"; aud_q=2; tiles=20; b_dis_shad=False
            ;;
        auto)
            sg_val=3; adv_q=3
            res_x=1920; res_y=1080; scr_pct="100.000000"; fps_lim="0.000000"
            b_dfao=True; b_ssao=True; b_bloom=False; b_dist_ao=True
            b_hi_aniso=True; b_foot_dec=True; b_foot_part=True; b_fluid=True
            b_low_vfx=False; b_prev_det=False; gnd_dens=100; gnd_rad=10000; hfs_q=3; lod_s="1.0"
            b_hi_mat=True; b_hi_surf=True; b_hi_lod=True; b_ext_stream=True; b_color_grad=True
            b_dyn_res=True; b_low_stream=False
            fol_dist="1.000000"; fol_limit="1.000000"; fol_qty="1.000000"
            gui3d_q="100.000000"; aud_q=2; tiles=20; b_dis_shad=False
            ;;
        *)
            log_err "Unknown preset: $preset (use: low, medium, high, auto)"
            return 1
            ;;
    esac

    # Update ScalabilityGroups
    for key in ResolutionQuality ViewDistanceQuality AntiAliasingQuality ShadowQuality \
               GlobalIlluminationQuality ReflectionQuality PostProcessQuality TextureQuality \
               EffectsQuality FoliageQuality ShadingQuality LandscapeQuality; do
        sed -i "s/^sg\.${key}=.*/sg.${key}=$sg_val/" "$ini"
    done

    # Update ShooterGameUserSettings
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

    # Store preset in map.conf
    if [[ -f "$MAPS_DIR/$map/map.conf" ]]; then
        write_conf_value "$MAPS_DIR/$map/map.conf" "GraphicsPreset" "$preset"
    fi

    log_ok "Graphics preset '${BOLD}$preset${R}${GRN}' applied to $map. Restart to take effect."
}

graphics_preset_menu() {
    local map="$1"
    local conf="$MAPS_DIR/$map/map.conf"
    local current_preset
    current_preset=$(read_conf_value "$conf" "GraphicsPreset" "high")

    echo
    echo -e "  ${BOLD}Graphics Preset — $map${R}"
    separator
    echo -e "  Current preset: ${BOLD}${CYN}$current_preset${R}"
    echo
    echo -e "  ${CYN}1${R}) ${RED}Low${R}        ${DIM}— Max performance, all effects off, 640x480, 30fps cap${R}"
    echo -e "  ${CYN}2${R}) ${YEL}Medium${R}     ${DIM}— Balanced, basic effects, 1280x720, 60fps cap${R}"
    echo -e "  ${CYN}3${R}) ${GRN}High${R}       ${DIM}— Max quality, all effects on, 1920x1080, unlimited fps${R}"
    echo -e "  ${CYN}4${R}) ${BLU}Auto${R}       ${DIM}— High quality + dynamic resolution (auto-adjusts live!)${R}"
    echo -e "  ${CYN}5${R}) Back"
    echo
    echo -e "  ${DIM}Note: With -NullRHI (headless mode), the server does not render graphics.${R}"
    echo -e "  ${DIM}These settings affect quality values stored in GameUserSettings.ini.${R}"
    echo -e "  ${DIM}To disable headless mode, edit optimization.conf → UseNullRHI=false${R}"
    echo
    echo -ne "  Choice: "
    read -r choice

    case "$choice" in
        1) apply_graphics_preset "$map" "low" ;;
        2) apply_graphics_preset "$map" "medium" ;;
        3) apply_graphics_preset "$map" "high" ;;
        4) apply_graphics_preset "$map" "auto" ;;
        5) return ;;
        *) log_err "Invalid choice." ;;
    esac
}

create_systemd_service() {
    local map="$1"
    local service_name="ark-${map,,}.service"  # lowercase
    local service_file="/etc/systemd/system/$service_name"

    log_info "Creating systemd service: $service_name"

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
    log_ok "Service '$service_name' created and enabled."
}

open_firewall_ports() {
    local game_port="$1" query_port="$2" rcon_port="$3"
    if command -v ufw &>/dev/null; then
        sudo ufw allow "${game_port}/udp" 2>/dev/null || true
        sudo ufw allow "$(( game_port + 1 ))/udp" 2>/dev/null || true
        sudo ufw allow "${query_port}/udp" 2>/dev/null || true
        sudo ufw allow "${rcon_port}/tcp" 2>/dev/null || true
        log_ok "Firewall ports opened: ${game_port}-$(( game_port + 1 ))/udp, ${query_port}/udp, ${rcon_port}/tcp"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  START / STOP / RESTART
#═══════════════════════════════════════════════════════════════════════════════

start_map() {
    local map="$1"
    local conf="$MAPS_DIR/$map/map.conf"

    if [[ ! -f "$conf" ]]; then
        log_err "Map '$map' not found."
        return 1
    fi

    if is_map_running "$map"; then
        log_warn "Map '$map' is already running."
        return 0
    fi

    check_cpu_flags || return 1

    # Load config
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

    # Check for port conflicts
    if ss -lunp 2>/dev/null | grep -q ":${game_port} "; then
        log_err "Port $game_port is already in use!"
        return 1
    fi

    log_info "Starting map: $map ($map_name)..."

    # Set Proton environment
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

    # Ensure save directory exists
    mkdir -p "$SERVER_DIR/ShooterGame/Saved/SavedArks/$save_dir"

    # Cluster params
    local cluster_args=""
    if [[ -n "$cluster_id" ]]; then
        local cluster_dir="$SCRIPT_DIR/clusters/$cluster_id"
        mkdir -p "$cluster_dir"
        cluster_args="-ClusterDirOverride=\"$cluster_dir\" -ClusterId=\"$cluster_id\""
    fi

    # Use -nullrhi for headless (no GPU rendering)
    local nullrhi=""
    local use_null
    use_null=$(read_conf_value "$OPT_CONF" "UseNullRHI" "true")
    [[ "$use_null" == "true" ]] && nullrhi="-nullrhi"

    # Nice level
    local nice_lvl
    nice_lvl=$(read_conf_value "$OPT_CONF" "ServerNiceLevel" "-5")

    # Start with Proton
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

    log_ok "Map '$map' starting... Should be online in ~60 seconds."
}

stop_map() {
    local map="$1"
    local conf="$MAPS_DIR/$map/map.conf"

    if [[ ! -f "$conf" ]]; then
        log_err "Map '$map' not found."
        return 1
    fi

    if ! is_map_running "$map"; then
        log_warn "Map '$map' is not running."
        return 0
    fi

    local save_dir admin_pw rcon_port
    save_dir=$(read_conf_value "$conf" "SaveDir" "$map")
    admin_pw=$(read_conf_value "$conf" "AdminPassword" "")
    rcon_port=$(read_conf_value "$conf" "RCONPort" "27020")

    log_info "Stopping map '$map'..."

    # Try graceful RCON DoExit
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

    # Also kill any orphan wine/proton processes for this map
    pkill -f "wineserver.*${save_dir}" 2>/dev/null || true

    log_ok "Map '$map' stopped."
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
    if (( ${#maps[@]} == 0 )); then
        log_warn "No maps configured."
        return
    fi
    for map in "${maps[@]}"; do
        start_map "$map"
        sleep 5
    done
}

stop_all_maps() {
    local maps
    maps=( $(get_maps) )
    for map in "${maps[@]}"; do
        if is_map_running "$map"; then
            stop_map "$map"
        fi
    done
}

#═══════════════════════════════════════════════════════════════════════════════
#  RCON
#═══════════════════════════════════════════════════════════════════════════════

rcon_console() {
    local map="$1"
    if ! is_map_running "$map"; then
        log_err "Map '$map' is not running."
        return 1
    fi
    local rcon_port admin_pw
    rcon_port=$(read_conf_value "$MAPS_DIR/$map/map.conf" "RCONPort" "27020")
    admin_pw=$(read_conf_value "$MAPS_DIR/$map/map.conf" "AdminPassword" "")
    log_info "Connecting RCON to $map on port $rcon_port..."
    python3 "$RCON_SCRIPT" "localhost:$rcon_port" -p "$admin_pw"
}

send_rcon() {
    local map="$1" cmd="$2"
    if ! is_map_running "$map"; then
        log_err "Map '$map' is not running."
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
        if is_map_running "$map"; then
            send_rcon "$map" "ServerChat $message" 2>/dev/null || true
        fi
    done
    log_ok "Broadcast sent to all running maps."
}

#═══════════════════════════════════════════════════════════════════════════════
#  MOD MANAGEMENT
#═══════════════════════════════════════════════════════════════════════════════

manage_mods() {
    local map="$1"
    local conf="$MAPS_DIR/$map/map.conf"
    local current_mods
    current_mods=$(read_conf_value "$conf" "ModIDs" "")

    echo
    echo -e "  ${BOLD}Mod Management — $map${R}"
    separator
    if [[ -n "$current_mods" ]]; then
        echo -e "  Current mods: ${CYN}$current_mods${R}"
    else
        echo -e "  ${DIM}No mods installed.${R}"
    fi
    echo
    echo -e "  ${CYN}1${R}) Add mod(s)"
    echo -e "  ${CYN}2${R}) Remove mod(s)"
    echo -e "  ${CYN}3${R}) Clear all mods"
    echo -e "  ${CYN}4${R}) Back"
    echo
    echo -ne "  Choice: "
    read -r choice

    case "$choice" in
        1)
            echo -ne "  Enter mod ID(s) to add (comma-separated): "
            read -r new_mods
            if [[ -n "$current_mods" ]]; then
                current_mods="${current_mods},${new_mods}"
            else
                current_mods="$new_mods"
            fi
            write_conf_value "$conf" "ModIDs" "$current_mods"
            log_ok "Mods updated. Restart the map to apply."
            ;;
        2)
            echo -ne "  Enter mod ID(s) to remove (comma-separated): "
            read -r remove_mods
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
            log_ok "Mods updated. Restart the map to apply."
            ;;
        3)
            write_conf_value "$conf" "ModIDs" ""
            log_ok "All mods cleared. Restart the map to apply."
            ;;
        4) return ;;
    esac
}

#═══════════════════════════════════════════════════════════════════════════════
#  SERVER SETTINGS (per-map quick tuning)
#═══════════════════════════════════════════════════════════════════════════════

server_settings_menu() {
    local map="$1"
    local gus="$MAPS_DIR/$map/GameUserSettings.ini"

    while true; do
        echo
        echo -e "  ${BOLD}Server Settings — $map${R}"
        separator

        # Read current values
        local xp taming harvest respawn mating baby hatch pdmg ddmg pres dres dcount stack
        xp=$(read_conf_value "$gus" "XPMultiplier" "1.0")
        taming=$(read_conf_value "$gus" "TamingSpeedMultiplier" "1.0")
        harvest=$(read_conf_value "$gus" "HarvestAmountMultiplier" "1.0")
        respawn=$(read_conf_value "$gus" "ResourcesRespawnPeriodMultiplier" "1.0")
        mating=$(read_conf_value "$gus" "MatingIntervalMultiplier" "1.0")
        baby=$(read_conf_value "$gus" "BabyMatureSpeedMultiplier" "1.0")
        hatch=$(read_conf_value "$gus" "EggHatchSpeedMultiplier" "1.0")
        stack=$(read_conf_value "$gus" "ItemStackSizeMultiplier" "1.0")
        local max_tamed auto_save max_struct
        max_tamed=$(read_conf_value "$gus" "MaxTamedDinos" "5000")
        auto_save=$(read_conf_value "$gus" "AutoSavePeriodMinutes" "15")
        max_struct=$(read_conf_value "$gus" "TheMaxStructuresInRange" "10500")

        printf "  ${CYN} 1${R}) XP Multiplier             : ${WHT}%s${R}\n" "$xp"
        printf "  ${CYN} 2${R}) Taming Speed               : ${WHT}%s${R}\n" "$taming"
        printf "  ${CYN} 3${R}) Harvest Amount              : ${WHT}%s${R}\n" "$harvest"
        printf "  ${CYN} 4${R}) Resource Respawn            : ${WHT}%s${R}\n" "$respawn"
        printf "  ${CYN} 5${R}) Mating Interval             : ${WHT}%s${R}\n" "$mating"
        printf "  ${CYN} 6${R}) Baby Mature Speed           : ${WHT}%s${R}\n" "$baby"
        printf "  ${CYN} 7${R}) Egg Hatch Speed             : ${WHT}%s${R}\n" "$hatch"
        printf "  ${CYN} 8${R}) Item Stack Size             : ${WHT}%s${R}\n" "$stack"
        printf "  ${CYN} 9${R}) Max Tamed Dinos             : ${WHT}%s${R}\n" "$max_tamed"
        printf "  ${CYN}10${R}) Auto-Save Interval (min)    : ${WHT}%s${R}\n" "$auto_save"
        printf "  ${CYN}11${R}) Max Structures In Range     : ${WHT}%s${R}\n" "$max_struct"
        echo
        printf "  ${CYN}12${R}) Graphics Preset              ${DIM}(low/medium/high/auto)${R}\n"
        printf "  ${CYN}13${R}) Edit GameUserSettings.ini   ${DIM}(advanced)${R}\n"
        printf "  ${CYN}14${R}) Edit Game.ini               ${DIM}(advanced)${R}\n"
        printf "  ${CYN}15${R}) Edit map.conf               ${DIM}(ports/passwords/params)${R}\n"
        printf "  ${CYN}16${R}) Back\n"
        echo
        echo -ne "  Choice: "
        read -r choice

        case "$choice" in
            1)  echo -ne "  New XP Multiplier: "; read -r val; write_conf_value "$gus" "XPMultiplier" "$val" ;;
            2)  echo -ne "  New Taming Speed: "; read -r val; write_conf_value "$gus" "TamingSpeedMultiplier" "$val" ;;
            3)  echo -ne "  New Harvest Amount: "; read -r val; write_conf_value "$gus" "HarvestAmountMultiplier" "$val" ;;
            4)  echo -ne "  New Resource Respawn: "; read -r val; write_conf_value "$gus" "ResourcesRespawnPeriodMultiplier" "$val" ;;
            5)  echo -ne "  New Mating Interval: "; read -r val; write_conf_value "$gus" "MatingIntervalMultiplier" "$val" ;;
            6)  echo -ne "  New Baby Mature Speed: "; read -r val; write_conf_value "$gus" "BabyMatureSpeedMultiplier" "$val" ;;
            7)  echo -ne "  New Egg Hatch Speed: "; read -r val; write_conf_value "$gus" "EggHatchSpeedMultiplier" "$val" ;;
            8)  echo -ne "  New Item Stack Size: "; read -r val; write_conf_value "$gus" "ItemStackSizeMultiplier" "$val" ;;
            9)  echo -ne "  New Max Tamed Dinos: "; read -r val; write_conf_value "$gus" "MaxTamedDinos" "$val" ;;
            10) echo -ne "  New Auto-Save (minutes): "; read -r val; write_conf_value "$gus" "AutoSavePeriodMinutes" "$val" ;;
            11) echo -ne "  New Max Structures: "; read -r val; write_conf_value "$gus" "TheMaxStructuresInRange" "$val" ;;
            12) graphics_preset_menu "$map" ;;
            13) ${EDITOR:-nano} "$gus" ;;
            14) ${EDITOR:-nano} "$MAPS_DIR/$map/Game.ini" ;;
            15) ${EDITOR:-nano} "$MAPS_DIR/$map/map.conf" ;;
            16) return ;;
            *)  log_err "Invalid choice." ;;
        esac
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= 11 )) && log_ok "Setting saved. Restart to apply."
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

    if [[ ! -d "$source" ]]; then
        log_err "No save data found for '$map'."
        return 1
    fi

    mkdir -p "$backup_dir"
    log_info "Backing up '$map' saves..."
    tar -czf "$backup_file" -C "$SERVER_DIR/ShooterGame/Saved/SavedArks" "$save_dir"
    local size
    size=$(du -h "$backup_file" | cut -f1)
    log_ok "Backup created: $backup_file ($size)"
}

restore_map() {
    local map="$1"
    local backup_dir="$MAPS_DIR/$map/backups"

    if [[ ! -d "$backup_dir" ]] || [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        log_err "No backups found for '$map'."
        return 1
    fi

    if is_map_running "$map"; then
        log_err "Stop the map before restoring a backup!"
        return 1
    fi

    echo
    echo -e "  ${BOLD}Available Backups — $map${R}"
    separator
    local backups=()
    local i=1
    for f in "$backup_dir"/*.tar.gz; do
        local size
        size=$(du -h "$f" | cut -f1)
        local fname
        fname=$(basename "$f")
        printf "  ${CYN}%2d${R}) %-40s ${DIM}(%s)${R}\n" "$i" "$fname" "$size"
        backups+=("$f")
        ((i++))
    done
    echo
    echo -ne "  Select backup to restore (0 to cancel): "
    read -r choice

    if (( choice == 0 )) || (( choice > ${#backups[@]} )); then
        return 0
    fi

    local selected="${backups[$((choice-1))]}"
    local save_dir
    save_dir=$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")
    local target="$SERVER_DIR/ShooterGame/Saved/SavedArks"

    if confirm "This will overwrite current save data for '$map'. Continue?"; then
        log_info "Restoring backup..."
        rm -rf "$target/$save_dir"
        tar -xzf "$selected" -C "$target"
        log_ok "Backup restored for '$map'."
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  LOG VIEWER
#═══════════════════════════════════════════════════════════════════════════════

view_logs() {
    local map="$1"
    local log_file="$MAPS_DIR/$map/server.log"
    local steam_log="$HOME/steam-${ARK_APPID}.log"

    echo
    echo -e "  ${BOLD}Logs — $map${R}"
    separator
    echo -e "  ${CYN}1${R}) View server log (last 50 lines)"
    echo -e "  ${CYN}2${R}) Follow server log (live)"
    echo -e "  ${CYN}3${R}) View Steam/Proton log"
    echo -e "  ${CYN}4${R}) View errors only"
    echo -e "  ${CYN}5${R}) Back"
    echo
    echo -ne "  Choice: "
    read -r choice

    case "$choice" in
        1)
            if [[ -f "$log_file" ]]; then
                echo
                tail -50 "$log_file"
            else
                log_warn "No log file found."
            fi
            ;;
        2)
            if [[ -f "$log_file" ]]; then
                log_info "Press Ctrl+C to stop following..."
                tail -f "$log_file"
            else
                log_warn "No log file found."
            fi
            ;;
        3)
            if [[ -f "$steam_log" ]]; then
                tail -80 "$steam_log"
            else
                log_warn "No Steam log found at $steam_log"
            fi
            ;;
        4)
            if [[ -f "$log_file" ]]; then
                grep -iE "error|fatal|crash|exception|fail" "$log_file" | tail -30 || log_info "No errors found."
            fi
            ;;
        5) return ;;
    esac
    echo
    press_enter
}

#═══════════════════════════════════════════════════════════════════════════════
#  FILE BROWSER — quick access to important directories
#═══════════════════════════════════════════════════════════════════════════════

browse_files() {
    local map="$1"
    echo
    echo -e "  ${BOLD}File Locations — $map${R}"
    separator
    echo -e "  ${CYN}1${R}) Map config directory     : $MAPS_DIR/$map/"
    echo -e "  ${CYN}2${R}) GameUserSettings.ini     : $MAPS_DIR/$map/GameUserSettings.ini"
    echo -e "  ${CYN}3${R}) Game.ini                 : $MAPS_DIR/$map/Game.ini"
    echo -e "  ${CYN}4${R}) Server log               : $MAPS_DIR/$map/server.log"
    echo -e "  ${CYN}5${R}) Save data                : $SERVER_DIR/ShooterGame/Saved/SavedArks/$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")/"
    echo -e "  ${CYN}6${R}) Backups                  : $MAPS_DIR/$map/backups/"
    echo -e "  ${CYN}7${R}) Server files             : $SERVER_DIR/"
    echo -e "  ${CYN}8${R}) Open folder in shell"
    echo -e "  ${CYN}9${R}) Back"
    echo
    echo -ne "  Choice: "
    read -r choice

    case "$choice" in
        1) ls -la "$MAPS_DIR/$map/" ; press_enter ;;
        2) ${EDITOR:-nano} "$MAPS_DIR/$map/GameUserSettings.ini" ;;
        3) ${EDITOR:-nano} "$MAPS_DIR/$map/Game.ini" ;;
        4) less "$MAPS_DIR/$map/server.log" 2>/dev/null || log_warn "No log file." ;;
        5) ls -la "$SERVER_DIR/ShooterGame/Saved/SavedArks/$(read_conf_value "$MAPS_DIR/$map/map.conf" "SaveDir" "$map")/" 2>/dev/null ; press_enter ;;
        6) ls -la "$MAPS_DIR/$map/backups/" 2>/dev/null ; press_enter ;;
        7) ls -la "$SERVER_DIR/" ; press_enter ;;
        8) log_info "Dropping into shell at: $MAPS_DIR/$map/" ; cd "$MAPS_DIR/$map" && exec bash ;;
        9) return ;;
    esac
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

    echo
    log_warn "This will permanently delete map '$map' and all its configuration."
    log_warn "Save data in server-files will NOT be deleted (only config/backups)."
    echo
    if confirm "Are you absolutely sure?"; then
        # Remove systemd service
        local service_name="ark-${map,,}.service"
        sudo systemctl stop "$service_name" 2>/dev/null || true
        sudo systemctl disable "$service_name" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/$service_name"
        sudo systemctl daemon-reload

        # Remove from maps.conf
        sed -i "/^${map}|/d" "$MAPS_CONF"

        # Remove map directory
        rm -rf "$MAPS_DIR/$map"

        log_ok "Map '$map' deleted."
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  CHANGE MAP (change the internal map for an existing entry)
#═══════════════════════════════════════════════════════════════════════════════

change_map_type() {
    local map="$1"

    if is_map_running "$map"; then
        log_err "Stop the map before changing the map type!"
        return 1
    fi

    echo
    log_info "Available maps:"
    local i=1
    local map_keys=()
    for key in $(echo "${!MAP_NAMES[@]}" | tr ' ' '\n' | sort); do
        printf "  ${CYN}%2d${R}) %-20s  ${DIM}(%s)${R}\n" "$i" "$key" "${MAP_NAMES[$key]}"
        map_keys+=("$key")
        ((i++))
    done
    echo
    echo -ne "  Select new map: "
    read -r choice

    if (( choice > 0 && choice <= ${#map_keys[@]} )); then
        local new_internal="${MAP_NAMES[${map_keys[$((choice-1))]}]}"
        write_conf_value "$MAPS_DIR/$map/map.conf" "MapName" "$new_internal"
        log_ok "Map changed to ${map_keys[$((choice-1))]} ($new_internal). Restart to apply."
    else
        log_err "Invalid selection."
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  OPTIMIZATION
#═══════════════════════════════════════════════════════════════════════════════

apply_optimizations() {
    log_info "Applying system optimizations..."

    # ─── Kernel tuning ───
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

    # ─── Logrotate ───
    setup_logrotate

    # ─── Healthcheck cron ───
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
    else
        log_warn "logrotate not found. Install it for automatic log rotation."
    fi
}

setup_healthcheck() {
    # Create healthcheck script
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

    save_dir=$(grep "^SaveDir=" "$conf" | cut -d= -f2-)

    # Check if the map has a systemd service enabled (meaning it should be running)
    service_name="ark-${map,,}.service"
    if ! systemctl is-enabled "$service_name" &>/dev/null; then
        continue  # Not managed by systemd, skip
    fi

    # Check if active
    if ! systemctl is-active "$service_name" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [HEAL] $map is down, restarting via systemd..." >> "$LOG"
        systemctl restart "$service_name" 2>/dev/null || true
    fi
done
HCEOF
    chmod +x "$hc_script"

    # Install cron job
    local cron_line="*/5 * * * * $hc_script"
    if ! crontab -l 2>/dev/null | grep -qF "$hc_script"; then
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
        log_ok "Healthcheck cron installed (every 5 minutes)."
    else
        log_ok "Healthcheck cron already present."
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
#  SCHEDULED RESTART (with player warnings)
#═══════════════════════════════════════════════════════════════════════════════

setup_scheduled_restart() {
    echo
    echo -e "  ${BOLD}Scheduled Restart Setup${R}"
    separator
    echo -ne "  Restart time (HH:MM, 24h format) [04:00]: "
    read -r restart_time
    restart_time="${restart_time:-04:00}"

    local hour minute
    hour=$(echo "$restart_time" | cut -d: -f1)
    minute=$(echo "$restart_time" | cut -d: -f2)

    # Create restart script
    local rs_script="$SCRIPT_DIR/scheduled-restart.sh"
    cat > "$rs_script" <<RSEOF
#!/usr/bin/env bash
# ARK Scheduled Restart with Player Warnings
SCRIPT_DIR="$(cd "$(dirname "$(realpath "\$0")")" && pwd)"
MANAGER="\$SCRIPT_DIR/ark-manager.sh"
LOG="\$SCRIPT_DIR/restart.log"

announce() {
    local msg="\$1"
    \$MANAGER broadcast "\$msg" 2>/dev/null
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [RESTART] \$msg" >> "\$LOG"
}

# Warning sequence
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

    # Calculate cron time (30 min before desired restart)
    local cron_min=$(( (minute - 30 + 60) % 60 ))
    local cron_hour=$hour
    if (( minute < 30 )); then
        cron_hour=$(( (hour - 1 + 24) % 24 ))
    fi

    local cron_line="$cron_min $cron_hour * * * $rs_script"

    # Remove old restart cron and add new
    crontab -l 2>/dev/null | grep -vF "scheduled-restart.sh" | { cat; echo "$cron_line"; } | crontab -

    log_ok "Scheduled restart set for $restart_time daily (warnings start 30 min before)."
}

#═══════════════════════════════════════════════════════════════════════════════
#  MIGRATE FROM OLD MANAGER (one-time helper)
#═══════════════════════════════════════════════════════════════════════════════

migrate_from_old() {
    local old_instances="$SCRIPT_DIR/instances"
    if [[ ! -d "$old_instances" ]]; then
        # Try parent structure
        old_instances="$(dirname "$SCRIPT_DIR")/Linux-ASA-Server-Manager/instances"
    fi
    if [[ ! -d "$old_instances" ]]; then
        log_warn "No old instances directory found. Nothing to migrate."
        return
    fi

    log_info "Migrating old instances to new map format..."
    for inst_dir in "$old_instances"/*/; do
        [[ -d "$inst_dir" ]] || continue
        local inst_name
        inst_name=$(basename "$inst_dir")
        local old_conf="$inst_dir/instance_config.ini"
        [[ -f "$old_conf" ]] || continue

        # Read old config
        local map_name server_name admin_pw server_pw max_players game_port query_port rcon_port mod_ids custom_params save_dir cluster_id
        map_name=$(read_conf_value "$old_conf" "MapName" "TheIsland_WP")
        server_name=$(read_conf_value "$old_conf" "ServerName" "$inst_name")
        admin_pw=$(read_conf_value "$old_conf" "ServerAdminPassword" "")
        server_pw=$(read_conf_value "$old_conf" "ServerPassword" "")
        max_players=$(read_conf_value "$old_conf" "MaxPlayers" "70")
        game_port=$(read_conf_value "$old_conf" "Port" "7777")
        query_port=$(read_conf_value "$old_conf" "QueryPort" "27015")
        rcon_port=$(read_conf_value "$old_conf" "RCONPort" "27020")
        mod_ids=$(read_conf_value "$old_conf" "ModIDs" "")
        custom_params=$(read_conf_value "$old_conf" "CustomStartParameters" "")
        save_dir=$(read_conf_value "$old_conf" "SaveDir" "$inst_name")
        cluster_id=$(read_conf_value "$old_conf" "ClusterID" "")

        # Determine display name from mapname
        local display_name="$inst_name"

        mkdir -p "$MAPS_DIR/$display_name/backups"

        cat > "$MAPS_DIR/$display_name/map.conf" <<EOF
# Migrated from old instance: $inst_name
MapName=$map_name
DisplayName=$display_name
SaveDir=$save_dir
GamePort=$game_port
QueryPort=$query_port
RCONPort=$rcon_port
MaxPlayers=$max_players
AdminPassword=$admin_pw
ServerPassword=$server_pw
ModIDs=$mod_ids
CustomStartParams=$custom_params
ClusterID=$cluster_id
EOF

        # Copy config files
        if [[ -f "$inst_dir/Config/GameUserSettings.ini" ]]; then
            cp "$inst_dir/Config/GameUserSettings.ini" "$MAPS_DIR/$display_name/"
        else
            create_optimized_game_settings "$MAPS_DIR/$display_name"
        fi
        if [[ -f "$inst_dir/Config/Game.ini" ]]; then
            cp "$inst_dir/Config/Game.ini" "$MAPS_DIR/$display_name/"
        else
            touch "$MAPS_DIR/$display_name/Game.ini"
        fi

        echo "${display_name}|${map_name}|enabled" >> "$MAPS_CONF"
        create_systemd_service "$display_name"

        log_ok "Migrated: $inst_name → $display_name"
    done
    log_ok "Migration complete!"
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
    echo
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
    echo
    echo -ne "  Select map: "
    read -r choice
    if (( choice > 0 && choice <= ${#maps[@]} )); then
        SELECTED_MAP="${maps[$((choice-1))]}"
        return 0
    fi
    return 1
}

map_menu() {
    local map="$1"
    while true; do
        echo
        echo -e "  ${BOLD}${BLU}═══ $map ═══${R}"
        local internal
        internal=$(read_conf_value "$MAPS_DIR/$map/map.conf" "MapName" "?")
        echo -e "  ${DIM}Internal: $internal${R}"
        echo

        local status_text
        if is_map_running "$map"; then
            status_text="${GRN}● ONLINE${R}"
        else
            status_text="${RED}● OFFLINE${R}"
        fi
        echo -e "  Status: $status_text    Health: $(check_map_health "$map")"
        echo

        echo -e "  ${CYN} 1${R}) Start"
        echo -e "  ${CYN} 2${R}) Stop"
        echo -e "  ${CYN} 3${R}) Restart"
        echo -e "  ${CYN} 4${R}) RCON Console"
        echo -e "  ${CYN} 5${R}) Server Settings"
        echo -e "  ${CYN} 6${R}) Mod Management"
        echo -e "  ${CYN} 7${R}) Change Map Type"
        echo -e "  ${CYN} 8${R}) Backup World"
        echo -e "  ${CYN} 9${R}) Restore Backup"
        echo -e "  ${CYN}10${R}) View Logs"
        echo -e "  ${CYN}11${R}) Browse Files"
        echo -e "  ${CYN}12${R}) Delete Map"
        echo -e "  ${CYN}13${R}) Back to Dashboard"
        echo
        echo -ne "  Choice: "
        read -r choice

        case "$choice" in
            1)  start_map "$map" ; press_enter ;;
            2)  stop_map "$map" ; press_enter ;;
            3)  restart_map "$map" ; press_enter ;;
            4)  rcon_console "$map" ;;
            5)  server_settings_menu "$map" ;;
            6)  manage_mods "$map" ; press_enter ;;
            7)  change_map_type "$map" ; press_enter ;;
            8)  backup_map "$map" ; press_enter ;;
            9)  restore_map "$map" ; press_enter ;;
            10) view_logs "$map" ;;
            11) browse_files "$map" ;;
            12) delete_map "$map" && return ; press_enter ;;
            13) return ;;
            *)  log_err "Invalid choice." ;;
        esac
    done
}

main_menu() {
    while true; do
        show_dashboard

        echo -e "  ${BOLD}Actions:${R}"
        echo
        echo -e "  ${CYN} 1${R}) Select Map           ${CYN} 7${R}) Broadcast Message"
        echo -e "  ${CYN} 2${R}) Add Map              ${CYN} 8${R}) Scheduled Restarts"
        echo -e "  ${CYN} 3${R}) Start All Maps       ${CYN} 9${R}) Apply Optimizations"
        echo -e "  ${CYN} 4${R}) Stop All Maps        ${CYN}10${R}) Migrate Old Instances"
        echo -e "  ${CYN} 5${R}) Install / Update     ${CYN}11${R}) Global Defaults"
        echo -e "  ${CYN} 6${R}) Send RCON Command    ${CYN}12${R}) Exit"
        echo
        echo -ne "  ${WHT}Choice: ${R}"
        read -r choice

        case "$choice" in
            1)
                if select_map; then
                    map_menu "$SELECTED_MAP"
                fi
                ;;
            2)  add_map ;;
            3)  start_all_maps ; press_enter ;;
            4)  stop_all_maps ; press_enter ;;
            5)  install_server ; press_enter ;;
            6)
                if select_map; then
                    echo -ne "  RCON command: "
                    read -r cmd
                    send_rcon "$SELECTED_MAP" "$cmd"
                    press_enter
                fi
                ;;
            7)
                echo -ne "  Message: "
                read -r msg
                broadcast_message "$msg"
                press_enter
                ;;
            8)  setup_scheduled_restart ; press_enter ;;
            9)  apply_optimizations ; press_enter ;;
            10) migrate_from_old ; press_enter ;;
            11) ${EDITOR:-nano} "$DEFAULTS_CONF" ;;
            12)
                echo -e "  ${GRN}Goodbye!${R}"
                exit 0
                ;;
            *)  log_err "Invalid choice." ;;
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
    printf "%-16s %-10s %-10s %-8s %-8s %-8s\n" "MAP" "STATUS" "HEALTH" "PLAYERS" "UPTIME" "RAM"
    for map in "${maps[@]}"; do
        local status health players uptime mem
        if is_map_running "$map"; then status="ONLINE"; else status="OFFLINE"; fi
        health=$(check_map_health "$map")
        if is_map_running "$map"; then
            players=$(get_player_count "$map" 2>/dev/null || echo "?")
        else
            players="-"
        fi
        uptime=$(get_map_uptime "$map")
        mem=$(get_map_memory "$map")
        printf "%-16s %-10s %-10s %-8s %-8s %-8s\n" "$map" "$status" "$health" "$players" "$uptime" "$mem"
    done
}

show_help() {
    echo "ARK: Survival Ascended — Server Manager"
    echo
    echo "Usage: $(basename "$0") [command] [arguments]"
    echo
    echo "Commands:"
    echo "  (none)              Interactive dashboard"
    echo "  install             Install/update server files"
    echo "  start <map>         Start a map"
    echo "  stop <map>          Stop a map"
    echo "  restart <map>       Restart a map"
    echo "  start-all           Start all maps"
    echo "  stop-all            Stop all maps"
    echo "  status              Show all map statuses"
    echo "  update              Alias for install"
    echo "  rcon <map> \"cmd\"    Send RCON command"
    echo "  backup <map>        Backup map world"
    echo "  broadcast \"msg\"     Send message to all maps"
    echo "  help                Show this help"
}

#═══════════════════════════════════════════════════════════════════════════════
#  MAIN ENTRY POINT
#═══════════════════════════════════════════════════════════════════════════════

# Ensure dirs exist
mkdir -p "$CONFIG_DIR" "$MAPS_DIR"

# Create default configs if missing
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
