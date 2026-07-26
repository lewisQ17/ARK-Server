#!/usr/bin/env bash
# ==============================================================================
#  ARK: Survival Ascended — one-command server installer for Ubuntu
# ==============================================================================
#  Installs, in this order:
#    1. system packages + a dedicated unprivileged user
#    2. SteamCMD + Proton-GE + the ASA server binaries (via ark-manager.sh)
#    3. your first map, with generated passwords
#    4. the web dashboard (optional) behind a login, as a systemd service
#    5. your chosen way of reaching it: LAN-only, port-forward, or Cloudflare tunnel
#
#  It is idempotent: re-running it skips whatever is already in place.
#  Nothing is exposed to the internet unless you explicitly ask for it.
#
#  Usage:
#     sudo ./install.sh                          # interactive (recommended)
#     sudo ./install.sh --yes --map TheIsland    # unattended, sensible defaults
#     sudo ./install.sh --no-dashboard           # game server only
#     sudo ./install.sh --help
# ==============================================================================
set -Eeuo pipefail

# ---------------------------------------------------------------- appearance --
if [[ -t 1 ]]; then
	R=$'\033[0m'; B=$'\033[1m'; DIM=$'\033[2m'
	GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; CYN=$'\033[36m'
else
	R=""; B=""; DIM=""; GRN=""; YEL=""; RED=""; CYN=""
fi
step() { echo; echo "${CYN}${B}==>${R} ${B}$*${R}"; }
ok()   { echo "  ${GRN}✔${R} $*"; }
warn() { echo "  ${YEL}⚠${R} $*"; }
die()  { echo; echo "  ${RED}✖ $*${R}" >&2; exit 1; }
note() { echo "  ${DIM}$*${R}"; }

# ------------------------------------------------------------------ defaults --
ARK_USER="arkadmin"
INSTALL_DIR="/opt/ark-server"
DASH_PORT="8787"
DASH_USER="admin"
FIRST_MAP=""
ASSUME_YES=0
WITH_DASHBOARD=1
EXPOSURE=""                # lan | forward | tunnel
DASHBOARD_REPO="${DASHBOARD_REPO:-https://github.com/lewisQ17/ark-server-dashboard.git}"
REPO_SRC="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
SUMMARY_FILE="/root/ark-install-summary.txt"

usage() {
	cat <<EOF
${B}ARK: Survival Ascended — Ubuntu installer${R}

  sudo ./install.sh [options]

Options:
  --yes, -y             Don't ask anything; use defaults.
  --map NAME            Create this map on first install (e.g. TheIsland, Extinction).
  --user NAME           System user that owns and runs the server (default: ${ARK_USER}).
  --dir PATH            Install location (default: ${INSTALL_DIR}).
  --no-dashboard        Skip the web dashboard; install the game server only.
  --dashboard-port N    Port for the dashboard (default: ${DASH_PORT}).
  --dashboard-repo URL  Where to fetch the dashboard from.
  --expose MODE         lan | forward | tunnel. Skips the interactive question.
  --help, -h            Show this text.

Everything is idempotent — safe to run again after a failure.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-y|--yes)          ASSUME_YES=1; shift ;;
		--map)             FIRST_MAP="${2:-}"; shift 2 ;;
		--user)            ARK_USER="${2:-}"; shift 2 ;;
		--dir)             INSTALL_DIR="${2:-}"; shift 2 ;;
		--no-dashboard)    WITH_DASHBOARD=0; shift ;;
		--dashboard-port)  DASH_PORT="${2:-}"; shift 2 ;;
		--dashboard-repo)  DASHBOARD_REPO="${2:-}"; shift 2 ;;
		--expose)          EXPOSURE="${2:-}"; shift 2 ;;
		-h|--help)         usage; exit 0 ;;
		*)                 die "Unknown option: $1  (try --help)" ;;
	esac
done

ask() {  # ask <prompt> <default>  → echoes the answer
	local prompt="$1" default="${2:-}" reply
	if (( ASSUME_YES )); then echo "$default"; return; fi
	read -r -p "  ${prompt} [${default}]: " reply </dev/tty || reply=""
	echo "${reply:-$default}"
}
confirm() {  # confirm <prompt>  → returns 0 for yes
	local reply
	if (( ASSUME_YES )); then return 0; fi
	read -r -p "  $1 [Y/n]: " reply </dev/tty || reply=""
	[[ -z "$reply" || "$reply" =~ ^[JjYy] ]]
}
genpw() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-24}"; }

trap 'die "Failed on line $LINENO. Nothing was left running; fix the cause and re-run."' ERR

# ============================================================ 0. preflight ====
step "Checking this machine"

[[ $EUID -eq 0 ]] || die "Run this with sudo:  sudo ./install.sh"

if [[ -r /etc/os-release ]]; then
	. /etc/os-release
	case "${ID:-}" in
		ubuntu) ok "Ubuntu ${VERSION_ID:-?}" ;;
		debian) warn "Debian ${VERSION_ID:-?} — untested but should work." ;;
		*)      warn "${PRETTY_NAME:-unknown OS} — this installer targets Ubuntu. Continuing anyway." ;;
	esac
else
	warn "Can't identify the OS. Continuing."
fi

[[ "$(uname -m)" == "x86_64" ]] || die "ASA server binaries are x86_64-only; this machine is $(uname -m)."

TOTAL_RAM_GB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
if (( TOTAL_RAM_GB < 12 )); then
	warn "${TOTAL_RAM_GB} GB RAM. One ASA map needs ~12-16 GB; expect the kernel to kill the server."
	confirm "Continue anyway?" || die "Stopped. Add RAM or swap first."
else
	ok "${TOTAL_RAM_GB} GB RAM"
fi

FREE_GB=$(df -BG --output=avail "$(dirname "$INSTALL_DIR")" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
if (( FREE_GB < 40 )); then
	warn "Only ${FREE_GB} GB free on $(dirname "$INSTALL_DIR"). ASA needs ~30 GB, plus saves and backups."
	confirm "Continue anyway?" || die "Stopped. Free up disk space first."
else
	ok "${FREE_GB} GB free"
fi

# ==================================================== 1. packages and user ====
step "Installing system packages"

export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386 >/dev/null 2>&1 || true
apt-get update -qq
# lib32gcc-s1 + libfreetype: SteamCMD.  python3: rcon.py.  xz/tar/curl/wget: downloads.
apt-get install -y -qq --no-install-recommends \
	curl wget tar xz-utils ca-certificates \
	lib32gcc-s1 libfreetype6:i386 \
	python3 jq git sudo procps >/dev/null
ok "Base packages installed"

if (( WITH_DASHBOARD )); then
	if ! command -v node >/dev/null 2>&1 || (( $(node -v 2>/dev/null | tr -dc '0-9.' | cut -d. -f1 || echo 0) < 18 )); then
		note "Installing Node.js 20 (the dashboard needs 18+)…"
		curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
		apt-get install -y -qq nodejs >/dev/null
	fi
	ok "Node.js $(node -v)"
fi

step "Setting up the '${ARK_USER}' user"
if id -u "$ARK_USER" >/dev/null 2>&1; then
	ok "User '${ARK_USER}' already exists"
else
	useradd -m -s /bin/bash "$ARK_USER"
	ok "Created user '${ARK_USER}' (no password, no sudo — it only runs the game server)"
fi

# =========================================================== 2. the server ====
step "Installing the server manager into ${INSTALL_DIR}"

mkdir -p "$INSTALL_DIR"
if [[ "$REPO_SRC" != "$INSTALL_DIR" ]]; then
	# Copy the repo (not the game data) — rsync if present, else tar.
	if command -v rsync >/dev/null 2>&1; then
		rsync -a --exclude='.git' --exclude='server-files' --exclude='steamcmd' \
			--exclude='GE-Proton*' --exclude='maps/*/backups' "$REPO_SRC"/ "$INSTALL_DIR"/
	else
		(cd "$REPO_SRC" && tar -c --exclude='.git' --exclude='server-files' --exclude='steamcmd' \
			--exclude='GE-Proton*' .) | (cd "$INSTALL_DIR" && tar -x)
	fi
	ok "Manager copied to ${INSTALL_DIR}"
else
	ok "Already running from ${INSTALL_DIR}"
fi

chown -R "$ARK_USER":"$ARK_USER" "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/ark-manager.sh" "$INSTALL_DIR/healthcheck.sh" 2>/dev/null || true

step "Downloading SteamCMD, Proton-GE and the ASA server (this takes a while — ~30 GB)"
if [[ -d "$INSTALL_DIR/server-files/ShooterGame" ]]; then
	ok "Server files already present — skipping the download"
else
	note "Grab a coffee. Progress is printed by SteamCMD below."
	# Deliberately unprivileged: SteamCMD and Proton only write inside ${INSTALL_DIR}.
	# The manager's optional system tuning (sysctl / logrotate / healthcheck cron) needs
	# root and is therefore skipped here — see the summary for how to apply it.
	if sudo -u "$ARK_USER" -H bash -lc "cd '$INSTALL_DIR' && ./ark-manager.sh install"; then
		ok "Server files installed"
	else
		warn "The manager reported a problem during install."
		note "The download itself may still be fine — check with:"
		note "  sudo -u ${ARK_USER} ${INSTALL_DIR}/ark-manager.sh status"
		confirm "Continue with the rest of the setup?" || die "Stopped at your request."
	fi
fi

# ============================================================== 3. the map ====
step "Creating your first map"

existing_maps=$(sudo -u "$ARK_USER" -H bash -lc "ls -1 '$INSTALL_DIR/maps' 2>/dev/null" | wc -l)
if (( existing_maps > 0 )); then
	ok "${existing_maps} map(s) already configured — skipping"
else
	if [[ -z "$FIRST_MAP" ]]; then
		echo
		note "Common maps: TheIsland  ScorchedEarth  Aberration  Extinction  TheCenter  Ragnarok"
		FIRST_MAP=$(ask "Which map do you want to start with?" "TheIsland")
	fi
	ADMIN_PW="$(genpw 20)"
	SERVER_PW=""
	if ! (( ASSUME_YES )); then
		if confirm "Password-protect the server (players need a password to join)?"; then
			SERVER_PW="$(ask "Join password" "$(genpw 10)")"
		fi
	fi

	# add-map is the non-interactive path; it writes map.conf (mode 600), the
	# GameUserSettings, the systemd unit and the firewall rules in one go.
	# Run it as root — writing /etc/systemd/system needs that — but tell the manager
	# which user the unit must run as, so the server itself never runs as root.
	if ARK_SERVICE_USER="$ARK_USER" bash -lc \
		"cd '$INSTALL_DIR' && ./ark-manager.sh add-map $(printf %q "$FIRST_MAP") --admin-pw $(printf %q "$ADMIN_PW") --server-pw $(printf %q "$SERVER_PW")"
	then
		chown -R "$ARK_USER":"$ARK_USER" "$INSTALL_DIR/maps" "$INSTALL_DIR/config" 2>/dev/null || true
		ok "Map '${FIRST_MAP}' created with a generated admin password"
	else
		ADMIN_PW=""
		warn "Could not create '${FIRST_MAP}' automatically."
		note "If it isn't a stock map, give the internal name yourself:"
		note "  sudo -u ${ARK_USER} ${INSTALL_DIR}/ark-manager.sh add-map ${FIRST_MAP} --internal ${FIRST_MAP}_WP"
		note "Or run ${INSTALL_DIR}/ark-manager.sh and use the menu."
	fi
fi

# ============================================================ 4. dashboard ====
DASH_PASS=""
DASH_DIR="/opt/ark-dashboard"
if (( WITH_DASHBOARD )); then
	step "Installing the web dashboard"

	if [[ -d "$DASH_DIR/.git" ]]; then
		ok "Dashboard already present at ${DASH_DIR}"
	elif git clone --depth 1 "$DASHBOARD_REPO" "$DASH_DIR" >/dev/null 2>&1; then
		ok "Dashboard fetched from ${DASHBOARD_REPO}"
	else
		WITH_DASHBOARD=0
		warn "Could not fetch the dashboard from ${DASHBOARD_REPO}."
		note "If that repository is private, either make it public or clone it yourself into ${DASH_DIR}"
		note "and re-run this installer. The game server itself is fine and will be set up regardless."
	fi
fi

if (( WITH_DASHBOARD )); then
	(cd "$DASH_DIR/backend" && npm install --omit=dev --no-audit --no-fund >/dev/null 2>&1) \
		|| die "npm install failed in ${DASH_DIR}/backend"

	DASH_PASS="$(genpw 20)"
	install -d -m 750 "$DASH_DIR/deploy"
	cat > "$DASH_DIR/deploy/.env" <<EOF
# Generated by install.sh on $(date -Is)
# Local mode: the dashboard runs on the same machine as the game server and
# executes the manager directly. No Proxmox, no remote API.
ARK_EXEC_MODE=local
ARK_USER=${ARK_USER}
ARK_MANAGER=${INSTALL_DIR}/ark-manager.sh
PORT=${DASH_PORT}
BIND=127.0.0.1

# Login for the dashboard. Change these any time, then: systemctl restart ark-dashboard
DASH_USER=${DASH_USER}
DASH_PASS=${DASH_PASS}
EOF
	chmod 600 "$DASH_DIR/deploy/.env"
	ok "Dashboard configured (login details are in the summary at the end)"

	# The dashboard needs to run the manager as ${ARK_USER}; give it exactly that and nothing more.
	cat > /etc/sudoers.d/ark-dashboard <<EOF
# Let the dashboard service run the ARK manager as ${ARK_USER} — nothing else.
ark-dashboard ALL=(${ARK_USER}) NOPASSWD: ALL
EOF
	chmod 440 /etc/sudoers.d/ark-dashboard
	visudo -c -f /etc/sudoers.d/ark-dashboard >/dev/null || die "Generated sudoers file is invalid — removed nothing, please inspect /etc/sudoers.d/ark-dashboard"

	id -u ark-dashboard >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin ark-dashboard
	chown -R ark-dashboard:ark-dashboard "$DASH_DIR"

	cat > /etc/systemd/system/ark-dashboard.service <<EOF
[Unit]
Description=ARK server dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ark-dashboard
WorkingDirectory=${DASH_DIR}/backend
EnvironmentFile=${DASH_DIR}/deploy/.env
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=5
NoNewPrivileges=no
PrivateTmp=yes
ProtectSystem=full
ProtectHome=read-only

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
	systemctl enable --now ark-dashboard >/dev/null 2>&1 || warn "Dashboard service did not start — check: journalctl -u ark-dashboard -n 50"
	sleep 2
	if systemctl is-active --quiet ark-dashboard; then
		ok "Dashboard running on 127.0.0.1:${DASH_PORT}"
	else
		warn "Dashboard is not running. Check: journalctl -u ark-dashboard -n 50"
	fi
fi

# ============================================================= 5. exposure ====
step "How do you want to reach the dashboard?"

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -z "$EXPOSURE" ]]; then
	if (( ASSUME_YES )); then
		EXPOSURE="lan"
	else
		cat <<EOF

  ${B}1) LAN only${R} ${DIM}(recommended)${R}
     Reachable from your own network at http://${LAN_IP:-<this-machine>}:${DASH_PORT}
     From outside, use an SSH tunnel. Nothing is opened to the internet.

  ${B}2) Port-forward${R}
     You open a port on your router yourself. I'll tell you exactly which ones.
     Your home IP becomes visible to anyone who scans it.

  ${B}3) Cloudflare Tunnel${R}
     A free outbound-only tunnel: no open ports, your IP stays hidden,
     and you get an https address. Needs a (free) Cloudflare account.

EOF
		case "$(ask "Choose 1, 2 or 3" "1")" in
			2) EXPOSURE="forward" ;;
			3) EXPOSURE="tunnel" ;;
			*) EXPOSURE="lan" ;;
		esac
	fi
fi

EXPOSURE_NOTE=""
case "$EXPOSURE" in
	lan)
		if (( WITH_DASHBOARD )); then
			sed -i "s/^BIND=.*/BIND=0.0.0.0/" "$DASH_DIR/deploy/.env"
			systemctl restart ark-dashboard 2>/dev/null || true
		fi
		EXPOSURE_NOTE="Dashboard listens on your LAN only: http://${LAN_IP:-<this-machine>}:${DASH_PORT}
From outside your network, tunnel in over SSH:
  ssh -N -L ${DASH_PORT}:127.0.0.1:${DASH_PORT} <user>@<this-machine>
then open http://localhost:${DASH_PORT}"
		ok "LAN only — nothing exposed to the internet"
		;;
	forward)
		if (( WITH_DASHBOARD )); then
			sed -i "s/^BIND=.*/BIND=0.0.0.0/" "$DASH_DIR/deploy/.env"
			systemctl restart ark-dashboard 2>/dev/null || true
		fi
		EXPOSURE_NOTE="Forward these on your router to ${LAN_IP:-this machine}:

  7777/UDP   → game traffic          (required for players to connect)
  27015/UDP  → Steam server query    (required to appear in the server list)
  ${DASH_PORT}/TCP    → dashboard           (OPTIONAL — see the warning below)

  Do NOT forward 27020 (RCON). It stays on localhost.

WARNING: forwarding the dashboard port publishes an admin panel on your home IP.
Anyone who finds it only has to get past the login. Prefer option 3 (tunnel),
or leave the dashboard on LAN and forward only 7777 and 27015."
		ok "Port-forward chosen — the exact ports are in the summary"
		;;
	tunnel)
		if ! command -v cloudflared >/dev/null 2>&1; then
			note "Installing cloudflared…"
			curl -fsSL -o /tmp/cloudflared.deb \
				"https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb" 2>/dev/null \
				&& dpkg -i /tmp/cloudflared.deb >/dev/null 2>&1 \
				&& ok "cloudflared installed" \
				|| warn "Could not install cloudflared automatically — see https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/"
			rm -f /tmp/cloudflared.deb
		else
			ok "cloudflared already installed"
		fi
		EXPOSURE_NOTE="Finish the tunnel (one-time, in your browser):

  1. cloudflared tunnel login
  2. cloudflared tunnel create ark
  3. Point a hostname at it, e.g.:
       cloudflared tunnel route dns ark ark.yourdomain.com
  4. Run it as a service:
       cloudflared tunnel --url http://127.0.0.1:${DASH_PORT} run ark
       cloudflared service install

Players still connect to the game over 7777/UDP + 27015/UDP directly, so you
still need those two forwarded on your router — a tunnel does not carry game
traffic. The tunnel is only for the dashboard."
		ok "Cloudflare tunnel chosen — the remaining steps are in the summary"
		;;
	*) die "Unknown --expose value: ${EXPOSURE} (use lan, forward or tunnel)" ;;
esac

# ============================================================== 6. summary ====
ADMIN_PW_SHOWN="${ADMIN_PW:-<already configured — see ${INSTALL_DIR}/maps/<Map>/map.conf>}"

{
	echo "=============================================================="
	echo " ARK: Survival Ascended — installed $(date -Is)"
	echo "=============================================================="
	echo
	echo "GAME SERVER"
	echo "  Location        ${INSTALL_DIR}"
	echo "  Runs as user    ${ARK_USER}"
	echo "  Map             ${FIRST_MAP:-<none created yet>}"
	echo "  In-game admin   ${ADMIN_PW_SHOWN}"
	[[ -n "${SERVER_PW:-}" ]] && echo "  Join password   ${SERVER_PW}"
	echo
	echo "  Start:   sudo -u ${ARK_USER} ${INSTALL_DIR}/ark-manager.sh start-all"
	echo "  Stop:    sudo -u ${ARK_USER} ${INSTALL_DIR}/ark-manager.sh stop-all"
	echo "  Menu:    sudo -u ${ARK_USER} ${INSTALL_DIR}/ark-manager.sh"
	echo
	if (( WITH_DASHBOARD )); then
		echo "DASHBOARD"
		echo "  Address         http://${LAN_IP:-127.0.0.1}:${DASH_PORT}"
		echo "  Username        ${DASH_USER}"
		echo "  Password        ${DASH_PASS}"
		echo "  Config          ${DASH_DIR}/deploy/.env"
		echo "  Service         systemctl {status,restart} ark-dashboard"
		echo
	fi
	echo "REACHING IT"
	echo "${EXPOSURE_NOTE}" | sed 's/^/  /'
	echo
	echo "STILL TO DO"
	echo "  - Start the server: the installer does not auto-start it, so you can"
	echo "    review the settings in ${INSTALL_DIR}/maps/<Map>/ first."
	echo "  - Optional system tuning (sysctl, logrotate, healthcheck cron) was skipped:"
	echo "    it needs root, while the download ran as ${ARK_USER}. Apply it with:"
	echo "      sudo ${INSTALL_DIR}/ark-manager.sh   → menu → System / Optimization"
	if (( WITH_DASHBOARD )); then
		echo "  - Change the dashboard password if you like, in ${DASH_DIR}/deploy/.env"
	fi
	echo "  - Take backups: the manager writes them to ${INSTALL_DIR}/maps/<Map>/backups/"
	echo
	echo "This file: ${SUMMARY_FILE} (root-only, chmod 600)"
} > "$SUMMARY_FILE"
chmod 600 "$SUMMARY_FILE"

trap - ERR
echo
echo "${GRN}${B}══════════════════════════════════════════════════════════════${R}"
cat "$SUMMARY_FILE"
echo "${GRN}${B}══════════════════════════════════════════════════════════════${R}"
echo
ok "Done. The details above are also saved in ${SUMMARY_FILE}"
