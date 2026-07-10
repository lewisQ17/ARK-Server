#!/usr/bin/env bash
# Deploy the ARK dashboard to a Docker host over SSH.
#   ./deploy/deploy.sh <ssh-target>
# e.g. ./deploy/deploy.sh docker-host   (or root@10.0.0.20, or an ssh alias)
#
# Pulls the PVE root password from the macOS Keychain and writes it into a
# remote deploy/.env (chmod 600). The RCON admin password is NOT stored here —
# the app reads it from the ARK VM at runtime.
set -euo pipefail

TARGET="${1:?usage: deploy.sh <ssh-target>}"
REMOTE_DIR="${2:-/opt/ark-dashboard}"
HOST_PORT="${3:-8790}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"

echo "→ syncing $PROJ to $TARGET:$REMOTE_DIR"
ssh "$TARGET" "mkdir -p $REMOTE_DIR/deploy"
rsync -az --delete \
  --exclude node_modules --exclude .git --exclude '*.log' \
  --exclude 'backend/.env' --exclude 'deploy/.env' \
  "$PROJ"/ "$TARGET:$REMOTE_DIR"/

echo "→ writing remote deploy/.env (secrets from Keychain)"
PVE_PW="$(~/.claude/bin/secret get proxmox/root-pw-old)"
UNIFI_KEY="$(~/.claude/bin/secret get unifi/api-key 2>/dev/null || true)"
ssh "$TARGET" "umask 077; cat > $REMOTE_DIR/deploy/.env" <<ENV
PVE_HOST=10.0.0.10
PVE_PORT=8006
PVE_NODE=pve
PVE_VMID=100
PVE_USER=root@pam
PVE_PASSWORD=${PVE_PW}
ARK_SERVICE=ark-extinction
ARK_USER=arkadmin
ARK_MANAGER=/home/arkadmin/ark-manager/ark-manager.sh
ARK_RCON_PORT=27020
ARK_RCON_PASSWORD=
ARK_MAX_PLAYERS=70
ARK_RAM_ALLOC=16
PORT=8787
POLL_INTERVAL_MS=6000
UNIFI_HOST=10.0.0.1
UNIFI_API_KEY=${UNIFI_KEY}
UNIFI_SITE=default
ARK_VM_IP=10.0.0.50
UNIFI_FORWARD_PROTO=udp
ENV
ssh "$TARGET" "chmod 600 $REMOTE_DIR/deploy/.env"

echo "→ building + starting container (host port $HOST_PORT)"
ssh "$TARGET" "cd $REMOTE_DIR && HOST_PORT=$HOST_PORT docker compose up -d --build"

echo "→ health check"
sleep 8
ssh "$TARGET" "curl -s --max-time 8 http://127.0.0.1:$HOST_PORT/api/health || echo 'health check failed'"
echo ""
echo "✓ deployed. Dashboard: http://$(echo "$TARGET" | sed 's/.*@//'):$HOST_PORT/"
