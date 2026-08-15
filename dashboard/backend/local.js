// local.js — run the ARK manager on *this* machine instead of through Proxmox.
//
// The dashboard was built for a homelab setup where the game server lives in a
// Proxmox VM and every command travels over the qemu-guest-agent. That makes it
// unusable for anyone who just installed ARK on a plain Ubuntu box.
//
// LocalExec exposes the exact same surface as the Proxmox client — guestShell,
// guestExec, vmStatus, rrddata, vmPower — so `ark.js` and `server.js` don't care
// which one they got. Set ARK_EXEC_MODE=local to pick this one.
//
// Differences that callers should know about, and that we're explicit about
// rather than faking:
//   * rrddata has no history to read, so we sample on each poll and keep a small
//     in-memory ring. After a restart the graph starts empty instead of lying.
//   * vmPower would mean rebooting the host itself. That's refused unless the
//     operator opts in with ALLOW_HOST_POWER=1.

const { execFile } = require('child_process');
const fs = require('fs');
const os = require('os');

const RING = 44;   // matches config.histLen

class LocalExec {
  constructor(cfg = {}) {
    this.runAsUser = cfg.runAsUser || null;      // usually 'arkadmin'
    this.allowHostPower = cfg.allowHostPower === true;
    this._hist = [];
    this._lastCpu = null;
    // Serialize like the Proxmox client does: the manager writes config files and
    // talks to RCON, and two of those at once can interleave badly.
    this._q = Promise.resolve();
  }

  // ---- command execution -----------------------------------------------------

  guestExec(args, opts = {}) {
    const run = () => this._exec(args, opts);
    this._q = this._q.then(run, run);
    return this._q;
  }

  _exec(args, { inputData = null, timeoutMs = 20000 } = {}) {
    let [cmd, ...rest] = args;
    // Drop the runuser wrapper the Proxmox path uses; we do the same thing with sudo -u.
    if (cmd === '/usr/sbin/runuser' && rest[0] === '-u') {
      const user = rest[1];
      const dashdash = rest.indexOf('--');
      const real = rest.slice(dashdash + 1);
      return this._spawnAs(user, real, { inputData, timeoutMs });
    }
    return this._spawnAs(this.runAsUser, [cmd, ...rest], { inputData, timeoutMs });
  }

  _spawnAs(user, args, { inputData, timeoutMs }) {
    let cmd = args[0];
    let argv = args.slice(1);
    // Only step down to another user when we're root and it isn't already us.
    if (user && process.getuid && process.getuid() === 0 && user !== 'root') {
      argv = ['-u', user, '-H', '--', cmd, ...argv];
      cmd = 'sudo';
    } else if (user && process.getuid && process.getuid() !== 0) {
      // Not root: sudo will consult sudoers. -n so we fail fast instead of hanging
      // on a password prompt no one can answer.
      argv = ['-n', '-u', user, '-H', '--', cmd, ...argv];
      cmd = 'sudo';
    }

    return new Promise((resolve) => {
      const child = execFile(cmd, argv, {
        timeout: timeoutMs,
        maxBuffer: 8 * 1024 * 1024,
        killSignal: 'SIGKILL',
      }, (err, stdout, stderr) => {
        resolve({
          exitcode: err && typeof err.code === 'number' ? err.code : (err ? 1 : 0),
          out: stdout || '',
          err: stderr || (err && err.killed ? 'command timed out' : (err ? String(err.message) : '')),
        });
      });
      if (inputData != null) {
        child.stdin.on('error', () => {});   // the child may exit before we finish writing
        child.stdin.end(inputData);
      }
    });
  }

  async guestShell(script, { asUser = null, inputData = null, timeoutMs = 20000 } = {}) {
    const user = asUser || this.runAsUser;
    return this._spawnAs(user, ['/bin/bash', '-lc', script], { inputData, timeoutMs });
  }

  // ---- host metrics ----------------------------------------------------------

  _cpuPct() {
    // /proc/stat gives cumulative jiffies; the fraction busy is the delta between polls.
    try {
      const line = fs.readFileSync('/proc/stat', 'utf8').split('\n')[0];
      const v = line.trim().split(/\s+/).slice(1).map(Number);
      const idle = v[3] + (v[4] || 0);
      const total = v.reduce((a, b) => a + b, 0);
      const prev = this._lastCpu;
      this._lastCpu = { idle, total };
      if (!prev) return 0;                       // first sample has nothing to compare to
      const dt = total - prev.total;
      const di = idle - prev.idle;
      return dt > 0 ? Math.max(0, Math.min(1, 1 - di / dt)) : 0;
    } catch { return 0; }
  }

  _mem() {
    try {
      const t = fs.readFileSync('/proc/meminfo', 'utf8');
      const kb = (k) => {
        const m = t.match(new RegExp('^' + k + ':\\s+(\\d+)', 'm'));
        return m ? parseInt(m[1], 10) * 1024 : 0;
      };
      const total = kb('MemTotal');
      const avail = kb('MemAvailable') || (kb('MemFree') + kb('Cached'));
      return { used: Math.max(0, total - avail), total };
    } catch {
      return { used: os.totalmem() - os.freemem(), total: os.totalmem() };
    }
  }

  _net() {
    // Sum every interface except loopback. Cumulative counters — the UI plots deltas.
    try {
      const lines = fs.readFileSync('/proc/net/dev', 'utf8').split('\n').slice(2);
      let rx = 0, tx = 0;
      for (const l of lines) {
        const [iface, rest] = l.split(':');
        if (!rest || iface.trim() === 'lo') continue;
        const f = rest.trim().split(/\s+/).map(Number);
        rx += f[0] || 0; tx += f[8] || 0;
      }
      return { netin: rx, netout: tx };
    } catch { return { netin: 0, netout: 0 }; }
  }

  async vmStatus() {
    const cpu = this._cpuPct();
    const { used, total } = this._mem();
    const { netin, netout } = this._net();

    let disk = 0, maxdisk = 0;
    try {
      const s = fs.statfsSync ? fs.statfsSync('/') : null;
      if (s) { maxdisk = s.blocks * s.bsize; disk = (s.blocks - s.bfree) * s.bsize; }
    } catch { /* statfsSync needs Node 18.15+; the UI falls back to the df-based value */ }

    // Keep the ring topped up so rrddata has something to return.
    this._hist.push({ cpu, mem: used, maxmem: total, netin, netout, time: Math.floor(Date.now() / 1000) });
    if (this._hist.length > RING) this._hist.shift();

    return {
      name: os.hostname(),
      status: 'running',                 // if we're answering, the machine is up
      cpus: os.cpus().length,
      cpu,
      mem: used,
      maxmem: total,
      disk,
      maxdisk,
      uptime: Math.floor(os.uptime()),
    };
  }

  async rrddata() {
    return this._hist.slice();
  }

  async vmPower(action) {
    if (!this.allowHostPower) {
      throw new Error(
        `Refusing to ${action} the machine: in local mode "the VM" is this server itself. ` +
        'Set ALLOW_HOST_POWER=1 in the dashboard env if you really want the panel to be able to do that.'
      );
    }
    const map = { reboot: ['reboot'], shutdown: ['poweroff'] };
    if (!map[action]) throw new Error(`"${action}" is not available in local mode — the host is always running.`);
    return this._spawnAs('root', ['systemctl', ...map[action]], { inputData: null, timeoutMs: 10000 });
  }
}

module.exports = { LocalExec };
