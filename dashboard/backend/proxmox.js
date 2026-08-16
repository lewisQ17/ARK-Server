// proxmox.js — thin Proxmox VE API client for the ARK dashboard.
//
// Two capabilities the dashboard relies on:
//   1. rrddata / status  → host-level VM metrics (CPU/RAM/disk/net/uptime).
//      Read-only, never touches the guest OS.
//   2. guest-exec        → run a command *inside* the ARK VM via the already-running
//      qemu-guest-agent. Installs nothing on the ARK VM; it's how we reach RCON
//      (localhost-only), systemctl and ark-manager.sh.
//
// Auth: root@pam ticket (cached ~110 min, re-auth on 401). A privilege-separated
// API token has no VM perms here, so ticket auth is used. See README security note.

// Proxmox uses a self-signed cert; pin it by SHA-256 fingerprint (PVE_TLS_FINGERPRINT)
// so the root@pam ticket is never sent to an unverified peer. Fails closed unless
// PVE_TLS_INSECURE=1 is set. See pinned-agent.js.
const { buildPinnedAgent } = require('./pinned-agent');

class Proxmox {
  constructor(cfg) {
    this.base = `https://${cfg.host}:${cfg.port || 8006}/api2/json`;
    this.node = cfg.node;              // Proxmox node name, e.g. 'pve'
    this.vmid = cfg.vmid;              // numeric VM id, from PVE_VMID
    this.user = cfg.user || 'root@pam';
    this.password = cfg.password;
    this._ticket = null;
    this._ticketAt = 0;
    this._csrf = null;
    this._agent = buildPinnedAgent({ label: 'proxmox', fingerprint: cfg.tlsFingerprint, allowInsecure: cfg.tlsInsecure });
  }

  async _fetch(path, opts = {}) {
    const res = await fetch(this.base + path, {
      ...opts,
      dispatcher: this._agent,
      headers: { ...(opts.headers || {}) },
    });
    return res;
  }

  async _auth() {
    const body = new URLSearchParams({ username: this.user, password: this.password });
    const res = await this._fetch('/access/ticket', { method: 'POST', body });
    if (!res.ok) throw new Error(`Proxmox auth failed: HTTP ${res.status}`);
    const j = await res.json();
    this._ticket = j.data.ticket;
    this._csrf = j.data.CSRFPreventionToken;
    this._ticketAt = Date.now();
    return this._ticket;
  }

  async _ticketValid() {
    // Proxmox tickets last 2h; refresh after 110 min.
    if (!this._ticket || Date.now() - this._ticketAt > 110 * 60 * 1000) await this._auth();
    return this._ticket;
  }

  // Authenticated request; retries once on 401 with a fresh ticket.
  async api(method, path, form) {
    await this._ticketValid();
    const doReq = async () => {
      const headers = { Cookie: `PVEAuthCookie=${this._ticket}` };
      // Proxmox requires the CSRF token on all mutating requests, with or without a body.
      if (method !== 'GET') headers['CSRFPreventionToken'] = this._csrf;
      let body;
      if (form) body = form instanceof URLSearchParams ? form : new URLSearchParams(form);
      return this._fetch(path, { method, headers, body });
    };
    let res = await doReq();
    if (res.status === 401) { await this._auth(); res = await doReq(); }
    if (!res.ok) {
      const txt = await res.text().catch(() => '');
      throw new Error(`Proxmox ${method} ${path} → HTTP ${res.status} ${txt.slice(0, 200)}`);
    }
    return (await res.json()).data;
  }

  // ---- host-level, read-only ----
  vmStatus() {
    return this.api('GET', `/nodes/${this.node}/qemu/${this.vmid}/status/current`);
  }
  rrddata(timeframe = 'hour') {
    return this.api('GET', `/nodes/${this.node}/qemu/${this.vmid}/rrddata?timeframe=${timeframe}`);
  }
  // action: start | stop | shutdown | reboot | suspend | resume
  vmPower(action) {
    return this.api('POST', `/nodes/${this.node}/qemu/${this.vmid}/status/${action}`);
  }

  // ---- guest-exec: run a command inside the VM via qemu-guest-agent ----
  // Serialized: the qemu-guest-agent handles one exec at a time reliably, so we
  // queue calls to avoid overwhelming (and hanging) the agent.
  guestExec(args, opts = {}) {
    const run = () => this._guestExec(args, opts);
    this._gq = (this._gq || Promise.resolve()).then(run, run);
    return this._gq;
  }
  async _guestExec(args, { inputData = null, timeoutMs = 20000 } = {}) {
    const form = new URLSearchParams();
    for (const a of args) form.append('command', a);   // PVE expects repeated `command`
    if (inputData != null) form.append('input-data', inputData);   // raw; PVE URL-decodes to stdin
    const { pid } = await this.api('POST', `/nodes/${this.node}/qemu/${this.vmid}/agent/exec`, form);

    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const st = await this.api('GET', `/nodes/${this.node}/qemu/${this.vmid}/agent/exec-status?pid=${pid}`);
      if (st.exited) {
        const dec = (d) => (d == null ? '' : (st['out-truncated'] || st['err-truncated'] ? d : d));
        return {
          exitcode: st.exitcode,
          out: dec(st['out-data']) || '',
          err: dec(st['err-data']) || '',
        };
      }
      if (Date.now() > deadline) throw new Error('guest-exec timed out');
      await new Promise((r) => setTimeout(r, 350));
    }
  }

  // Convenience: run a shell snippet inside the guest, optionally as another user.
  async guestShell(script, { asUser = null, inputData = null, timeoutMs = 20000 } = {}) {
    const cmd = asUser
      ? ['/usr/sbin/runuser', '-u', asUser, '--', '/bin/bash', '-lc', script]
      : ['/bin/bash', '-lc', script];
    return this.guestExec(cmd, { inputData, timeoutMs });
  }
}

module.exports = { Proxmox };
