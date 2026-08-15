// auth.js — HTTP Basic auth for the whole dashboard.
//
// Until now there was no auth at all: anything that could reach the port could
// start/stop worlds, run RCON and read the admin password out of map.conf. That
// was survivable while it only listened inside a homelab, but this project is
// meant to be installed by other people, some of whom will forward the port.
//
// Basic auth over a single shared operator account is deliberately modest: no
// sessions, no cookies, no password database, nothing to get subtly wrong. It is
// the credential check the install script generates a password for.
//
// Fail-closed: if DASH_PASS is missing, every request is refused rather than
// silently running wide open.

const crypto = require('crypto');

// Constant-time compare that doesn't leak length through an early return.
function safeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

function basicAuth(cfg) {
  const { user, pass, realm = 'ARK dashboard', enabled = true } = cfg || {};

  return function (req, res, next) {
    if (!enabled) return next();

    if (!pass) {
      res.status(503).type('text/plain').send(
        'Dashboard is not configured: DASH_PASS is empty.\n' +
        'Set DASH_USER and DASH_PASS in the environment (deploy/.env) and restart.\n'
      );
      return;
    }

    const header = req.headers.authorization || '';
    const [scheme, encoded] = header.split(' ');

    if (!encoded || String(scheme).toLowerCase() !== 'basic') {
      res.set('WWW-Authenticate', `Basic realm="${realm}", charset="UTF-8"`);
      res.status(401).type('text/plain').send('Authentication required.\n');
      return;
    }

    let decoded = '';
    try { decoded = Buffer.from(encoded, 'base64').toString('utf8'); } catch { decoded = ''; }
    const idx = decoded.indexOf(':');
    const gotUser = idx >= 0 ? decoded.slice(0, idx) : '';
    const gotPass = idx >= 0 ? decoded.slice(idx + 1) : '';

    // Always check both, so a wrong username costs the same as a wrong password.
    const okUser = safeEqual(gotUser, user);
    const okPass = safeEqual(gotPass, pass);

    if (okUser && okPass) return next();

    res.set('WWW-Authenticate', `Basic realm="${realm}", charset="UTF-8"`);
    res.status(401).type('text/plain').send('Invalid credentials.\n');
  };
}

module.exports = { basicAuth };
