# ARK Server Manager — dashboard

Live web dashboard for an ARK: Survival Ascended server: status, players, RCON,
config, logs and backups from the browser.

## Two modes

| `ARK_EXEC_MODE` | When | How it reaches the server |
|---|---|---|
| **`local`** | The game server runs on the same machine as the dashboard. This is what `install.sh` in the [ARK-Server](https://github.com/lewisQ17/ARK-Server) repo sets up. | Runs `ark-manager.sh` directly, stepping down to the unprivileged `arkadmin` user. Host metrics come from `/proc`. |
| **`proxmox`** | The game server lives in a Proxmox VM (the original homelab setup). | Proxmox API for metrics and power, guest-agent exec for everything else. **Nothing is installed on the ARK VM.** |

Leave `ARK_EXEC_MODE` empty and it auto-detects: no `PVE_PASSWORD` means `local`.

## Login

The dashboard can start and stop worlds, run RCON and read admin passwords out of
`map.conf`, so it is **never** served unauthenticated:

- Set `DASH_USER` / `DASH_PASS` in `deploy/.env`. `install.sh` generates a password
  for you and prints it at the end.
- Without `DASH_PASS` every request returns **503** — fail-closed by design.
- It binds to `127.0.0.1` unless you set `BIND=0.0.0.0`. From outside, prefer an
  SSH tunnel or a Cloudflare tunnel over forwarding the port.

```bash
ssh -N -L 8787:127.0.0.1:8787 you@your-server   # then open http://localhost:8787
```

## How it connects in proxmox mode (nothing on the ARK VM)

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
