#!/usr/bin/env bash
# Deploy the ARK dashboard to a Docker host over SSH.
#   ./deploy/deploy.sh <ssh-target> [remote-dir] [host-port]
# e.g. ./deploy/deploy.sh docker-host   (or root@10.0.0.20, or an ssh alias)
#
# Site-specific settings (which Proxmox, which VM, which UniFi) live in
# deploy/site.env, which is gitignored — this script ships no addresses. Copy
# deploy/site.env.example to deploy/site.env once and fill it in.
#
# Secrets come from the macOS Keychain and are written into a remote
# deploy/.env (chmod 600). The RCON admin password is NOT stored here — the app
# reads it from the ARK VM at runtime.
set -euo pipefail

TARGET="${1:?usage: deploy.sh <ssh-target> [remote-dir] [host-port]}"
REMOTE_DIR="${2:-/opt/ark-dashboard}"
HOST_PORT="${3:-8790}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"

# Where this particular deployment points. Kept out of git so the repo carries
# no network layout; without it we stop rather than guess at an address.
SITE_ENV="$(dirname "$0")/site.env"
if [ ! -f "$SITE_ENV" ]; then
  echo "error: $SITE_ENV not found." >&2
  echo "       cp $(dirname "$0")/site.env.example $SITE_ENV and fill in your own values." >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$SITE_ENV"

for v in PVE_HOST PVE_NODE PVE_VMID ARK_SERVICE PVE_PW_KEY; do
  [ -n "${!v:-}" ] || { echo "error: $v is empty in $SITE_ENV" >&2; exit 1; }
done

echo "→ syncing $PROJ to $TARGET:$REMOTE_DIR"
ssh "$TARGET" "mkdir -p $REMOTE_DIR/deploy"
rsync -az --delete \
  --exclude node_modules --exclude .git --exclude '*.log' \
  --exclude 'backend/.env' --exclude 'deploy/.env' \
  "$PROJ"/ "$TARGET:$REMOTE_DIR"/

echo "→ writing remote deploy/.env (secrets from Keychain)"
# Which Keychain entries hold the secrets. The names themselves are site-specific
# (they tend to be named after your own hosts), so they come from site.env too.
PVE_PW="$(~/.claude/bin/secret get "${PVE_PW_KEY:?PVE_PW_KEY missing in site.env}")"
UNIFI_KEY="$(~/.claude/bin/secret get "${UNIFI_KEY_KEY:-unifi/api-key}" 2>/dev/null || true)"

# Dashboard login. The panel can stop worlds and read admin passwords, so the
# backend refuses every request when DASH_PASS is empty. Generate once, keep it
# in the Keychain so redeploys reuse the same password instead of locking you out.
DASH_USER="${DASH_USER:-admin}"
DASH_PW="$(~/.claude/bin/secret get ark-dashboard/admin-pw 2>/dev/null || true)"
if [ -z "$DASH_PW" ]; then
  DASH_PW="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)"
  ~/.claude/bin/secret set ark-dashboard/admin-pw "$DASH_PW"
  echo "  generated a dashboard password → Keychain key ark-dashboard/admin-pw"
fi
ssh "$TARGET" "umask 077; cat > $REMOTE_DIR/deploy/.env" <<ENV
PVE_HOST=${PVE_HOST}
PVE_PORT=${PVE_PORT:-8006}
PVE_NODE=${PVE_NODE}
PVE_VMID=${PVE_VMID}
PVE_USER=${PVE_USER:-root@pam}
PVE_PASSWORD=${PVE_PW}
ARK_SERVICE=${ARK_SERVICE}
ARK_USER=${ARK_USER:-arkadmin}
ARK_MANAGER=${ARK_MANAGER:-/home/arkadmin/ark-manager/ark-manager.sh}
ARK_RCON_PORT=${ARK_RCON_PORT:-27020}
ARK_RCON_PASSWORD=
ARK_MAX_PLAYERS=${ARK_MAX_PLAYERS:-70}
ARK_RAM_ALLOC=${ARK_RAM_ALLOC:-16}
PORT=8787
# 0.0.0.0 is container-internal: Docker publishes ${HOST_PORT} on the host and
# cannot reach a process bound to the container's loopback. Exposure is limited
# by the published port + the Basic-auth login below, not by this bind address.
BIND=0.0.0.0
DASH_USER=${DASH_USER}
DASH_PASS=${DASH_PW}
POLL_INTERVAL_MS=6000
UNIFI_HOST=${UNIFI_HOST:-}
UNIFI_API_KEY=${UNIFI_KEY}
UNIFI_SITE=${UNIFI_SITE:-default}
ARK_VM_IP=${ARK_VM_IP:-}
UNIFI_FORWARD_PROTO=${UNIFI_FORWARD_PROTO:-udp}
ENV
ssh "$TARGET" "chmod 600 $REMOTE_DIR/deploy/.env"

echo "→ building + starting container (host port $HOST_PORT)"
ssh "$TARGET" "cd $REMOTE_DIR && HOST_PORT=$HOST_PORT docker compose up -d --build"

echo "→ health check"
sleep 8
# /api/health sits behind the login like every other route, so authenticate here.
# Credentials go in over stdin (-K -) so they never land in argv on either host.
ssh "$TARGET" "curl -s --max-time 8 -K - http://127.0.0.1:$HOST_PORT/api/health || echo 'health check failed'" <<CURLRC
user = "$DASH_USER:$DASH_PW"
CURLRC
echo ""
echo "✓ deployed. Dashboard: http://$(echo "$TARGET" | sed 's/.*@//'):$HOST_PORT/"
echo "  login: $DASH_USER  ·  password: secret get ark-dashboard/admin-pw"
