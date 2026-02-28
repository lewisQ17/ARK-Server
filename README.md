# ARK: Survival Ascended - Linux Server Manager

A clean, powerful, map-centered server manager for running ARK: Survival Ascended dedicated servers on Linux via GE-Proton.

## Features

- **Map-Centered Dashboard** — See all maps at a glance with status, health, player count, ports, and mods
- **One-Command Install** — Clone the repo, run the script, select Install, and you're done
- **Per-Map Management** — Start, stop, restart, update any map independently
- **RCON Console** — Built-in RCON client for sending commands to running servers
- **Mod Management** — Add, remove, and update Steam Workshop mods per map
- **Server Settings** — Tune XP, taming, harvesting, and 40+ other settings from a menu
- **Graphics Presets** — Low / Medium / High / Auto quality presets per map
- **Backup & Restore** — Full world backup/restore with timestamped archives
- **Auto-Restart & Healthcheck** — Scheduled restarts with player warnings + crash auto-recovery
- **Log Viewer** — Tail live logs or view recent history per map
- **System Optimization** — Tuned kernel, RAM, CPU, and game graphics settings out of the box
- **Logrotate** — Automatic log rotation to prevent disk filling
- **Security** — Passwords kept out of git, template configs provided

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/lewisQ17/ARK-Server.git
cd ARK-Server

# 2. Make executable and run
chmod +x ark-manager.sh
./ark-manager.sh

# 3. Select "Install / Update Server" from the menu
#    This installs SteamCMD, GE-Proton, and the ARK dedicated server automatically.

# 4. Select "Add Map" to create your first map (e.g. Extinction, TheIsland, etc.)
#    Set your admin password when prompted.

# 5. Start your map from the dashboard!
```

## How to Run

```bash
# Interactive dashboard (recommended)
./ark-manager.sh

# Or use CLI commands directly:
./ark-manager.sh start Extinction
./ark-manager.sh stop Extinction
./ark-manager.sh status

# Via systemd (auto-start on boot):
sudo systemctl start ark-extinction
sudo systemctl enable ark-extinction
```

## Graphics Presets

Each map can have its own graphics preset. Change it via **Server Settings → Graphics Preset**.

| Preset     | Quality | Resolution | FPS Limit | Effects        | Best For                  |
| ---------- | ------- | ---------- | --------- | -------------- | ------------------------- |
| **Low**    | 0       | 640×480    | 30        | All off        | Max performance, low RAM  |
| **Medium** | 2       | 1280×720   | 60        | Basic          | Balanced                  |
| **High**   | 3       | 1920×1080  | Unlimited | All on         | Best quality (default)    |
| **Auto**   | 3       | 1920×1080  | Unlimited | All on + adapt | High + dynamic resolution |

> **Note:** With `-NullRHI` (headless mode, default for dedicated servers), the server does not render graphics.
> These settings define the quality configuration. To enable rendering, set `UseNullRHI=false` in `config/optimization.conf`.

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

## Requirements

- Ubuntu 22.04+ / Debian 12+ (or similar)
- 16 GB RAM minimum (per map running)
- 25 GB free disk space minimum
- CPU with AVX/AVX2 support
- Internet connection for Steam downloads

## Security

**Passwords are NOT stored in git.** Map configs (`maps/*/map.conf`) and game settings are gitignored.

- Use `templates/map.conf.example` as a starting point
- Set your admin password when adding a map via the script
- The script will prompt for passwords interactively
- Never commit real passwords to the repository

## File Structure

```
ark-manager.sh              # Main management script (run this!)
rcon.py                     # RCON client
config/
  maps.conf                 # Map definitions (auto-managed)
  server-defaults.conf      # Default server settings
  optimization.conf         # Performance tuning + graphics preset docs
templates/
  map.conf.example          # Template for map configuration
maps/
  <MapName>/
    map.conf                # Per-map settings (gitignored — contains passwords)
    Game.ini                # Game rules (gitignored)
    GameUserSettings.ini    # Graphics & gameplay settings (gitignored)
    server.log              # Server output log
    backups/                # World save backups
healthcheck.sh              # Auto-restart crashed maps (cron)
```

## CLI Usage

```bash
./ark-manager.sh                      # Interactive dashboard
./ark-manager.sh install              # Install/update server
./ark-manager.sh start <map>          # Start a specific map
./ark-manager.sh stop <map>           # Stop a specific map
./ark-manager.sh restart <map>        # Restart a specific map
./ark-manager.sh status               # Show all map statuses
./ark-manager.sh update               # Update game server files
./ark-manager.sh rcon <map> "cmd"     # Send RCON command
./ark-manager.sh backup <map>         # Backup map world
./ark-manager.sh start-all            # Start all maps
./ark-manager.sh stop-all             # Stop all maps
./ark-manager.sh broadcast "message"  # Message all running maps
```

## VM / Proxmox Optimization

For best performance on Proxmox:

- Set CPU type to **host** (required for AVX/AVX2)
- Allocate **16 GB RAM** minimum
- Use **virtio** disk and network drivers
- The script auto-tunes kernel parameters (`sysctl`) on install

## License

MIT — Use freely, contribute back if you can.
