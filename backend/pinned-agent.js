// pinned-agent.js — undici Agent that pins a self-signed peer by SHA-256 fingerprint.
//
// Homelab services (Proxmox, UniFi/UDM) use self-signed certs, so CA-chain
// validation can't work. Instead of disabling TLS verification (which lets any
// LAN MITM capture the credential in the request), we disable chain validation
// but require an EXACT peer-cert fingerprint match before the socket is ever
// used — a stronger guarantee than chain validation (pins one specific cert).
//
// Fails CLOSED: if no fingerprint is configured we throw, unless the operator
// explicitly opts into unverified TLS via the matching *_TLS_INSECURE=1 flag.

const { Agent } = require('undici');
const tls = require('tls');

function buildPinnedAgent({ label, fingerprint, allowInsecure }) {
  const want = String(fingerprint || '').replace(/:/g, '').toLowerCase();
  if (!want) {
    if (!allowInsecure) {
      throw new Error(
        `${label}: TLS cert fingerprint required — configure the cert pin ` +
        `(or set the matching *_TLS_INSECURE=1 to explicitly allow unverified TLS). ` +
        `Refusing to send credentials over an unpinned connection.`
      );
    }
    console.warn(`[${label}] *_TLS_INSECURE=1 — TLS peer verification DISABLED; credentials are exposed to LAN MITM.`);
    return new Agent({ connect: { rejectUnauthorized: false } });
  }
  return new Agent({
    connect(opts, callback) {
      // rejectUnauthorized:false here is intentional and safe: the fingerprint
      // check below REPLACES chain validation for the self-signed cert.
      const socket = tls.connect(
        // opts.port is '' for default-port (443) URLs — default it, else tls throws ERR_SOCKET_BAD_PORT
        { ...opts, host: opts.hostname, port: opts.port || 443, servername: opts.servername || opts.hostname, ALPNProtocols: ['http/1.1'], rejectUnauthorized: false },
        () => {
          const got = (socket.getPeerCertificate().fingerprint256 || '').replace(/:/g, '').toLowerCase();
          if (got !== want) { socket.destroy(); callback(new Error(`${label}: TLS fingerprint mismatch (got ${got || 'none'})`)); return; }
          callback(null, socket);
        },
      );
      socket.once('error', callback);
    },
  });
}

module.exports = { buildPinnedAgent };
