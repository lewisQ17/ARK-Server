// config.js — environment + defaults.
// Instances are DISCOVERED live from the VM (maps/*/map.conf), not hardcoded, so
// the dashboard only ever shows maps that actually exist.

require('dotenv').config();
const env = process.env;

const config = {
  port: parseInt(env.PORT || '8787', 10),

  proxmox: {
    host: env.PVE_HOST || '10.0.0.10',
    port: parseInt(env.PVE_PORT || '8006', 10),
    node: env.PVE_NODE || 'pve',
    vmid: parseInt(env.PVE_VMID || '100', 10),
    user: env.PVE_USER || 'root@pam',
    password: env.PVE_PASSWORD || '',
    tlsFingerprint: env.PVE_TLS_FINGERPRINT || '',   // SHA-256 cert pin (required unless tlsInsecure)
    tlsInsecure: env.PVE_TLS_INSECURE === '1',       // explicit opt-in to unverified TLS
  },

  // Leak-guard: ASA leaks memory over uptime. Auto save+restart a world when its RAM
  // crosses the ceiling AND nobody is online (never disturbs players). Opt-out via env.
  leakGuard: {
    enabled: env.ARK_LEAK_GUARD !== '0',
    ramGB: parseFloat(env.ARK_LEAK_GUARD_GB || '12'),
    minUptimeH: parseFloat(env.ARK_LEAK_GUARD_MIN_UPTIME_H || '12'),
    cooldownH: parseFloat(env.ARK_LEAK_GUARD_COOLDOWN_H || '6'),
  },

  // ARK manager on the VM.
  ark: {
    user: env.ARK_USER || 'arkadmin',
    manager: env.ARK_MANAGER || '/home/arkadmin/ark-manager/ark-manager.sh',
    servicePrefix: 'ark-',           // systemd unit = ark-<mapname,lowercase>
    ramAllocGB: parseInt(env.ARK_RAM_ALLOC || '16', 10),
    coresTotal: parseInt(env.PVE_VM_CORES || '4', 10),   // the ARK VM vCPU count — ceiling for per-world CPU caps (falls back if Proxmox status omits it)
    rconPasswordOverride: env.ARK_RCON_PASSWORD || '',
  },

  // Official ARK: Survival Ascended maps (display → internal), for the "Add map" picker.
  officialMaps: {
    TheIsland: 'TheIsland_WP', ScorchedEarth: 'ScorchedEarth_WP', Aberration: 'Aberration_WP',
    Extinction: 'Extinction_WP', TheCenter: 'TheCenter_WP', Ragnarok: 'Ragnarok_WP',
    Valguero: 'Valguero_WP', CrystalIsles: 'CrystalIsles_WP', LostIsland: 'LostIsland_WP',
    Fjordur: 'Fjordur_WP', GenesisPart1: 'Genesis_WP', GenesisPart2: 'Gen2_WP',
  },

  // UniFi/UDM — auto-manage the WAN port-forward for a map's game port on create/delete.
  // Disabled unless UNIFI_API_KEY is set. Forward target = the ARK VM's (reserved) LAN IP.
  unifi: {
    enabled: !!env.UNIFI_API_KEY,
    host: env.UNIFI_HOST || '10.0.0.1',
    apiKey: env.UNIFI_API_KEY || '',
    site: env.UNIFI_SITE || 'default',
    arkVmIp: env.ARK_VM_IP || '10.0.0.50',
    proto: env.UNIFI_FORWARD_PROTO || 'udp',
    tlsFingerprint: env.UNIFI_TLS_FINGERPRINT || '',   // SHA-256 cert pin (required when enabled, unless tlsInsecure)
    tlsInsecure: env.UNIFI_TLS_INSECURE === '1',
  },

  pollIntervalMs: parseInt(env.POLL_INTERVAL_MS || '6000', 10),
  discoverEveryN: 5,   // re-scan maps/ every N poll cycles
  histLen: 44,
};

module.exports = config;
