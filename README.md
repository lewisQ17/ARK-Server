## ARK ASA Server Manager (map-based)

This directory contains the **recommended, map-based manager** for ARK: Survival Ascended dedicated servers.

- `ark-manager.sh`: main entrypoint (TUI dashboard + CLI).
- `config/`: global defaults and optimization settings.
- `maps/<MapName>/`: per-map config (`map.conf`, `GameUserSettings.ini`, `Game.ini`, `mods.conf`, `backups/`).
- `server-files/`, `steamcmd/`, `GE-Proton*/`: server binaries, SteamCMD and Proton runtime.

### Quick usage

- Start interactive dashboard:
  - `./ark-manager.sh`
- Install / update server (SteamCMD + Proton + ASA binaries):
  - `./ark-manager.sh install`  (or `update`)
- Manage maps:
  - Add map: dashboard → **Add Map**
  - Start/Stop/Restart: dashboard → **Select Map → Start/Stop/Restart**
  - Start/Stop all batch maps:
    - `./ark-manager.sh start-all`
    - `./ark-manager.sh stop-all`
- Backups:
  - Per map: map menu → **Backup World** / **Restore Backup**
  - Files in: `maps/<MapName>/backups/`.

### System integration

`ark-manager.sh` can integrate with the host system:

- **systemd services**: `ark-<map>.service` created via `create_systemd_service` (called when adding a map).
- **Healthcheck**:
  - Script: `healthcheck.sh` (auto-generated).
  - Cron: every 5 minutes (if system tuning is enabled).
- **Log rotation**:
  - `/etc/logrotate.d/ark-server` (server logs + Steam logs).
- **Kernel tuning**:
  - `/etc/sysctl.d/99-ark-server.conf` (net/memory tweaks).

All these are applied via `apply_optimizations` during `install`, and can be controlled with the `EnableSystemTuning` flag.

### Configuration & security

- Global defaults: `config/server-defaults.conf`
  - Ports, rates, QoL options, default start parameters.
- Optimization: `config/optimization.conf`
  - **EnableSystemTuning=true/false** → controls whether sysctl/logrotate/healthcheck are applied.
- Per-map:
  - `maps/<MapName>/map.conf`:
    - Includes ports, passwords (`AdminPassword`, `ServerPassword`), cluster ID, and custom flags.
    - File permissions are tightened to `600` when created.
  - `maps/<MapName>/GameUserSettings.ini`:
    - Generated via `create_optimized_game_settings`, mirrors passwords from `map.conf` and is also set to `600`.

> **Tip:** Choose a strong `AdminPassword` when creating a map. The manager warns if you leave it empty and lets you abort.

### Legacy vs new manager

- **New (recommended)**: this map-based manager in `ARK server/`.
- **Legacy**: multi-instance scripts in `old-manager/` (`ark_instance_manager.sh`, `ark_restart_manager.sh`), kept only for existing setups.
  - New deployments should **not** use `old-manager/` and should migrate to `ark-manager.sh` where possible.

# ARK: Survival Ascended — Linux Server Manager

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

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/lewisQ17/ARK-Server.git
cd ARK-Server

# 2. Make executable and run
chmod +x ark-manager.sh
./ark-manager.sh

# 3. Select "Install / Update Server" from the menu
#    This installs SteamCMD, GE-Proton, and the ARK dedicated server.

# 4. Select "Add Map" to create your first map (e.g. Extinction, TheIsland)
#    Set your admin password when prompted.

# 5. Start your map from the dashboard!
```

## CLI Usage

```bash
./ark-manager.sh                      # Interactive dashboard (live refresh)
./ark-manager.sh install              # Install/update server
./ark-manager.sh start <map>          # Start a specific map
./ark-manager.sh stop <map>           # Stop a specific map
./ark-manager.sh restart <map>        # Restart a specific map
./ark-manager.sh start-all            # Start all groep maps
./ark-manager.sh stop-all             # Stop all groep maps
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

## Requirements

- **OS:** Ubuntu 22.04+ / Debian 12+
- **RAM:** 16 GB minimum (per running map)
- **Disk:** 25 GB free minimum
- **CPU:** Must support AVX/AVX2 (set CPU type to `host` in Proxmox)
- **Network:** Internet for Steam downloads, open ports for players

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
