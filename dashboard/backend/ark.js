// ark.js — ARK: Survival Ascended operations, driven live off the VM.
// Maps are discovered from maps/*/map.conf (nothing hardcoded). Everything runs
// inside the VM via Proxmox guest-exec, so nothing is installed on the game VM.

// Inline Source-RCON client (password over stdin, never in argv). Handles ARK's
// two-packet auth handshake.
const RCON_PY = `
import sys, socket, struct
data = sys.stdin.read().split("\\n")
pw = data[0]
cmd = "\\n".join(data[1:]).strip("\\n")
HOST, PORT = "127.0.0.1", int(sys.argv[1])
def pkt(pid, ptype, body):
    payload = struct.pack("<ii", pid, ptype) + body.encode("utf-8") + b"\\x00\\x00"
    return struct.pack("<i", len(payload)) + payload
def recv(sock):
    raw = b""
    while len(raw) < 4:
        c = sock.recv(4 - len(raw))
        if not c: raise IOError("closed")
        raw += c
    ln = struct.unpack("<i", raw)[0]
    buf = b""
    while len(buf) < ln:
        c = sock.recv(ln - len(buf))
        if not c: raise IOError("closed")
        buf += c
    pid, ptype = struct.unpack("<ii", buf[:8])
    return pid, ptype, buf[8:-2].decode("utf-8", "replace")
try:
    s = socket.create_connection((HOST, PORT), timeout=8)
    s.settimeout(8)
    s.sendall(pkt(1, 3, pw))
    rid, rtype, _ = recv(s)
    if rtype == 0:
        rid, rtype, _ = recv(s)
    if rid == -1 or rtype != 2:
        print("__RCON_AUTH_FAIL__"); sys.exit(2)
    s.sendall(pkt(7, 2, cmd))
    out = []
    _, _, resp = recv(s); out.append(resp)
    s.settimeout(1.0)
    try:
        while True:
            _, _, more = recv(s)
            if more: out.append(more)
    except Exception:
        pass
    sys.stdout.write("".join(out))
    s.close()
except Exception as e:
    sys.stderr.write("__RCON_ERR__ " + str(e)); sys.exit(3)
`;

function shq(s) { return `'${String(s).replace(/'/g, `'\\''`)}'`; }

// Proxmox' guest-exec input-data can't carry wide (non-ASCII) characters — its
// Perl base64 step throws "Wide character". ARK config is ASCII, so transliterate
// common typographic chars and drop anything else outside ASCII.
function asciiSafe(s) {
  return String(s)
    .replace(/[‒-―−]/g, '-')       // dashes → hyphen
    .replace(/[‘’‛]/g, "'")         // smart single quotes
    .replace(/[“”]/g, '"')               // smart double quotes
    .replace(/[…]/g, '...')
    .replace(/[^\x09\x0A\x0D\x20-\x7E]/g, '');     // strip remaining non-ASCII
}

// Redact secrets ARK writes into its own log / config.
function redactSecrets(text) {
  return String(text).replace(
    /((?:Server)?(?:Admin)?Password|RCONPassword|ServerAdminPassword)=([^\s?"&]+)/gi,
    (_m, k) => `${k}=••••••`
  );
}

// Parse a simple KEY=VALUE conf blob into an object (last value wins).
function parseConf(text) {
  const o = {};
  String(text).split('\n').forEach((l) => {
    const m = l.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m) o[m[1]] = m[2];
  });
  return o;
}

const managerDir = (cfg) => cfg.manager.replace(/\/[^/]+$/, '');

class ArkInstance {
  constructor(pmx, arkCfg, map) {
    this.pmx = pmx;
    this.arkCfg = arkCfg;
    this.user = arkCfg.user;
    this.manager = arkCfg.manager;
    this.dir = managerDir(arkCfg);
    // map = { display, internal, saveDir, gamePort, queryPort, rconPort, maxPlayers, ... }
    this.id = map.display.toLowerCase();
    this.display = map.display;
    this.name = map.display;
    this.map = map.internal || map.display;
    this.saveDir = map.saveDir || map.display;
    this.service = `${arkCfg.servicePrefix}${map.display.toLowerCase()}`;
    this.rconPort = parseInt(map.rconPort || 27020, 10);
    this.gamePort = map.gamePort; this.queryPort = map.queryPort;
    this.maxPlayers = parseInt(map.maxPlayers || 70, 10);
    this.ramAlloc = arkCfg.ramAllocGB;
    this._paths = null; this._pw = null; this._cfg = null; this._cfgAt = 0;
  }

  mapConfPath() { return `${this.dir}/maps/${this.display}/map.conf`; }
  mapDir() { return `${this.dir}/maps/${this.display}`; }

  async _rconPw() {
    if (this.arkCfg.rconPasswordOverride) return this.arkCfg.rconPasswordOverride;
    if (this._pw != null) return this._pw;
    const defConf = `${this.dir}/config/server-defaults.conf`;
    const r = await this.pmx.guestShell(
      `V=$(grep -E '^AdminPassword=' ${shq(this.mapConfPath())} 2>/dev/null | tail -1 | cut -d= -f2-); ` +
      `[ -z "$V" ] && V=$(grep -E '^DefaultAdminPassword=' ${shq(defConf)} 2>/dev/null | tail -1 | cut -d= -f2-); ` +
      `printf 'PW<%s>PW' "$V"`,
      { asUser: this.user, timeoutMs: 15000 }
    );
    const m = (r.out || '').match(/PW<([\s\S]*)>PW/);
    this._pw = m ? m[1].replace(/[\r\n]+$/, '') : '';
    return this._pw;
  }

  async rcon(command, _retried) {
    const pw = await this._rconPw();
    if (!pw) return { ok: false, error: 'admin password not found' };
    const r = await this.pmx.guestShell(`python3 -c ${shq(RCON_PY)} ${this.rconPort}`, {
      asUser: this.user, inputData: `${pw}\n${command}`, timeoutMs: 15000,
    });
    const out = (r.out || '').trim(), err = (r.err || '').trim();
    if (out.includes('__RCON_AUTH_FAIL__')) {
      // The admin password may have just been rotated (map.conf changed, then the server
      // restarted). Re-read map.conf once and retry so RCON self-heals without a manual restart.
      if (!_retried && !this.arkCfg.rconPasswordOverride) { this._pw = null; return this.rcon(command, true); }
      return { ok: false, error: 'RCON auth failed (bad admin password)' };
    }
    if (err.includes('__RCON_ERR__') || r.exitcode === 3) return { ok: false, error: err.replace('__RCON_ERR__', '').trim() || 'RCON connection failed' };
    return { ok: true, output: out };
  }

  async status() {
    const r = await this.pmx.guestShell(
      `systemctl is-active ${this.service} 2>/dev/null; echo "---"; ` +
      `systemctl show ${this.service} -p SubState,ExecMainStartTimestamp 2>/dev/null`
    );
    const [active, rest = ''] = (r.out || '').split('---');
    const state = (active || '').trim();
    const props = parseConf(rest);
    let dash = 'stopped';
    if (state === 'active') dash = props.SubState === 'running' ? 'running' : 'starting';
    else if (state === 'activating') dash = 'starting';
    else if (state === 'failed') dash = 'crashed';
    return { state, dash, subState: props.SubState || '', startTs: props.ExecMainStartTimestamp || '' };
  }

  async serviceAction(action) {
    if (!['start', 'stop', 'restart'].includes(action)) throw new Error('bad action');
    const r = await this.pmx.guestShell(`systemctl ${action} ${this.service} 2>&1; echo "exit=$?"`);
    return { ok: /exit=0\b/.test(r.out || ''), output: (r.out || '').trim() };
  }

  // Per-world compute allocation. Each world is its own systemd service, so we cap its
  // share of the shared VM via cgroup properties: CPUQuota (CPU ceiling) + MemoryHigh
  // (soft throttle) / MemoryMax (hard ceiling). Read current caps + live RAM usage.
  async resources() {
    if (!/^ark-[a-z0-9_.-]+$/.test(this.service)) return { ok: false, cores: null, ramGB: null, ramUsedGB: null };
    const r = await this.pmx.guestShell(
      `systemctl show ${this.service} -p CPUQuotaPerSecUSec -p MemoryMax -p MemoryCurrent 2>/dev/null`
    );
    const p = parseConf(r.out || '');
    // CPUQuotaPerSecUSec is a CPU-time span per real second: 1s == 1 core, 500ms == 0.5 core.
    const spanToCores = (v) => {
      if (!v || /infinity/i.test(v)) return null;
      let us = 0, any = false, m; const re = /(\d+)(min|ms|us|s)/g;
      while ((m = re.exec(v))) { any = true; const n = +m[1]; us += m[2] === 'min' ? n * 6e7 : m[2] === 's' ? n * 1e6 : m[2] === 'ms' ? n * 1e3 : n; }
      if (!any) { const n = parseInt(v, 10); if (!isNaN(n)) us = n; else return null; }
      return Math.round((us / 1e6) * 100) / 100;
    };
    const bytesToGB = (v) => (!v || /infinity/i.test(v)) ? null : Math.round((parseInt(v, 10) / 1073741824) * 10) / 10;
    return { ok: r.ok !== false, cores: spanToCores(p.CPUQuotaPerSecUSec), ramGB: bytesToGB(p.MemoryMax), ramUsedGB: bytesToGB(p.MemoryCurrent) };
  }

  // Apply CPU-core cap + RAM ceiling (GB) to this world. Persists (drop-in) and applies live.
  // Clamped to the VM's total so one world can never claim more than the box has.
  async setResources({ cores, ramGB, vmCores = 4, vmRam = 16, force = false }) {
    if (!/^ark-[a-z0-9_.-]+$/.test(this.service)) return { ok: false, error: 'unsafe service name' };
    // Read the world's current caps + live RAM use first. A missing/zero field then keeps its
    // current value (never silently resets to the VM max), and we can refuse an unsafe shrink.
    const cur = await this.resources().catch(() => null);
    const curCores = cur && cur.cores != null ? cur.cores : vmCores;
    const curRam = cur && cur.ramGB != null ? cur.ramGB : vmRam;
    const reqC = Number(cores), reqR = Number(ramGB);
    const c = Math.min(vmCores, Math.max(0.25, Number.isFinite(reqC) && reqC > 0 ? reqC : curCores));
    const r = Math.min(vmRam, Math.max(1, Math.round(Number.isFinite(reqR) && reqR > 0 ? reqR : curRam)));
    // OOM guard: writing MemoryMax below a running world's live RSS makes the cgroup OOM-killer
    // terminate it (ARK memory is mostly non-reclaimable) → crash + lost progress. Refuse unless forced.
    const liveGB = cur ? cur.ramUsedGB : null;
    if (!force && liveGB != null && liveGB > 0.1 && r < liveGB * 1.15) {
      return { ok: false, needsForce: true, liveGB, cores: c, ramGB: r,
        error: `Requested ${r} GB is below this world's live use (${liveGB} GB). Stop the world first or raise the limit.` };
    }
    const quota = Math.round(c * 100) + '%';
    const high = Math.max(256, Math.round(r * 0.9 * 1024)) + 'M';   // soft throttle in MB so 90% is real even for small caps
    const max = r + 'G';
    const res = await this.pmx.guestShell(
      `systemctl set-property ${this.service} CPUQuota=${quota} MemoryHigh=${high} MemoryMax=${max} 2>&1; echo "rc=$?"`
    );
    const ok = /rc=0\b/.test(res.out || '');
    return { ok, cores: c, ramGB: r, quota, memHigh: high, memMax: max, output: (res.out || '').replace(/rc=\d+\s*$/, '').trim() };
  }

  async players() {
    const r = await this.rcon('ListPlayers');
    if (!r.ok) return { ok: false, error: r.error, players: [] };
    const txt = r.output || '';
    if (/no players/i.test(txt)) return { ok: true, players: [] };
    const players = [];
    txt.split('\n').forEach((line) => {
      const m = line.match(/^\s*(\d+)\.\s*(.+?),\s*([0-9a-fx]+)\s*$/i);
      if (m) players.push({ slot: +m[1], name: m[2].trim(), id: m[3] });
    });
    return { ok: true, players };
  }

  async paths() {
    if (this._paths) return this._paths;
    const md = this.mapDir();
    const r = await this.pmx.guestShell(
      `L=$(find ${shq(this.dir)}/server-files -type f -name ShooterGame.log 2>/dev/null | head -1); ` +
      `echo "LOG=$L"; echo "GUS=${md}/GameUserSettings.ini"; echo "GAME=${md}/Game.ini"; echo "BKP=${md}/backups"`,
      { asUser: this.user, timeoutMs: 20000 }
    );
    const p = parseConf(r.out);
    this._paths = { log: p.LOG || '', gus: p.GUS || '', game: p.GAME || '', backups: p.BKP || '' };
    return this._paths;
  }

  async logTail(n = 200) {
    const { log } = await this.paths();
    if (!log) return { ok: false, error: 'server log not found', lines: [] };
    const r = await this.pmx.guestShell(`tail -n ${n} ${shq(log)} 2>/dev/null`, { asUser: this.user });
    return { ok: true, lines: (r.out || '').split('\n').filter(Boolean).map(redactSecrets) };
  }

  async readConfig(which = 'gus') {
    const paths = await this.paths();
    const path = which === 'game' ? paths.game : paths.gus;
    if (!path) return { ok: false, error: 'config file not found', ini: '' };
    const r = await this.pmx.guestShell(`cat ${shq(path)} 2>/dev/null`, { asUser: this.user });
    return { ok: true, path, ini: redactSecrets(r.out || '') };
  }

  // Overwrite a whole config file with edited content. Any line the editor still shows
  // redacted (KEY=••••••) is restored from the real on-disk value, so passwords are never
  // exposed to the UI nor clobbered by a save.
  async writeConfigRaw(which, content) {
    const paths = await this.paths();
    const path = which === 'game' ? paths.game : paths.gus;
    if (!path) return { ok: false, error: 'config file not found' };
    const cur = await this.pmx.guestShell(`cat ${shq(path)} 2>/dev/null`, { asUser: this.user });
    const realVals = {};
    (cur.out || '').split('\n').forEach((l) => { const m = l.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*)$/); if (m) realVals[m[1]] = m[2]; });
    const merged = String(content).split('\n').map((l) => {
      const m = l.match(/^(\s*)([A-Za-z0-9_]+)(\s*=\s*)(.*)$/);
      if (m && /[••]/.test(m[4]) && realVals[m[2]] != null) return m[1] + m[2] + m[3] + realVals[m[2]];
      return l;
    }).join('\n');
    await this.pmx.guestExec(['/bin/sh', '-c', `cat > ${shq(path)}`], { asUser: this.user, inputData: asciiSafe(merged), timeoutMs: 15000 });
    this._cfg = null;
    return { ok: true, path };
  }

  // Write a single key=value under a section in GameUserSettings.ini (or Game.ini).
  async setConfigKey(key, value, file = 'gus') {
    if (!/^[A-Za-z0-9_]+$/.test(key)) return { ok: false, error: 'invalid key' };
    const paths = await this.paths();
    const path = file === 'game' ? paths.game : paths.gus;
    if (!path) return { ok: false, error: 'config file not found' };
    const val = asciiSafe(String(value).replace(/[\r\n]/g, ''));
    // Update in place if present, else append under [ServerSettings] (or [/script/shootergame.shootergamemode] for Game.ini).
    const section = file === 'game' ? '[/script/shootergame.shootergamemode]' : '[ServerSettings]';
    const r = await this.pmx.guestShell(
      `python3 - ${shq(path)} ${shq(key)} ${shq(val)} ${shq(section)} <<'PYEOF'\n` +
      `import sys,re,os\n` +
      `path,key,val,section=sys.argv[1:5]\n` +
      `lines=open(path,encoding='utf-8',errors='replace').read().split('\\n') if os.path.exists(path) else []\n` +
      `done=False\n` +
      `for i,l in enumerate(lines):\n` +
      `    if re.match(r'^\\s*'+re.escape(key)+r'\\s*=', l):\n` +
      `        lines[i]=key+'='+val; done=True; break\n` +
      `if not done:\n` +
      `    try: idx=next(i for i,l in enumerate(lines) if l.strip().lower()==section.lower())\n` +
      `    except StopIteration:\n` +
      `        lines=[section]+lines; idx=0\n` +
      `    lines.insert(idx+1, key+'='+val)\n` +
      `open(path,'w',encoding='utf-8').write('\\n'.join(lines))\n` +
      `print('OK')\n` +
      `PYEOF`,
      { asUser: this.user, timeoutMs: 15000 }
    );
    this._cfg = null; // invalidate cache
    return { ok: /OK/.test(r.out || ''), output: (r.out || r.err || '').trim(), path };
  }

  // Which platforms may join is the real ASA launch arg `-ServerPlatform=PC+XSX+PS5+WINGDK`
  // (tokens: PC=Steam, XSX=Xbox, PS5=PlayStation, WINGDK=Windows Store). No arg / ALL = every
  // platform. It lives in map.conf CustomStartParams, applied on next restart.
  static PLATFORMS = ['PC', 'XSX', 'PS5', 'WINGDK'];

  async readPlatforms() {
    const r = await this.pmx.guestShell(
      `grep -E '^CustomStartParams=' ${shq(this.mapConfPath())} 2>/dev/null | tail -1`,
      { asUser: this.user, timeoutMs: 12000 }
    ).catch(() => ({ out: '' }));
    const m = (r.out || '').match(/-ServerPlatform=([A-Za-z0-9+]+)/i);
    const all = ArkInstance.PLATFORMS;
    if (!m || /^all$/i.test(m[1])) return all.reduce((o, p) => ((o[p] = true), o), {});
    const on = m[1].split('+').map((t) => t.toUpperCase());
    return all.reduce((o, p) => ((o[p] = on.includes(p)), o), {});
  }

  // list = array of allowed tokens (subset of PLATFORMS). Rewrites CustomStartParams.
  async setPlatforms(list) {
    const valid = (Array.isArray(list) ? list : []).map((t) => String(t).toUpperCase()).filter((t) => ArkInstance.PLATFORMS.includes(t));
    const uniq = ArkInstance.PLATFORMS.filter((p) => valid.includes(p)); // canonical order, deduped
    const arg = uniq.length === 0 || uniq.length === ArkInstance.PLATFORMS.length ? 'ALL' : uniq.join('+');
    const path = this.mapConfPath();
    const r = await this.pmx.guestShell(
      `python3 - ${shq(path)} ${shq(arg)} <<'PYEOF'\n` +
      `import sys,os\n` +
      `path=sys.argv[1]; arg=sys.argv[2]\n` +
      `lines=open(path,encoding='utf-8',errors='replace').read().split('\\n') if os.path.exists(path) else []\n` +
      `done=False\n` +
      `for i,l in enumerate(lines):\n` +
      `    if l.startswith('CustomStartParams='):\n` +
      `        toks=[t for t in l.split('=',1)[1].split() if t and t!='-crossplay' and not t.startswith('-ServerPlatform=')]\n` +
      `        toks.append('-ServerPlatform='+arg)\n` +
      `        lines[i]='CustomStartParams='+(' '.join(toks)); done=True; break\n` +
      `if not done:\n` +
      `    lines.append('CustomStartParams=-ServerPlatform='+arg)\n` +
      `open(path,'w',encoding='utf-8').write('\\n'.join(lines))\n` +
      `print('OK')\n` +
      `PYEOF`,
      { asUser: this.user, timeoutMs: 15000 }
    );
    this._cfg = null;
    return { ok: /OK/.test(r.out || ''), output: (r.out || r.err || '').trim(), platform: arg };
  }

  async configSummary() {
    if (this._cfg && Date.now() - this._cfgAt < 60000) return this._cfg;
    const c = await this.readConfig('gus').catch(() => ({ ok: false, ini: '' }));
    const cg = await this.readConfig('game').catch(() => ({ ini: '' }));
    const platforms = await this.readPlatforms().catch(() => ({ PC: true, XSX: true, PS5: true, WINGDK: true }));
    const kv = Object.assign({}, parseConf(cg.ini || ''), parseConf(c.ini || ''));  // GUS wins on conflict
    const lower = {}; for (const k in kv) lower[k.toLowerCase()] = kv[k];
    const num = (k, d) => { const v = parseFloat(lower[k.toLowerCase()]); return isNaN(v) ? d : v; };
    const bool = (k, d) => { const v = lower[k.toLowerCase()]; return v == null ? d : /^true$/i.test(v); };
    const M = (label, key, base, max, file) => { const v = num(key, base); return { k: label, key, file: file || 'gus', v: v + '×', val: v, v2: String(v), base: base + '×', baseNum: base, max, pct: Math.min(100, Math.round(v / max * 100)), hot: v > base }; };
    const multipliers = [
      M('XP', 'XPMultiplier', 1, 10, 'gus'), M('Harvest', 'HarvestAmountMultiplier', 1, 10, 'gus'),
      M('Taming', 'TamingSpeedMultiplier', 1, 10, 'gus'), M('Maturation', 'BabyMatureSpeedMultiplier', 1, 30, 'game'),
      M('Mating interval', 'MatingIntervalMultiplier', 1, 5, 'game'), M('Egg hatch', 'EggHatchSpeedMultiplier', 1, 30, 'game'),
    ];
    const rules = {
      mode: bool('ServerPVE', true) ? 'PvE' : 'PvP',
      difficulty: num('OverrideOfficialDifficulty', num('DifficultyOffset', 1)),
      maxWild: Math.round(num('OverrideOfficialDifficulty', 1) * 30),
      tameLimit: Math.round(num('MaxTamedDinos', 5000)),
      crosshair: bool('ServerCrosshair', true), thirdPerson: bool('AllowThirdPersonPlayer', true),
      flyerCarry: bool('AllowFlyerCarryPvE', true), platforms,
      crossplay: platforms.PC || platforms.XSX || platforms.PS5 || platforms.WINGDK,
    };
    this._cfg = { ok: c.ok, multipliers, rules, sessionName: kv.SessionName || '', all: kv };
    this._cfgAt = Date.now();
    return this._cfg;
  }

  async updateCheck() {
    const mf = `${this.dir}/server-files/steamapps/appmanifest_2430930.acf`;
    const sc = `${this.dir}/steamcmd/steamcmd.sh`;
    const r1 = await this.pmx.guestShell(`grep -aE '"buildid"' ${shq(mf)} 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1`, { asUser: this.user });
    const installed = (r1.out || '').trim().split('\n')[0] || '';
    let latest = '', latestErr = null;
    try {
      const r2 = await this.pmx.guestShell(
        `${shq(sc)} +login anonymous +app_info_update 1 +app_info_print 2430930 +quit 2>/dev/null ` +
        `| tr -d '\\t' | awk '/"public"/{f=1} f&&/"buildid"/{print; exit}' | grep -oE '[0-9]+' | head -1`,
        { asUser: this.user, timeoutMs: 90000 }
      );
      latest = (r2.out || '').trim().split('\n')[0] || '';
    } catch (e) { latestErr = 'SteamCMD query timed out'; }
    return { ok: true, appId: '2430930', installed, latest, latestErr, updateAvailable: !!(installed && latest && installed !== latest) };
  }

  async applyUpdate() {
    await this.rcon('Broadcast Server update starting — saving and restarting shortly').catch(() => {});
    await this.rcon('SaveWorld').catch(() => {});
    const script =
      `systemctl stop ${this.service}; ` +
      `runuser -u ${this.user} -- bash -lc 'cd ${shq(this.dir)} && ./ark-manager.sh update' ; ` +
      `systemctl start ${this.service}`;
    const r = await this.pmx.guestShell(`nohup bash -c ${shq(script)} > /tmp/ark-dashboard-update.log 2>&1 & echo STARTED`, { timeoutMs: 15000 });
    return { ok: /STARTED/.test(r.out || ''), output: (r.out || '').trim() };
  }

  // ark-manager's own `backup` archives Saved/SavedArks/, but ASA writes the live world
  // to Saved/<AltSaveDir>/<Map>_WP/ (e.g. ARK-ex) — so its backups were empty. This helper
  // backs up the REAL save dir (auto-detected from where the .ark files live), excluding
  // ARK's own timestamped rotating .ark backups, and preserves the path so restore fits.
  async ensureBackupHelper() {
    if (this._bkHelper) return `${this.dir}/dashboard-backup.sh`;
    const path = `${this.dir}/dashboard-backup.sh`;
    const body = [
      '#!/bin/bash',
      '# usage: dashboard-backup.sh <MAPDIR> <SERVERDIR> <DISPLAY> [TAG]',
      'MD="$1"; SERVER="$2"; DISP="$3"; TAG="$4"',
      'SAVED="$SERVER/ShooterGame/Saved"',
      'BK="$MD/backups"; mkdir -p "$BK"',
      "SR=$(find \"$SAVED\" -maxdepth 3 -name '*.ark' -printf '%P\\n' 2>/dev/null | head -1 | cut -d/ -f1)",
      '[ -z "$SR" ] && SR=SavedArks',
      'TS=$(date +%Y%m%d_%H%M%S)',
      'F="$BK/${DISP}${TAG:+_$TAG}_$TS.tar.gz"',
      "tar -czf \"$F\" -C \"$SAVED\" --exclude='*_[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]_*.ark' \"$SR\" 2>&1",
      'echo "OK saved=$SR size=$(du -h "$F" 2>/dev/null | cut -f1)"',
      '',
    ].join('\n');
    await this.pmx.guestExec(['/bin/sh', '-c', `cat > ${shq(path)} && chmod +x ${shq(path)}`], { asUser: this.user, inputData: asciiSafe(body), timeoutMs: 15000 });
    this._bkHelper = true;
    return path;
  }

  async createBackup() {
    const helper = await this.ensureBackupHelper();
    const r = await this.pmx.guestShell(
      `runuser -u ${this.user} -- bash ${shq(helper)} ${shq(this.mapDir())} ${shq(this.dir + '/server-files')} ${shq(this.display)} 2>&1 | tail -3`,
      { timeoutMs: 120000 }
    );
    const out = (r.out || '').trim();
    return { ok: /OK saved=/.test(out), output: out };
  }

  // Restore: stop → safety-snapshot of the current save → extract the chosen backup back
  // into Saved/ (so <AltSaveDir>/<Map>_WP lands where the server actually reads) → start.
  async restoreBackup(name) {
    if (!/^[\w.\- ]+\.tar\.gz$/.test(name)) return { ok: false, error: 'invalid snapshot name' };
    const bk = `${this.mapDir()}/backups`;
    const saved = `${this.dir}/server-files/ShooterGame/Saved`;
    const excl = "--exclude='*_[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]_*.ark'";
    const script =
      `systemctl stop ${this.service}; sleep 2; ` +
      `SAVED=${shq(saved)}; BK=${shq(bk)}; ` +
      `SR=$(find "$SAVED" -maxdepth 3 -name '*.ark' -printf '%P\\n' 2>/dev/null | head -1 | cut -d/ -f1); ` +
      `[ -n "$SR" ] && runuser -u ${this.user} -- tar -czf "$BK/${this.display}_pre-restore_$(date +%Y%m%d_%H%M%S).tar.gz" -C "$SAVED" ${excl} "$SR" 2>/dev/null; ` +
      `runuser -u ${this.user} -- tar -xzf ${shq(bk + '/' + name)} -C "$SAVED" 2>&1 | tail -2; ` +
      `systemctl start ${this.service}`;
    const r = await this.pmx.guestShell(`nohup bash -c ${shq(script)} > /tmp/ark-dashboard-restore.log 2>&1 & echo STARTED`, { timeoutMs: 15000 });
    return { ok: /STARTED/.test(r.out || ''), output: (r.out || '').trim() };
  }

  async backupsList() {
    const { backups } = await this.paths();
    if (!backups) return { ok: true, backups: [] };
    const r = await this.pmx.guestShell(
      `ls -1t ${shq(backups)} 2>/dev/null | head -40 | while read f; do sz=$(du -h ${shq(backups)}/"$f" 2>/dev/null | cut -f1); ts=$(stat -c %y ${shq(backups)}/"$f" 2>/dev/null | cut -d. -f1); echo "$f|$sz|$ts"; done`,
      { asUser: this.user }
    );
    const backupsArr = (r.out || '').split('\n').filter(Boolean).map((l) => {
      const [name, size, when] = l.split('|');
      // trigger: how this snapshot was created — so the UI can explain "backups I didn't make".
      const trigger = /_pre-restore_/i.test(name) ? 'auto'
        : /_scheduled_/i.test(name) ? 'scheduled'
        : /_pre-update_/i.test(name) ? 'update' : 'manual';
      return { name, size: size || '', when: when || '', trigger };
    });
    return { ok: true, dir: backups, backups: backupsArr };
  }

  // Delete a single snapshot. Name is a basename from backupsList() — the regex
  // forbids '/' so no path traversal outside the backups dir.
  async deleteBackup(name) {
    if (!/^[\w.\- ]+\.tar\.gz$/.test(String(name || ''))) return { ok: false, error: 'invalid snapshot name' };
    const { backups } = await this.paths();
    if (!backups) return { ok: false, error: 'backup dir not found' };
    const r = await this.pmx.guestShell(`rm -f ${shq(backups + '/' + name)} && echo DELETED`, { asUser: this.user, timeoutMs: 15000 });
    return { ok: /DELETED/.test(r.out || ''), output: (r.out || '').trim() };
  }

  // Set (or append) a KEY=VALUE line in this map's map.conf (as arkadmin, chmod 600 file).
  async setMapConfKey(key, value) {
    if (!/^[A-Za-z0-9_]+$/.test(key)) return false;
    const path = this.mapConfPath();
    const val = asciiSafe(String(value).replace(/[\r\n]/g, ''));
    const r = await this.pmx.guestShell(
      `python3 - ${shq(path)} ${shq(key)} ${shq(val)} <<'PYEOF'\n` +
      `import sys,os,re\n` +
      `path,key,val=sys.argv[1:4]\n` +
      `lines=open(path,encoding='utf-8',errors='replace').read().split('\\n') if os.path.exists(path) else []\n` +
      `done=False\n` +
      `for i,l in enumerate(lines):\n` +
      `    if re.match(r'^\\s*'+re.escape(key)+r'\\s*=', l):\n` +
      `        lines[i]=key+'='+val; done=True; break\n` +
      `if not done: lines.append(key+'='+val)\n` +
      `open(path,'w',encoding='utf-8').write('\\n'.join(lines))\n` +
      `print('OK')\n` +
      `PYEOF`,
      { asUser: this.user, timeoutMs: 15000 }
    );
    return /OK/.test(r.out || '');
  }

  // Change an existing map's identity: session name + admin/server password.
  // Password changes land in both map.conf (source of truth for RCON) and GUS,
  // and take full effect on the next restart.
  async updateSettings(opts = {}) {
    const changed = [], failed = [];
    const ok = (r) => (typeof r === 'boolean' ? r : !!(r && r.ok));
    if (opts.sessionName != null && String(opts.sessionName).trim() !== '') {
      (ok(await this.setConfigKey('SessionName', opts.sessionName, 'gus')) ? changed : failed).push('name');
    }
    if (opts.adminPassword != null && String(opts.adminPassword) !== '') {
      const a = ok(await this.setMapConfKey('AdminPassword', opts.adminPassword));
      const b = ok(await this.setConfigKey('ServerAdminPassword', opts.adminPassword, 'gus'));
      // Keep serving the cached (old) password so live RCON stays in sync with the still-running
      // server; rcon() re-reads map.conf automatically on the first auth failure after a restart.
      (a && b ? changed : failed).push('adminPassword');
    }
    if (opts.serverPassword != null && String(opts.serverPassword) !== '') {
      const a = ok(await this.setMapConfKey('ServerPassword', opts.serverPassword));
      const b = ok(await this.setConfigKey('ServerPassword', opts.serverPassword, 'gus'));
      (a && b ? changed : failed).push('serverPassword');
    }
    this._cfg = null;
    if (changed.length === 0 && failed.length === 0) return { ok: false, error: 'nothing to change', changed: [] };
    if (failed.length) return { ok: false, error: 'failed to write: ' + failed.join(', '), changed, failed };
    return { ok: true, changed, note: 'applies on next restart' };
  }

  async schedule() {
    const r = await this.pmx.guestShell(`crontab -l 2>/dev/null | grep -vE '^\\s*#' | grep -iE 'ark-manager|ark|healthcheck' | head -30`, { asUser: this.user });
    const jobs = (r.out || '').split('\n').filter(Boolean).map((line) => {
      const m = line.match(/^(\S+\s+\S+\s+\S+\s+\S+\s+\S+)\s+(.*)$/);
      const cron = m ? m[1] : '';
      const cmd = m ? m[2] : line;
      let type = 'task';
      if (/dashboard-set-rate/i.test(cmd)) type = 'multiplier';
      else if (/backup/i.test(cmd)) type = 'backup';
      else if (/restart/i.test(cmd)) type = 'restart';
      else if (/healthcheck/i.test(cmd)) type = 'healthcheck';
      else if (/broadcast/i.test(cmd)) type = 'broadcast';
      else if (/rcon/i.test(cmd)) type = 'rcon';
      return { cron, cmd: cmd.replace(/\s*>.*$/, '').slice(0, 80), type };
    });
    return { ok: true, jobs };
  }

  // Write (once) a small helper the cron jobs use to set a rate in the .ini on the server.
  // Sent over stdin so the inner python heredoc is plain file content, not a nested heredoc.
  async ensureRateHelper() {
    if (this._rateHelper) return;
    const path = `${this.dir}/dashboard-set-rate.sh`;
    const body = [
      '#!/bin/bash',
      '# usage: dashboard-set-rate.sh <KEY> <VALUE> <gus|game> <MAPDIR>',
      'KEY="$1"; VAL="$2"; F="$3"; MD="$4"',
      'if [ "$F" = "game" ]; then P="$MD/Game.ini"; SEC="[/script/shootergame.shootergamemode]"; else P="$MD/GameUserSettings.ini"; SEC="[ServerSettings]"; fi',
      'python3 - "$P" "$KEY" "$VAL" "$SEC" <<\'PYEOF\'',
      'import sys,re,os',
      'path,key,val,section=sys.argv[1:5]',
      "lines=open(path,encoding='utf-8',errors='replace').read().split('\\n') if os.path.exists(path) else []",
      'done=False',
      'for i,l in enumerate(lines):',
      "    if re.match(r'^\\s*'+re.escape(key)+r'\\s*=', l):",
      "        lines[i]=key+'='+val; done=True; break",
      'if not done:',
      '    try: idx=next(i for i,l in enumerate(lines) if l.strip().lower()==section.lower())',
      '    except StopIteration:',
      '        lines=[section]+lines; idx=0',
      "    lines.insert(idx+1, key+'='+val)",
      "open(path,'w',encoding='utf-8').write('\\n'.join(lines))",
      "print('OK')",
      'PYEOF',
      '',
    ].join('\n');
    await this.pmx.guestExec(['/bin/sh', '-c', `cat > ${shq(path)} && chmod +x ${shq(path)}`], { asUser: this.user, inputData: asciiSafe(body), timeoutMs: 15000 });
    this._rateHelper = true;
  }

  // Add a scheduled task to arkadmin's crontab (real cron).
  // extra (taskType 'multiplier'): { rates:[{key,value,file,revertValue}], restart, endCron }
  // (or legacy single { key, value, file, revertValue }). A rate event writes TWO cron
  // lines: start (all rates boosted) and end (all rates reverted).
  async addSchedule(taskType, cron, message, extra = {}) {
    const okCron = (c) => /^[\d*/,\- ]+$/.test(String(c).trim()) && String(c).trim().split(/\s+/).length === 5;
    const clean = (m) => asciiSafe(String(m || 'Scheduled announcement').replace(/["\r\n]/g, '')).slice(0, 120);
    const msg = clean(message);
    if (!okCron(cron)) return { ok: false, error: 'invalid cron (need 5 fields)' };
    const lines = [];
    if (taskType === 'multiplier') {
      // Accept a list of rates, or fall back to the legacy single-rate fields.
      const raw = (Array.isArray(extra.rates) && extra.rates.length)
        ? extra.rates
        : [{ key: extra.key, value: extra.value, file: extra.file, revertValue: extra.revertValue }];
      const rates = [];
      for (const r of raw) {
        const key = String(r.key || '');
        const file = r.file === 'game' ? 'game' : 'gus';
        const val = String(r.value != null ? r.value : '');
        const rev = String(r.revertValue != null ? r.revertValue : '1.0');
        if (!/^[A-Za-z0-9_]+$/.test(key)) return { ok: false, error: 'invalid multiplier key: ' + (key || '(empty)') };
        if (!/^-?\d+(\.\d+)?$/.test(val)) return { ok: false, error: 'invalid value for ' + key };
        if (!/^-?\d+(\.\d+)?$/.test(rev)) return { ok: false, error: 'invalid revert value for ' + key };
        rates.push({ key, file, val, rev });
      }
      if (!rates.length) return { ok: false, error: 'no rates given' };
      await this.ensureRateHelper();
      const restart = extra.restart ? ` ; ./ark-manager.sh restart ${this.display}` : '';
      const setCmds = (useRevert) => rates.map((r) => `bash ${this.dir}/dashboard-set-rate.sh ${r.key} ${useRevert ? r.rev : r.val} ${r.file} ${this.mapDir()}`).join(' ; ');
      const mk = (c, m, useRevert) => `${String(c).trim()} cd ${this.dir} && ./ark-manager.sh rcon ${this.display} "Broadcast ${m}" ; ${setCmds(useRevert)}${restart}`;
      lines.push(mk(cron, msg, false));
      if (okCron(extra.endCron)) {
        lines.push(mk(extra.endCron, clean('Event ended — rates back to normal'), true));
      }
    } else if (taskType === 'backup') {
      const helper = await this.ensureBackupHelper();
      lines.push(`${cron.trim()} bash ${helper} ${this.mapDir()} ${this.dir}/server-files ${this.display} scheduled`);
    } else {
      const cmds = {
        restart: `./ark-manager.sh restart ${this.display}`,
        save: `./ark-manager.sh rcon ${this.display} "SaveWorld"`,
        broadcast: `./ark-manager.sh rcon ${this.display} "Broadcast ${msg}"`,
      };
      if (!cmds[taskType]) return { ok: false, error: 'unknown task type' };
      lines.push(`${cron.trim()} cd ${this.dir} && ${cmds[taskType]}`);
    }
    const echoes = lines.map((l) => `echo ${shq(l)}`).join('; ');
    // Add the line(s), then read the crontab back and confirm the job actually landed.
    const verifyFrag = lines[0] ? lines[0].slice(-45) : '';
    const r = await this.pmx.guestShell(
      `( crontab -l 2>/dev/null; ${echoes} ) | crontab - && echo ADDED; ` +
      (verifyFrag ? `crontab -l 2>/dev/null | grep -qF ${shq(verifyFrag)} && echo VERIFIED` : ''),
      { asUser: this.user });
    return { ok: /ADDED/.test(r.out || ''), verified: /VERIFIED/.test(r.out || ''), lines };
  }

  // Remove a cron line by a unique fragment (the command tail).
  async deleteSchedule(match) {
    if (!match || String(match).length < 4) return { ok: false, error: 'bad match' };
    const r = await this.pmx.guestShell(`crontab -l 2>/dev/null | grep -vF ${shq(match)} | crontab - && echo DELETED`, { asUser: this.user });
    return { ok: /DELETED/.test(r.out || '') };
  }
}

// ---- module-level: discover + create maps ----

async function discoverMaps(pmx, arkCfg) {
  const dir = managerDir(arkCfg);
  // For each map dir, print its map.conf prefixed by the dir name.
  const r = await pmx.guestShell(
    `for d in ${shq(dir)}/maps/*/; do n=$(basename "$d"); [ -f "$d/map.conf" ] || continue; ` +
    `echo "===MAP:$n==="; cat "$d/map.conf" 2>/dev/null; done`,
    { asUser: arkCfg.user, timeoutMs: 20000 }
  );
  const maps = [];
  const blocks = (r.out || '').split(/===MAP:(.+?)===/).slice(1);
  for (let i = 0; i < blocks.length; i += 2) {
    const display = blocks[i].trim();
    const conf = parseConf(blocks[i + 1] || '');
    maps.push({
      display,
      internal: conf.MapName || display,
      saveDir: conf.SaveDir || display,
      gamePort: conf.GamePort, queryPort: conf.QueryPort, rconPort: conf.RCONPort,
      maxPlayers: conf.MaxPlayers,
    });
  }
  return maps;
}

// Create a map by writing its files in small, reliable steps (each file's
// content passed over stdin — no nested heredocs, and the admin password never
// appears in a command line).
async function createMap(pmx, arkCfg, opts) {
  const dir = managerDir(arkCfg);
  const { display, internal, gamePort, queryPort, rconPort, maxPlayers, adminPassword, serverPassword = '', sessionName } = opts;
  if (!/^[A-Za-z0-9_]+$/.test(display)) return { ok: false, error: 'invalid display name (letters/numbers/underscore only)' };
  if (!internal) return { ok: false, error: 'internal map name required' };
  if (!/^[A-Za-z0-9_]+$/.test(internal)) return { ok: false, error: 'invalid internal map name (letters/numbers/underscore only)' };
  if (!adminPassword) return { ok: false, error: 'admin password required' };
  // validate numeric inputs — these are interpolated into shell commands (ufw), so they MUST be plain integers
  const gp = Number(gamePort), qp = Number(queryPort), rp = Number(rconPort), mp = Number(maxPlayers);
  for (const [nm, v, lo, hi] of [['gamePort', gp, 1, 65535], ['queryPort', qp, 1, 65535], ['rconPort', rp, 1, 65535], ['maxPlayers', mp, 1, 255]]) {
    if (!Number.isInteger(v) || v < lo || v > hi) return { ok: false, error: `invalid ${nm}` };
  }
  const u = arkCfg.user;
  const md = `${dir}/maps/${display}`;
  const sess = asciiSafe((sessionName || display).replace(/[\r\n"]/g, ''));
  // strip CR/LF: these land in the line-based map.conf/GUS; a newline would inject
  // extra KEY=VALUE lines that ark-manager.sh reads + feeds into the launch (delayed RCE)
  const apw = asciiSafe(adminPassword).replace(/[\r\n]/g, ''), spw = asciiSafe(serverPassword).replace(/[\r\n]/g, '');

  // exists check
  const chk = await pmx.guestShell(`[ -d ${shq(md)} ] && echo EXISTS || echo OK`, { asUser: u });
  if (/EXISTS/.test(chk.out || '')) return { ok: false, error: 'map already exists' };

  // helper: write a file with (ASCII-safe) content supplied over stdin
  const writeFile = (path, content) => pmx.guestExec(['/bin/sh', '-c', `cat > ${shq(path)}`], { asUser: u, inputData: asciiSafe(content), timeoutMs: 15000 });

  await pmx.guestShell(`mkdir -p ${shq(md)}/backups`, { asUser: u });

  const mapConf =
    `MapName=${internal}\nDisplayName=${display}\nSaveDir=${display}\n` +
    `GamePort=${gamePort}\nQueryPort=${queryPort}\nRCONPort=${rconPort}\nMaxPlayers=${maxPlayers}\n` +
    `AdminPassword=${apw}\nServerPassword=${spw}\n` +
    `CustomStartParams=-NoBattlEye -crossplay -NoHangDetection\nClusterID=\nBatchEnabled=true\n`;
  await writeFile(`${md}/map.conf`, mapConf);
  await pmx.guestShell(`chmod 600 ${shq(md)}/map.conf`, { asUser: u });
  await writeFile(`${md}/mods.conf`, `# Mod configuration for ${display}\n# Format: id|name|enabled\n`);
  await writeFile(`${md}/Game.ini`, '');

  // GUS: read an existing map's GUS as a template, substitute in Node, write it.
  const srcRead = await pmx.guestShell(`cat "$(ls ${shq(dir)}/maps/*/GameUserSettings.ini 2>/dev/null | head -1)" 2>/dev/null`, { asUser: u, timeoutMs: 15000 });
  let gus = srcRead.out || '[ServerSettings]\nRCONEnabled=True\n';
  const sets = { SessionName: sess, ServerAdminPassword: apw, ServerPassword: spw, RCONPort: String(rconPort), MaxPlayers: String(maxPlayers), RCONEnabled: 'True' };
  const seen = {};
  gus = gus.split('\n').map((l) => {
    const m = l.match(/^\s*([A-Za-z0-9_]+)\s*=/);
    if (m && sets[m[1]] != null) { seen[m[1]] = 1; return `${m[1]}=${sets[m[1]]}`; }
    return l;
  }).join('\n');
  const lines = gus.split('\n');
  let idx = lines.findIndex((l) => l.trim().toLowerCase() === '[serversettings]');
  if (idx < 0) { lines.unshift('[ServerSettings]'); idx = 0; }
  for (const k of Object.keys(sets)) if (!seen[k]) lines.splice(idx + 1, 0, `${k}=${sets[k]}`);
  await writeFile(`${md}/GameUserSettings.ini`, lines.join('\n'));

  // maps.conf entry
  await pmx.guestShell(`MC=${shq(dir)}/config/maps.conf; grep -q "^${display}|" "$MC" 2>/dev/null || echo "${display}|${internal}|enabled" >> "$MC"`, { asUser: u });

  // systemd service (needs root) + firewall
  const svc = `ark-${display.toLowerCase()}.service`;
  const svcBody =
    `[Unit]\nDescription=ARK ASA Server - ${display}\nAfter=network-online.target\nWants=network-online.target\n\n` +
    `[Service]\nType=forking\nUser=${arkCfg.user}\nWorkingDirectory=${dir}\n` +
    `Environment=PROTON_LOG=1\nEnvironment=PROTON_LOG_DIR=/home/${arkCfg.user}\n` +
    `ExecStart=${dir}/ark-manager.sh start ${display}\nExecStop=${dir}/ark-manager.sh stop ${display}\n` +
    `Restart=on-failure\nRestartSec=30\nTimeoutStartSec=300\nTimeoutStopSec=180\nMemoryAccounting=true\nCPUAccounting=true\n\n` +
    `[Install]\nWantedBy=multi-user.target\n`;
  // write the unit file over stdin (root), then reload/enable + open firewall
  await pmx.guestExec(['/bin/sh', '-c', `cat > /etc/systemd/system/${svc}`], { inputData: svcBody, timeoutMs: 15000 });
  const rs = await pmx.guestShell(
    `systemctl daemon-reload; systemctl enable ${svc} 2>/dev/null; ` +
    `command -v ufw >/dev/null && { ufw allow ${gp}/udp; ufw allow ${qp}/udp; ufw allow ${rp}/tcp; } 2>/dev/null; ` +
    `echo SVCOK`,
    { timeoutMs: 20000 }
  );
  return { ok: /SVCOK/.test(rs.out || ''), display, service: svc, output: (rs.out || '').trim() };
}

// Delete a map: stop+disable service, remove unit, map dir, and maps.conf entry.
async function deleteMap(pmx, arkCfg, display) {
  if (!/^[A-Za-z0-9_]+$/.test(display)) return { ok: false, error: 'invalid map name' };
  const dir = managerDir(arkCfg);
  const svc = `ark-${display.toLowerCase()}.service`;
  const md = `${dir}/maps/${display}`;
  const r = await pmx.guestShell(
    `systemctl stop ${svc} 2>/dev/null; systemctl disable ${svc} 2>/dev/null; ` +
    `rm -f /etc/systemd/system/${svc}; systemctl daemon-reload; ` +
    // Close this map's firewall ports before removing its config (read ports from map.conf while
    // it still exists), so deleting a world leaves no orphan ufw rules.
    `MCF=${shq(md)}/map.conf; if [ -f "$MCF" ]; then ` +
    `GP=$(grep -E '^GamePort=' "$MCF" | tail -1 | cut -d= -f2); ` +
    `QP=$(grep -E '^QueryPort=' "$MCF" | tail -1 | cut -d= -f2); ` +
    `RP=$(grep -E '^RCONPort=' "$MCF" | tail -1 | cut -d= -f2); ` +
    `[ -n "$GP" ] && ufw --force delete allow "$GP"/udp 2>/dev/null; ` +
    `[ -n "$QP" ] && ufw --force delete allow "$QP"/udp 2>/dev/null; ` +
    `[ -n "$RP" ] && ufw --force delete allow "$RP"/tcp 2>/dev/null; fi; ` +
    `runuser -u ${arkCfg.user} -- rm -rf ${shq(md)}; ` +
    `MC=${shq(dir)}/config/maps.conf; [ -f "$MC" ] && grep -v "^${display}|" "$MC" > "$MC.tmp" && mv "$MC.tmp" "$MC"; ` +
    `echo DELETED`,
    { timeoutMs: 20000 }
  );
  return { ok: /DELETED/.test(r.out || ''), output: (r.out || '').trim() };
}

// Suggest the next free ports given existing maps.
function suggestPorts(maps) {
  let g = 7777, q = 27015, r = 27020;
  for (const m of maps) {
    g = Math.max(g, (parseInt(m.gamePort, 10) || 0));
    q = Math.max(q, (parseInt(m.queryPort, 10) || 0));
    r = Math.max(r, (parseInt(m.rconPort, 10) || 0));
  }
  return maps.length ? { gamePort: g + 2, queryPort: q + 1, rconPort: r + 1 } : { gamePort: 7777, queryPort: 27015, rconPort: 27020 };
}

module.exports = { ArkInstance, discoverMaps, createMap, deleteMap, suggestPorts };
