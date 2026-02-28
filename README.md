# ARK: Survival Ascended - Linux Server Manager

A clean, powerful, map-centered server manager for running ARK: Survival Ascended dedicated servers on Linux via GE-Proton.

## Features

- **Map-Centered Dashboard** — See all maps at a glance with status, health, player count, ports, and mods
- **One-Command Install** — Clone the repo, run the script, select Install, and you're done
- **Per-Map Management** — Start, stop, restart, update any map independently
- **RCON Console** — Built-in RCON client for sending commands to running servers
- **Mod Management** — Add, remove, and update Steam Workshop mods per map
- **Server Settings** — Tune XP, taming, harvesting, and 40+ other settings from a menu
- **Backup & Restore** — Full world backup/restore with timestamped archives
- **Auto-Restart & Healthcheck** — Scheduled restarts with player warnings + crash auto-recovery
- **Log Viewer** — Tail live logs or view recent history per map
- **System Optimization** — Tuned kernel, RAM, CPU, and game graphics settings out of the box
- **Logrotate** — Automatic log rotation to prevent disk filling

## Quick Start

```bash
# 1. Clone
git clone https://github.com/lewisQ17/ARK-Server.git
cd ARK-Server

# 2. Run the manager
chmod +x ark-manager.sh
./ark-manager.sh

# 3. Select "Install / Update Server" from the menu
#    This installs SteamCMD, GE-Proton, and the ARK dedicated server automatically.

# 4. Select "Add Map" to create your first map (e.g. Extinction, TheIsland, etc.)

# 5. Start your map from the dashboard!
```

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

## File Structure

```
ark-manager.sh          # Main management script (run this)
rcon.py                 # RCON client
config/
  maps.conf             # Map definitions (auto-managed)
  server-defaults.conf  # Default server settings
  optimization.conf     # Performance tuning
maps/
  <MapName>/
    map.conf            # Per-map settings (ports, mods, passwords, etc.)
    Game.ini            # Game rules
    GameUserSettings.ini# Graphics & gameplay settings
    server.log          # Server output log
    backups/            # World save backups
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
```

## License

MIT — Use freely, contribute back if you can.
