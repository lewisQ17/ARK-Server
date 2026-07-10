// server.js — ARK Server Manager dashboard backend.
// Serves the frontend + a JSON API. Maps are discovered live from the VM, so the
// UI only shows maps that exist; new maps can be created via POST /api/maps.

const path = require('path');
const express = require('express');
const config = require('./config');
const catalog = require('./config-catalog');
const { Proxmox } = require('./proxmox');
const { Unifi } = require('./unifi');
const { ArkInstance, discoverMaps, createMap, deleteMap, suggestPorts } = require('./ark');

const app = express();
app.use(express.json());

const pmx = new Proxmox(config.proxmox);
// Optional: auto-manage the UDM WAN port-forward for each map's game port.
const udm = config.unifi.enabled ? new Unifi(config.unifi) : null;
const fwdName = (display) => `ARK-${display}`;

// ---- dynamic instance registry ----
const arks = {};          // id -> ArkInstance
let discovered = [];      // last discovered raw maps [{display, internal, ports...}]

const cache = {
  updatedAt: 0, connected: false, error: null, host: null,
  instances: {}, hist: {}, feed: [],
};
const audit = [];         // in-memory action/RCON log (newest first)
function logAudit(who, action, target, danger = false) {
  audit.unshift({ who, action, target, danger, ts: Date.now() });
  if (audit.length > 60) audit.pop();
}

async function syncMaps() {
  try {
    discovered = await discoverMaps(pmx, config.ark);
    const ids = new Set();
    for (const m of discovered) {
      const inst = new ArkInstance(pmx, config.ark, m);
      ids.add(inst.id);
      if (!arks[inst.id]) { arks[inst.id] = inst; cache.hist[inst.id] = { cpu: [], ram: [] }; }
      else arks[inst.id]._map = m; // keep latest
    }
    // drop removed maps
    for (const id of Object.keys(arks)) if (!ids.has(id)) { delete arks[id]; delete cache.instances[id]; }
  } catch (e) { console.error('[syncMaps]', e.message); }
}

function pushHist(id, cpu, ram) {
  const h = cache.hist[id] || (cache.hist[id] = { cpu: [], ram: [] });
  h.cpu.push(cpu); h.ram.push(ram);
  if (h.cpu.length > config.histLen) h.cpu.shift();
  if (h.ram.length > config.histLen) h.ram.shift();
}

function parseFeed(lines, mapName) {
  const feed = [];
  for (const line of lines.slice(-160).reverse()) {
    let m;
    if ((m = line.match(/Player "?([^"]+?)"? joined/i))) feed.push({ who: m[1], action: 'joined the server', map: mapName, type: 'join' });
    else if ((m = line.match(/Player "?([^"]+?)"? left/i))) feed.push({ who: m[1], action: 'left the server', map: mapName, type: 'leave' });
    else if (/World Save|Saving world/i.test(line)) feed.push({ who: 'Server', action: 'saved the world', map: mapName, type: 'sys' });
    else if (/advertising for join/i.test(line)) feed.push({ who: 'Server', action: 'is online — advertising for join', map: mapName, type: 'sys' });
    else if (/completed startup/i.test(line)) feed.push({ who: 'Server', action: 'completed startup', map: mapName, type: 'sys' });
    if (feed.length >= 8) break;
  }
  return feed;
}

function uptimeStr(s) {
  if (!s) return '—';
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  if (d) return `${d}d ${h}h`; if (h) return `${h}h ${m}m`; return `${m}m`;
}

let cycle = 0;
async function refresh() {
  try {
    if (cycle % config.discoverEveryN === 0) {
      await syncMaps();
      // real disk usage (Proxmox status/disk is unreliable for running VMs)
      try {
        const dr = await pmx.guestShell(`df -B1 / 2>/dev/null | tail -1`);
        const parts = (dr.out || '').trim().split(/\s+/);
        if (parts.length >= 4) { cache._diskUsed = +(parseInt(parts[2], 10) / 1e9).toFixed(0); cache._diskTotal = +(parseInt(parts[1], 10) / 1e9).toFixed(0); }
      } catch (e) { /* keep last */ }
    }
    cycle++;

    const [statusCur, rrd] = await Promise.all([
      pmx.vmStatus().catch(() => null),
      pmx.rrddata('hour').catch(() => []),
    ]);
    const points = (rrd || []).filter((p) => p.cpu != null);
    const last = points[points.length - 1] || {};
    cache.host = statusCur ? {
      name: statusCur.name || 'ARK', vmStatus: statusCur.status,
      cpus: Math.round(statusCur.cpus || config.ark.coresTotal || 4),
      cpuPct: Math.round((statusCur.cpu || last.cpu || 0) * 100),
      memUsed: +((statusCur.mem || last.mem || 0) / 1e9).toFixed(1),
      memTotal: +((statusCur.maxmem || last.maxmem || 0) / 1e9).toFixed(1),
      diskUsed: cache._diskUsed != null ? cache._diskUsed : (statusCur.disk ? +(statusCur.disk / 1e9).toFixed(0) : null),
      diskTotal: cache._diskTotal != null ? cache._diskTotal : (statusCur.maxdisk ? +(statusCur.maxdisk / 1e9).toFixed(0) : null),
      uptimeS: statusCur.uptime || 0, netin: last.netin || 0, netout: last.netout || 0,
    } : null;
    const host = cache.host;

    let anyFeed = null;
    for (const id of Object.keys(arks)) {
      const ark = arks[id];
      const st = await ark.status().catch((e) => ({ dash: 'unknown', err: e.message }));
      let players = [], cfgSummary = null;
      // Config lives in files on disk, so read it whether the server is up or down —
      // rates & multipliers must stay visible/editable even while stopped.
      cfgSummary = await ark.configSummary().catch(() => null);
      if (st.dash === 'running') {
        players = (await ark.players().catch(() => ({ players: [] }))).players || [];
        const lg = await ark.logTail(150).catch(() => ({ ok: false, lines: [] }));
        if (lg.ok && !anyFeed) anyFeed = parseFeed(lg.lines, ark.name);
      }
      const running = st.dash === 'running' || st.dash === 'starting';
      const cpuPct = running && host ? host.cpuPct : 0;
      const ramUsed = running && host ? host.memUsed : 0;
      pushHist(id, cpuPct, host ? Math.round((ramUsed / (ark.ramAlloc || 16)) * 100) : 0);
      let svcUptimeS = 0;
      if (st.startTs) { const t = Date.parse(st.startTs.replace(/^\w+ /, '')); if (!isNaN(t)) svcUptimeS = Math.max(0, Math.floor((Date.now() - t) / 1000)); }
      // Per-world compute caps (cgroup) — refreshed every discover cycle, cached in between.
      if (!cache._rsc) cache._rsc = {};
      if (cache._rsc[id] === undefined || cycle % config.discoverEveryN === 0) {
        cache._rsc[id] = await ark.resources().catch(() => null);
      }
      const rsc = cache._rsc[id];
      cache.instances[id] = {
        id, name: ark.name, code: ark.display.slice(0, 3).toUpperCase(), map: ark.map, display: ark.display,
        emblem: emblemFor(ark.display), gamemode: cfgSummary ? cfgSummary.rules.mode : 'PvE',
        status: st.dash, players: players.length, playerList: players, max: ark.maxPlayers,
        cpuPct, ramUsed, ramAlloc: ark.ramAlloc, uptime: st.dash === 'running' ? uptimeStr(svcUptimeS || (host ? host.uptimeS : 0)) : (st.dash === 'starting' ? 'booting' : '—'),
        online: st.dash === 'running', provisioned: true, config: cfgSummary,
        ports: { game: ark.gamePort, query: ark.queryPort, rcon: ark.rconPort },
        coresAlloc: rsc && rsc.cores != null ? rsc.cores : null,
        ramLimitGB: rsc && rsc.ramGB != null ? rsc.ramGB : null,
        ramLiveGB: rsc && rsc.ramUsedGB != null ? rsc.ramUsedGB : null,
      };
    }
    if (anyFeed) cache.feed = anyFeed;
    cache.connected = true; cache.error = null; cache.updatedAt = Date.now();
  } catch (e) {
    cache.connected = false; cache.error = e.message; cache.updatedAt = Date.now();
    console.error('[poller]', e.message);
  }
}

const EMBLEMS = ['#FF7A2E', '#37D67A', '#FFB23E', '#8C7BF7', '#37D3C3', '#5AA9FF', '#FF5B5B'];
function emblemFor(name) { let h = 0; for (const c of name) h = (h * 31 + c.charCodeAt(0)) & 0xffff; return EMBLEMS[h % EMBLEMS.length]; }

syncMaps().then(refresh);
setInterval(refresh, config.pollIntervalMs);

// ---------- API ----------
app.get('/api/health', (_req, res) => res.json({ ok: true, connected: cache.connected, updatedAt: cache.updatedAt, error: cache.error, maps: Object.keys(arks).length }));

app.get('/api/state', (_req, res) => {
  const instances = Object.values(cache.instances).map((c) => ({
    id: c.id, name: c.name, code: c.code, map: c.map, emblem: c.emblem, gamemode: c.gamemode,
    provisioned: true, status: c.status, players: c.players || 0, max: c.max,
    cpuPct: c.cpuPct || 0, ramUsed: c.ramUsed || 0, ramAlloc: c.ramAlloc, uptime: c.uptime || '—',
    coresAlloc: c.coresAlloc != null ? c.coresAlloc : null,
    ramLimitGB: c.ramLimitGB != null ? c.ramLimitGB : null,
    ramLiveGB: c.ramLiveGB != null ? c.ramLiveGB : null,
    config: c.config || null, ports: c.ports, hist: cache.hist[c.id],
  }));
  res.json({ updatedAt: cache.updatedAt, connected: cache.connected, error: cache.error, host: cache.host, instances, feed: cache.feed });
});

app.get('/api/instance/:id', (req, res) => {
  const c = cache.instances[req.params.id];
  if (!c) return res.status(404).json({ error: 'unknown instance' });
  res.json({ ...c, hist: cache.hist[req.params.id] });
});

app.post('/api/rcon', async (req, res) => {
  const { id, command } = req.body || {};
  const ark = arks[id];
  if (!ark) return res.status(400).json({ ok: false, error: 'instance not found' });
  if (!command || typeof command !== 'string') return res.status(400).json({ ok: false, error: 'command required' });
  try { const r = await ark.rcon(command); logAudit('admin', command, ark.name, /doexit|destroy|kick|ban/i.test(command)); res.json(r); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/instance/:id/action', async (req, res) => {
  const ark = arks[req.params.id];
  const action = (req.body || {}).action;
  try {
    if (['start', 'stop', 'restart'].includes(action)) {
      if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
      logAudit('admin', action, ark.name, action !== 'start');
      return res.json(await ark.serviceAction(action));
    }
    if (['vmreboot', 'vmshutdown', 'vmstart', 'vmstop'].includes(action)) {
      const map = { vmstart: 'start', vmstop: 'stop', vmreboot: 'reboot', vmshutdown: 'shutdown' };
      await pmx.vmPower(map[action]); logAudit('admin', 'VM ' + map[action], 'the ARK VM', true);
      return res.json({ ok: true, output: `VM ${map[action]} requested` });
    }
    if (action === 'save' && ark) { logAudit('admin', 'SaveWorld', ark.name); return res.json(await ark.rcon('SaveWorld')); }
    res.status(400).json({ ok: false, error: 'unknown action' });
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/instance/:id/settings', async (req, res) => {
  const ark = arks[req.params.id];
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  const { sessionName, adminPassword, serverPassword } = req.body || {};
  try {
    const r = await ark.updateSettings({ sessionName, adminPassword, serverPassword });
    if (r.ok) logAudit('admin', `Update world settings (${r.changed.join(', ')})`, ark.name, true);
    res.json(r);
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

// Per-world compute allocation (CPU cores + RAM ceiling, enforced via systemd cgroup).
function vmBudget() {
  const gb = cache.host && cache.host.memTotal;   // decimal GB (maxmem/1e9)
  return {
    vmCores: Math.max(1, Math.round((cache.host && cache.host.cpus) || config.ark.coresTotal || 4)),
    // Enforcement uses 'G' (=GiB), so express the ceiling in GiB too, else a 16 GiB VM reports 17.
    vmRam: gb ? Math.max(1, Math.floor((gb * 1e9) / 1073741824)) : (config.ark.ramAllocGB || 16),
  };
}
app.get('/api/instance/:id/resources', async (req, res) => {
  const ark = arks[req.params.id];
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  try { const r = await ark.resources(); res.json({ ok: true, ...r, ...vmBudget() }); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});
app.post('/api/instance/:id/resources', async (req, res) => {
  const ark = arks[req.params.id];
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  const { cores, ramGB } = req.body || {};
  try {
    const r = await ark.setResources({ cores, ramGB, ...vmBudget() });
    if (r.ok) { logAudit('admin', `set compute ${r.cores} vCPU / ${r.ramGB} GB`, ark.name, true); if (cache._rsc) cache._rsc[req.params.id] = undefined; }
    res.json(r);
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.get('/api/console/:id', async (req, res) => {
  const ark = arks[req.params.id];
  if (!ark) return res.json({ ok: false, error: 'not found', lines: [] });
  try { res.json(await ark.logTail(parseInt(req.query.n || '200', 10))); }
  catch (e) { res.status(500).json({ ok: false, error: e.message, lines: [] }); }
});

app.get('/api/config/:id', async (req, res) => {
  const ark = arks[req.params.id];
  if (!ark) return res.json({ ok: false, error: 'not found', ini: '' });
  try { res.json(await ark.readConfig(req.query.file === 'game' ? 'game' : 'gus')); }
  catch (e) { res.status(500).json({ ok: false, error: e.message, ini: '' }); }
});

app.post('/api/config/:id/set', async (req, res) => {
  const ark = arks[req.params.id];
  const { key, value, file } = req.body || {};
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  try { const r = await ark.setConfigKey(key, value, file === 'game' ? 'game' : 'gus'); logAudit('admin', `set ${key}=${value}`, ark.name); res.json(r); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/config/:id/raw', async (req, res) => {
  const ark = arks[req.params.id];
  const { file, content } = req.body || {};
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  if (content == null) return res.status(400).json({ ok: false, error: 'content required' });
  try {
    const r = await ark.writeConfigRaw(file === 'game' ? 'game' : 'gus', content);
    if (r.ok) logAudit('admin', `Edit ${file === 'game' ? 'Game.ini' : 'GameUserSettings.ini'}`, ark.name);
    res.json(r);
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/config/:id/platforms', async (req, res) => {
  const ark = arks[req.params.id];
  const list = (req.body && req.body.list) || [];
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  try { const r = await ark.setPlatforms(list); logAudit('admin', `platforms ${r.platform || (Array.isArray(list) ? list.join('+') : '')}`, ark.name); res.json(r); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.get('/api/config-catalog', (_req, res) => res.json({ ok: true, catalog }));

app.get('/api/backups/:id', async (req, res) => {
  const ark = arks[req.params.id];
  if (!ark) return res.json({ ok: true, backups: [] });
  try { res.json(await ark.backupsList()); }
  catch (e) { res.status(500).json({ ok: false, error: e.message, backups: [] }); }
});

app.post('/api/backups/:id/create', async (req, res) => {
  const ark = arks[req.params.id];
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  try { const r = await ark.createBackup(); logAudit('admin', 'Backup snapshot', ark.name); res.json(r); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.delete('/api/backups/:id', async (req, res) => {
  const ark = arks[req.params.id];
  const name = (req.body || {}).name;
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  if (!name) return res.status(400).json({ ok: false, error: 'snapshot name required' });
  try { const r = await ark.deleteBackup(name); if (r.ok) logAudit('admin', `Delete snapshot ${name}`, ark.name, true); res.json(r); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/backups/:id/restore', async (req, res) => {
  const ark = arks[req.params.id];
  const name = (req.body || {}).name;
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  if (!name) return res.status(400).json({ ok: false, error: 'snapshot name required' });
  try { logAudit('admin', `Restore snapshot ${name}`, ark.name, true); res.json(await ark.restoreBackup(name)); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.get('/api/schedule/:id', async (req, res) => {
  const ark = arks[req.params.id];
  if (!ark) return res.json({ ok: true, jobs: [] });
  try { res.json(await ark.schedule()); }
  catch (e) { res.status(500).json({ ok: false, error: e.message, jobs: [] }); }
});

app.post('/api/schedule/:id', async (req, res) => {
  const ark = arks[req.params.id];
  const { taskType, cron, message, key, value, file, restart, endCron, revertValue, rates } = req.body || {};
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  try { const r = await ark.addSchedule(taskType, cron, message, { key, value, file, restart, endCron, revertValue, rates }); if (r.ok) logAudit('admin', `Add schedule ${taskType} (${cron})`, ark.name); res.json(r); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.delete('/api/schedule/:id', async (req, res) => {
  const ark = arks[req.params.id];
  const { match } = req.body || {};
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  try { const r = await ark.deleteSchedule(match); if (r.ok) logAudit('admin', `Remove schedule`, ark.name, true); res.json(r); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.get('/api/update/:id', async (req, res) => {
  const ark = arks[req.params.id];
  if (!ark) return res.json({ ok: false, error: 'not found' });
  try { res.json(await ark.updateCheck()); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/update/:id/apply', async (req, res) => {
  const ark = arks[req.params.id];
  if (!ark) return res.status(400).json({ ok: false, error: 'not found' });
  try { logAudit('admin', 'Apply update + restart', ark.name, true); res.json(await ark.applyUpdate()); }
  catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.get('/api/audit', (_req, res) => res.json({ ok: true, audit }));

// ---- maps: available list + create ----
app.get('/api/maps/available', (_req, res) => {
  const existing = new Set(discovered.map((m) => m.display.toLowerCase()));
  const available = Object.entries(config.officialMaps)
    .filter(([disp]) => !existing.has(disp.toLowerCase()))
    .map(([display, internal]) => ({ display, internal }));
  res.json({ ok: true, available, ports: suggestPorts(discovered), existing: discovered.map((m) => m.display) });
});

app.post('/api/maps', async (req, res) => {
  const o = req.body || {};
  if (!o.display || !o.internal) return res.status(400).json({ ok: false, error: 'map name required' });
  try {
    const r = await createMap(pmx, config.ark, o);
    if (r.ok) {
      logAudit('admin', `Created map ${o.display}`, o.display);
      // Auto-open the internet-facing game port on the UDM (RCON/query stay LAN-only).
      if (udm && o.gamePort) {
        try {
          await udm.upsertForward({ name: fwdName(o.display), wanPort: parseInt(o.gamePort, 10), fwdIp: config.unifi.arkVmIp, proto: config.unifi.proto });
          logAudit('admin', `Opened WAN ${o.gamePort}/${config.unifi.proto} → ${config.unifi.arkVmIp}`, o.display);
          r.forward = { ok: true, wanPort: parseInt(o.gamePort, 10) };
        } catch (e) { r.forward = { ok: false, error: e.message }; console.error('[unifi create]', e.message); }
      }
      await syncMaps();
    }
    res.json(r);
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.delete('/api/maps/:display', async (req, res) => {
  try {
    const r = await deleteMap(pmx, config.ark, req.params.display);
    if (r.ok) {
      logAudit('admin', `Deleted map ${req.params.display}`, req.params.display, true);
      // Remove the map's WAN port-forward so nothing stays exposed after deletion.
      if (udm) {
        try { const d = await udm.deleteForwardByName(fwdName(req.params.display)); if (d.removed) logAudit('admin', `Closed WAN forward (${d.removed})`, req.params.display, true); r.forward = { ok: true, removed: d.removed }; }
        catch (e) { r.forward = { ok: false, error: e.message }; console.error('[unifi delete]', e.message); }
      }
      await syncMaps();
    }
    res.json(r);
  } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

// ---------- static frontend ----------
app.use(express.static(path.join(__dirname, '..', 'frontend'), {
  etag: true,
  setHeaders(res, filePath) {
    if (/\/vendor\//.test(filePath)) res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    else res.setHeader('Cache-Control', 'no-cache');
  },
}));
app.get('*', (_req, res) => { res.setHeader('Cache-Control', 'no-cache'); res.sendFile(path.join(__dirname, '..', 'frontend', 'index.html')); });

app.listen(config.port, () => console.log(`ARK dashboard on :${config.port} → VM ${config.proxmox.vmid} @ ${config.proxmox.node}`));
