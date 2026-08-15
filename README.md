# ARK: Survival Ascended — server + dashboard for Ubuntu

Run your own ASA dedicated server on a plain Ubuntu machine. One command installs
everything, creates your first map, sets up a web dashboard behind a login, and
tells you exactly what is left for you to do.

```bash
git clone https://github.com/lewisQ17/ARK-Server.git
cd ARK-Server
sudo ./install.sh
```

That's it. The installer walks you through the rest and prints your login details
at the end (also saved to `/root/ark-install-summary.txt`).

## What the installer does

| Step | What happens |
|---|---|
| 1 | Checks the machine: Ubuntu, x86_64, RAM and free disk. Warns before continuing if something is tight. |
| 2 | Installs the packages and creates an unprivileged `arkadmin` user that owns and runs the server. |
| 3 | Downloads SteamCMD, GE-Proton and the ASA server files (~30 GB). |
| 4 | Creates your first map with a generated admin password, a systemd service and firewall rules. |
| 5 | Installs the web dashboard as a service, with a generated login. |
| 6 | Asks how you want to reach it — see below. |

It is **idempotent**: run it again after a failure and it skips whatever is already done.
Nothing is exposed to the internet unless you ask for it.

### Options

```bash
sudo ./install.sh --yes --map TheIsland    # unattended
sudo ./install.sh --no-dashboard           # game server only
sudo ./install.sh --expose tunnel          # skip the exposure question
sudo ./install.sh --help                   # all options
```

## How players reach your server

Whatever you pick for the dashboard, **players always connect straight to the game**,
so these two have to be forwarded on your router:

| Port | Protocol | Why |
|---|---|---|
| 7777 | UDP | Game traffic — without this nobody can join |
| 27015 | UDP | Steam query — without this you don't show up in the server list |

**Never forward 27020 (RCON).** It stays on localhost; the dashboard talks to it locally.

## How *you* reach the dashboard

The installer asks which you want:

- **LAN only** *(recommended)* — reachable on your own network. From outside, tunnel in:
  `ssh -N -L 8787:127.0.0.1:8787 you@your-server`, then open `http://localhost:8787`.
  Nothing is exposed.
- **Port-forward** — you open the dashboard port on your router yourself. It works, but
  it publishes an admin panel on your home IP where only the login stands between a
  stranger and your server. The installer prints the exact ports and warns you.
- **Cloudflare Tunnel** — free, outbound-only: no open ports, your home IP stays hidden,
  and you get an https address. The installer sets up `cloudflared` and prints the
  remaining browser steps. Note this only carries the dashboard, not game traffic.

## After installing

```bash
sudo -u arkadmin /opt/ark-server/ark-manager.sh            # interactive menu
sudo -u arkadmin /opt/ark-server/ark-manager.sh start-all  # start every map
systemctl status ark-dashboard                             # the web dashboard
```

Your passwords live in `/opt/ark-server/maps/<Map>/map.conf` (mode 600) and
`/opt/ark-dashboard/deploy/.env`. Change them whenever you like — restart the
dashboard afterwards with `systemctl restart ark-dashboard`.

## Requirements

- Ubuntu 22.04 or 24.04, x86_64
- 16 GB RAM per map (12 GB is the floor; the installer warns below that)
- ~40 GB free disk
- Root access on the machine

---

# Reference — the manager in detail

A clean, powerful, map-centered server manager for running ARK: Survival Ascended dedicated servers on Linux via GE-Proton.

## Features

### Dashboard & Live Monitoring

- **Flicker-Free Live Dashboard** — System info + map table refresh every 2s without screen clear
- **Input Preservation** — Typed characters are never lost during live refresh; take your time
- **Server IP Display** — Always see your server's IP address in the system info bar
- **Per-Map Status** — Status, health, players, uptime, RAM, CPU, JOIN, AUTO columns
- **JOIN Check** — Real external network reachability test (ports + firewall + TCP connect)
- **AUTO Column** — Shows systemd auto-start status per map

### Server Management

- **One-Command Install** — Run the script, select Install, done (SteamCMD + GE-Proton + ARK)
- **Per-Map Management** — Start, stop, restart any map independently
- **Groep (Batch)** — Toggle maps in/out of batch start/stop groups
- **Auto-Start** — Toggle systemd auto-start per map (survives reboots)
- **RCON Console** — Built-in interactive RCON client per map
- **Broadcast** — Send messages to all running maps at once

### Configuration

- **Mod Management** — Add, remove, toggle, rename mods with Steam Workshop name auto-fetch
- **Server Settings** — Tune XP, taming, harvesting, and 10+ other settings from a menu
- **Graphics Presets** — Low / Medium / High / Auto quality presets per map
- **Per-Map Config** — Each map has its own ports, passwords, mods, and settings

### Maintenance

- **Backup & Restore** — Full world backup/restore with timestamped archives
- **Scheduled Restarts** — Daily restarts with 30m/10m/3m player warnings
- **Healthcheck** — Cron-based crash detection and auto-recovery
- **Log Viewer** — Tail live logs, view history, filter errors per map
- **Logrotate** — Automatic log rotation to prevent disk filling

### Security

- **Delete Protection** — Double confirmation required to delete a map

## Manual setup (without install.sh)

Prefer to do it yourself, or installing onto a machine that already has SteamCMD?

```bash
git clone https://github.com/lewisQ17/ARK-Server.git
cd ARK-Server
chmod +x ark-manager.sh

./ark-manager.sh install                       # SteamCMD + GE-Proton + server files
./ark-manager.sh add-map TheIsland --admin-pw 'choose-something-strong'
./ark-manager.sh start TheIsland
```

Or just run `./ark-manager.sh` and use the menu.

## CLI Usage

```bash
./ark-manager.sh                      # Interactive dashboard (live refresh)
./ark-manager.sh install              # Install/update server
./ark-manager.sh start <map>          # Start a specific map
./ark-manager.sh stop <map>           # Stop a specific map
./ark-manager.sh restart <map>        # Restart a specific map
./ark-manager.sh start-all            # Start all groep maps
./ark-manager.sh stop-all             # Stop all groep maps
./ark-manager.sh add-map <Name>       # Create a map without the menu (scriptable)
./ark-manager.sh status               # Show all map statuses (CLI)
./ark-manager.sh rcon <map> "cmd"     # Send RCON command
./ark-manager.sh backup <map>         # Backup map world
./ark-manager.sh broadcast "message"  # Message all running maps
./ark-manager.sh help                 # Show help
```

## Graphics Presets

| Preset     | Quality | Resolution | FPS Limit | Effects        | Best For                 |
| ---------- | ------- | ---------- | --------- | -------------- | ------------------------ |
| **Low**    | 0       | 640×480    | 30        | All off        | Max performance, low RAM |
| **Medium** | 2       | 1280×720   | 60        | Basic          | Balanced                 |
| **High**   | 3       | 1920×1080  | Unlimited | All on         | Best quality (default)   |
| **Auto**   | 3       | 1920×1080  | Unlimited | All on + adapt | High + dynamic res       |

> **Note:** With `-NullRHI` (headless mode, default), the server does not render graphics.
> These define the quality config sent to clients. To enable server rendering, set `UseNullRHI=false` in `config/optimization.conf`.

## Supported Maps

| Map Name       | Internal Name    |
| -------------- | ---------------- |
| The Island     | TheIsland_WP     |
| Scorched Earth | ScorchedEarth_WP |
| Aberration     | Aberration_WP    |
| Extinction     | Extinction_WP    |
| The Center     | TheCenter_WP     |
| Ragnarok       | Ragnarok_WP      |
| Valguero       | Valguero_WP      |
| Crystal Isles  | CrystalIsles_WP  |
| Lost Island    | LostIsland_WP    |
| Fjordur        | Fjordur_WP       |
| Genesis Part 1 | Genesis_WP       |
| Genesis Part 2 | Gen2_WP          |

## File Structure

```
ark-manager.sh              # Main management script (run this!)
rcon.py                     # RCON client (Python 3)
healthcheck.sh              # Auto-restart crashed maps (cron, auto-generated)
config/
  maps.conf                 # Map registry (auto-managed)
  server-defaults.conf      # Default server settings
  optimization.conf         # Performance tuning
templates/
  map.conf.example          # Template for map configuration
maps/
  <MapName>/
    map.conf                # Per-map settings (gitignored — passwords)
    mods.conf               # Per-map mod list (gitignored)
    Game.ini                # Game rules (gitignored)
    GameUserSettings.ini    # Graphics & gameplay settings (gitignored)
    server.log              # Server output log
    backups/                # World save backups
```

## Proxmox / VM Optimization

- Set CPU type to **host** (required for AVX/AVX2)
- Allocate **16 GB RAM** minimum per map
- Use **virtio** disk and network drivers
- The script auto-tunes kernel parameters (`sysctl`) on install

## Changelog

### v2.3 — Live Refresh Done Right

- Flicker-free live dashboard (cursor positioning, no screen clear)
- Input preservation — typed characters survive refreshes
- Server IP shown in system info bar
- Fast CPU reading via `/proc/stat` delta (replaces slow `top -bn1`)
- Delete map requires double confirmation
- Invalid choice feedback (shows what you typed)
- Pending input indicator with clear option (`c` to wis)
- Cleanup trap restores terminal on exit (Ctrl+C safe)
- `mods.conf` added to `.gitignore`
- `BatchEnabled` added to template

### v2.2 — Live Dashboard & UX

- 2s auto-refresh dashboard
- JOIN column (external network reachability check)
- AUTO column (systemd auto-start status)
- Groep (batch) toggle for start/stop all
- Player count caching (30s), JOIN caching (15s)
- Multi-byte `pad()` fix for table alignment

### v2.1 — Per-Map Resources

- CPU & RAM per map (cgroup + process tree)
- Mod management with Steam Workshop name fetch
- Batch start/stop all maps
- Graphics presets (Low/Medium/High/Auto)

### v2.0 — Initial Release

- Map-centered architecture
- SteamCMD + GE-Proton installer
- Per-map start/stop/restart
- RCON console
- Backup & restore
- Systemd integration
- Healthcheck & logrotate

## License

MIT — Use freely, contribute back if you can.
