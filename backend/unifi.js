// unifi.js — minimal UniFi/UDM controller client for WAN port-forwards.
// Lets the dashboard auto-open the internet-facing GAME port when a map is created
// and remove it when the map is deleted. RCON/query are never forwarded here.
// Auth: X-API-KEY (UniFi OS integration key). Self-signed cert is trusted for the
// configured controller only (like proxmox.js).

// Self-signed UDM cert: pin it by SHA-256 fingerprint (UNIFI_TLS_FINGERPRINT) so the
// X-API-KEY is never sent to an unverified peer. Fails closed unless UNIFI_TLS_INSECURE=1.
const { buildPinnedAgent } = require('./pinned-agent');

class Unifi {
  constructor(cfg) {
    this.base = `https://${cfg.host}/proxy/network/api/s/${cfg.site || 'default'}`;
    this.apiKey = cfg.apiKey;
    this._agent = buildPinnedAgent({ label: 'unifi', fingerprint: cfg.tlsFingerprint, allowInsecure: cfg.tlsInsecure });
  }

  async _req(method, path, body) {
    const res = await fetch(this.base + path, {
      method,
      dispatcher: this._agent,
      headers: { 'X-API-KEY': this.apiKey, ...(body ? { 'Content-Type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    const txt = await res.text().catch(() => '');
    let j = {};
    try { j = txt ? JSON.parse(txt) : {}; } catch (e) { /* non-JSON */ }
    if (!res.ok || (j.meta && j.meta.rc && j.meta.rc !== 'ok')) {
      throw new Error(`UniFi ${method} ${path} → HTTP ${res.status} ${(j.meta && j.meta.msg) || txt.slice(0, 120)}`);
    }
    return j.data || [];
  }

  listForwards() { return this._req('GET', '/rest/portforward'); }

  // Create-or-replace a WAN→LAN forward identified by name (idempotent — dupes removed first).
  async upsertForward({ name, wanPort, fwdIp, fwdPort, proto = 'udp' }) {
    const dupes = (await this.listForwards()).filter((f) => f.name === name);
    for (const f of dupes) await this._req('DELETE', `/rest/portforward/${f._id}`);
    return this._req('POST', '/rest/portforward', {
      name, enabled: true, pfwd_interface: 'wan', src: 'any', log: false,
      proto, dst_port: String(wanPort), fwd: String(fwdIp), fwd_port: String(fwdPort || wanPort),
    });
  }

  async deleteForwardByName(name) {
    const dupes = (await this.listForwards()).filter((f) => f.name === name);
    for (const f of dupes) await this._req('DELETE', `/rest/portforward/${f._id}`);
    return { ok: true, removed: dupes.length };
  }
}

module.exports = { Unifi };
