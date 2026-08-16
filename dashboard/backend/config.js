// config.js — environment + defaults.
// Instances are DISCOVERED live from the VM (maps/*/map.conf), not hardcoded, so
// the dashboard only ever shows maps that actually exist.

require('dotenv').config();
const env = process.env;

const config = {
  port: parseInt(env.PORT || '8787', 10),

  // Where to listen. Default 127.0.0.1: reachable over an SSH tunnel, invisible to
  // the rest of the network until someone deliberately opens it up. install.sh
  // flips this to 0.0.0.0 when you choose LAN or port-forward.
  bind: env.BIND || '127.0.0.1',

  // How commands reach the game server.
  //   proxmox — the original setup: the server lives in a VM, everything goes over
  //             the qemu-guest-agent.
  //   local   — the server runs on this same machine; run the manager directly.
  // Auto-detected: no PVE_PASSWORD means there is nothing to talk to, so local.
  mode: (env.ARK_EXEC_MODE || (env.PVE_PASSWORD ? 'proxmox' : 'local')).toLowerCase(),

  // Login for the dashboard itself. Fail-closed: without a password every request
  // is refused rather than serving an unauthenticated admin panel.
  auth: {
    enabled: env.DASH_AUTH_DISABLED !== '1',
    user: env.DASH_USER || 'admin',
    pass: env.DASH_PASS || '',
  },

  local: {
    // The unprivileged account that owns the server files and runs the maps.
    runAsUser: env.ARK_USER || 'arkadmin',
    // "Reboot the VM" means rebooting this machine in local mode — off by default.
    allowHostPower: env.ALLOW_HOST_POWER === '1',
  },

  // No site addresses are baked in here on purpose: a default that points at a
  // real machine is either wrong for you or advertises where someone else's box
  // lives. proxmox mode reads all of it from .env and refuses to start when it
  // is incomplete — see the validation at the bottom of this file.
  proxmox: {
    host: env.PVE_HOST || '',
    port: parseInt(env.PVE_PORT || '8006', 10),
    node: env.PVE_NODE || '',
    vmid: parseInt(env.PVE_VMID || '0', 10),
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
    coresTotal: parseInt(env.PVE_VM_CORES || '4', 10),   // VM vCPU count — ceiling for per-world CPU caps (falls back if Proxmox status omits it)
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
  // Needs all three of UNIFI_API_KEY, UNIFI_HOST and ARK_VM_IP: a key without a
  // target would otherwise look enabled and then fail on every call. Forward
  // target = the ARK VM's (reserved) LAN IP.
  unifi: {
    enabled: !!(env.UNIFI_API_KEY && env.UNIFI_HOST && env.ARK_VM_IP),
    host: env.UNIFI_HOST || '',
    apiKey: env.UNIFI_API_KEY || '',
    site: env.UNIFI_SITE || 'default',
    arkVmIp: env.ARK_VM_IP || '',
    proto: env.UNIFI_FORWARD_PROTO || 'udp',
    tlsFingerprint: env.UNIFI_TLS_FINGERPRINT || '',   // SHA-256 cert pin (required when enabled, unless tlsInsecure)
    tlsInsecure: env.UNIFI_TLS_INSECURE === '1',
  },

  pollIntervalMs: parseInt(env.POLL_INTERVAL_MS || '6000', 10),
  discoverEveryN: 5,   // re-scan maps/ every N poll cycles
  histLen: 44,
};

// Fail fast instead of dialing an empty host: in proxmox mode the connection
// details are mandatory, and a missing one used to be masked by a baked-in
// default that pointed at the original homelab.
if (config.mode === 'proxmox') {
  const missing = ['PVE_HOST', 'PVE_NODE', 'PVE_VMID']
    .filter((k) => !process.env[k] || process.env[k] === '0');
  if (missing.length) {
    throw new Error(
      `ARK_EXEC_MODE=proxmox needs ${missing.join(', ')} in the environment. ` +
      'Copy .env.example to .env and fill in your own Proxmox host/node/VM id.'
    );
  }
}

module.exports = config;
