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
- Running in Docker, `BIND` **must** be `0.0.0.0`: the published port cannot
  reach a process bound to the container's loopback. `deploy/deploy.sh` writes
  that plus a generated login into the remote `.env` (kept in the macOS Keychain
  as `ark-dashboard/admin-pw`, so redeploys reuse it instead of locking you out).

```bash
ssh -N -L 8787:127.0.0.1:8787 you@your-server   # then open http://localhost:8787
```

## Setup — what you have to fill in

This repo deliberately ships **no addresses**. Every setting that used to default
to a real machine is now empty, so nothing here points at anyone else's network —
which also means proxmox mode needs your own values before it will start. It tells
you exactly which ones are missing instead of failing silently.

**Using `local` mode? There is nothing to do.** `install.sh` generates everything,
including the dashboard login. The table below only applies to proxmox mode and to
deploying the container to a separate Docker host.

### 1. Running the backend directly (proxmox mode)

```bash
cp dashboard/.env.example dashboard/backend/.env
```

Then fill in:

| Setting | Required | What it is | Where to find it |
|---|---|---|---|
| `PVE_HOST` | yes | Proxmox host or IP | the address you open the PVE web UI on |
| `PVE_NODE` | yes | node name | top-left in the PVE UI, e.g. `pve` |
| `PVE_VMID` | yes | numeric id of the ARK VM | shown next to the VM in the PVE UI |
| `PVE_USER` | no | defaults to `root@pam` | — |
| `PVE_PASSWORD` | yes | password for that user | your password manager |
| `PVE_TLS_FINGERPRINT` | yes | SHA-256 pin of the PVE certificate | see the command below |
| `DASH_PASS` | yes | dashboard login password | pick one; without it every request returns 503 |

Get the fingerprint (replace the host and port with your own):

```bash
echo | openssl s_client -connect YOUR_PVE_HOST:8006 2>/dev/null   | openssl x509 -fingerprint -sha256 -noout
```

Paste the value after `sha256 Fingerprint=` — with or without colons, both parse.
If you would rather skip pinning while testing, set `PVE_TLS_INSECURE=1` instead,
but read the security note at the bottom first.

### 2. Deploying to a Docker host

```bash
cp dashboard/deploy/site.env.example dashboard/deploy/site.env
```

`site.env` holds the same connection details plus the names of the entries where
`deploy.sh` looks up your secrets. It is **gitignored** — it describes your network,
so it must never be committed. `deploy.sh` refuses to run when a required value is
missing rather than deploying something half-configured.

Optional, only if you want the dashboard to open WAN port-forwards for new maps:
set `UNIFI_HOST`, `ARK_VM_IP` and `UNIFI_TLS_FINGERPRINT`, and store the API key in
the entry named by `UNIFI_KEY_KEY`. Leave them empty and that feature stays off.

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
          Proxmox node ──guest-exec──► ARK VM
                     └─rrddata────►  (metrics, no guest touch)
```

## Layout

```
backend/    Express API + poller (proxmox.js, ark.js, server.js, config.js)
frontend/   index.html (design template + live logic) + support.js (dc-runtime) + React
deploy/     deploy.sh + site.env (your addresses, gitignored) + .env (secrets, gitignored)
Dockerfile, docker-compose.yml
```

The frontend reuses the design's exact template (`frontend/_template.xdc.html`)
rendered by the dc-runtime; `frontend/live.dcscript.js` replaces the prototype's
mock data with live API data. Rebuild `index.html` after editing either:
`bash frontend/build.sh`.

## Run

Local dev (see [Setup](#setup--what-you-have-to-fill-in) for the values):
```bash
cd backend && cp ../.env.example .env   # then fill it in
npm install && npm start                # http://localhost:8787
```

Deploy to a Docker host (needs `deploy/site.env` first):
```bash
cp deploy/site.env.example deploy/site.env   # fill in your own addresses
./deploy/deploy.sh <ssh-target>              # rsync + writes remote .env + docker compose up --build
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

- Proxmox and UniFi use self-signed certs, so CA-chain validation cannot work. The
  client pins the exact peer certificate by SHA-256 fingerprint instead
  (`backend/pinned-agent.js`) and **fails closed**: without `PVE_TLS_FINGERPRINT`
  it refuses to start rather than sending the root ticket to an unverified peer.
  `PVE_TLS_INSECURE=1` overrides that, but then any device on your LAN can
  intercept the credential — only use it while testing.
- The container holds the PVE **root** password (in `deploy/.env`, chmod 600). Better:
  create a scoped Proxmox API token (VM.Audit + VM.GuestAgent + VM.PowerMgmt on
  `/vms/<your-vmid>`) and use that instead.
- RCON admin password is weak (`map.conf` `AdminPassword`) and, per the known ARK-manager
  bug, appears in the server's own launch args. Rotating it is recommended separately.
