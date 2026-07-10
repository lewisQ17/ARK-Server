# ARK Server Manager — dashboard

Live web dashboard for the **Extinction** ARK: Survival Ascended server
(the ARK VM `ARK` on pve, `10.0.0.51`). Pixel-recreation of the Claude Design
handoff, wired to the real server. Runs as a Docker container on a Docker host —
**nothing is installed on the ARK VM.**

## How it connects (nothing on the ARK VM)

The backend talks to the **Proxmox API** and reaches the game server two ways:

| Data | Mechanism | Touches ARK VM? |
|------|-----------|-----------------|
| CPU / RAM / disk / net / uptime | Proxmox `rrddata` + `status/current` | no (host-level) |
| VM power (start/stop/reboot) | Proxmox `status/*` | no (host-level) |
| Service status, RCON, logs, config, backups | Proxmox **guest-agent exec** into the ARK VM | uses the already-running qemu-guest-agent; installs nothing |

RCON is localhost-only on the ARK VM, so RCON runs *inside* the VM via a tiny
Source-RCON client shipped inline to `python3` over guest-exec. The admin
password is read from the VM's own `map.conf` at runtime and passed over **stdin**
(never in a process argument, never stored in this app).

```
browser ─http→ dashboard container (Docker host)
                     │  Proxmox API (root ticket)
                     ▼
              pve ──guest-exec──► the ARK VM (ARK Extinction)
                     └─rrddata────►  (metrics, no guest touch)
```

## Layout

```
backend/    Express API + poller (proxmox.js, ark.js, server.js, config.js)
frontend/   index.html (design template + live logic) + support.js (dc-runtime) + React
deploy/     deploy.sh + .env (secrets, gitignored)
Dockerfile, docker-compose.yml
```

The frontend reuses the design's exact template (`frontend/_template.xdc.html`)
rendered by the dc-runtime; `frontend/live.dcscript.js` replaces the prototype's
mock data with live API data. Rebuild `index.html` after editing either:
`bash frontend/build.sh`.

## Run

Local dev:
```bash
cd backend && cp ../.env.example .env   # fill PVE_PASSWORD (secret get proxmox/root-pw-old)
npm install && npm start                # http://localhost:8787
```

Deploy to a Docker host:
```bash
./deploy/deploy.sh <ssh-target>         # rsync + writes .env + docker compose up --build
# dashboard on http://<host>:8790/
```

## What's live vs. placeholder

- **Live:** server status, host/VM metrics + graphs, players (RCON `ListPlayers`),
  RCON console + quick commands, live server-log console, save world, start/stop/restart,
  config file view, backups list. The 3 extra maps show honest "not deployed" cards.
- **Placeholder (no fake data):** cross-map cluster/transfers (single map), Discord
  webhook, tribes leaderboard, SteamCMD update flow, mod list, cron schedule editor —
  the panels exist but are empty until wired.

## Security notes / follow-ups

- Proxmox uses a self-signed cert; the client trusts it for the configured host only
  (`rejectUnauthorized:false`). Pin the CA for hardening.
- The container holds the PVE **root** password (in `deploy/.env`, chmod 600). Better:
  create a scoped Proxmox API token (VM.Audit + VM.GuestAgent + VM.PowerMgmt on `/vms/<your-vmid>`)
  and use that instead.
- RCON admin password is weak (`map.conf` `AdminPassword`) and, per the known ARK-manager
  bug, appears in the server's own launch args. Rotating it is recommended separately.
