'use strict';
const test = require('node:test');
const assert = require('node:assert');
const S = require('../src/shared');

test('norm : 1.0.0 = 1.0 = 1, préfixe v retiré', () => {
  assert.strictEqual(S.norm('v1.2.0'), '1.2');
  assert.strictEqual(S.norm('1.0.0'), '1');
  assert.strictEqual(S.norm(' V2 '), '2');
  assert.strictEqual(S.norm('version'), 'version');
  assert.strictEqual(S.norm(''), null);
});

test('globRegex capture la version, avec ou sans extension', () => {
  const re = S.globRegex('Zelda64Recomp-*-Linux.tar.gz');
  assert.deepStrictEqual(S.firstCapture(re, 'Zelda64Recomp-v1.2.0-Linux.tar.gz'), { matched: true, capture: 'v1.2.0' });
  const bare = S.globRegex('Zelda64Recomp-*-Linux.tar.gz', true);
  assert.strictEqual(S.firstCapture(bare, 'Zelda64Recomp-v1.2.0-Linux').capture, 'v1.2.0');
  assert.strictEqual(S.firstCapture(re, 'autre.zip').matched, false);
});

test('archiveExt reconnaît les doubles extensions et AppImage', () => {
  assert.strictEqual(S.archiveExt('Jeu-1.0.tar.gz'), '.tar.gz');
  assert.strictEqual(S.archiveExt('Jeu.AppImage'), '.appimage');
  assert.strictEqual(S.archiveExt('Jeu.txt'), null);
});

const game = { id: 'g', name: 'Jeu', tag: 'v1.2', version: '1.2', released: '2026-10-01', systems: ['linux', 'windows'],
  assets: { linux: 'Jeu-*-Linux.zip', windows: 'Jeu-*-Windows.zip' } };

test('état : téléchargé ici, à jour ou non', () => {
  assert.strictEqual(S.status(game, 'linux', { g: { linux: { tag: 'v1.2', exists: true } } }, {}), S.STATUS.upToDate);
  assert.strictEqual(S.status(game, 'linux', { g: { linux: { tag: 'v1.1', version: '1.1', exists: true } } }, {}), S.STATUS.outdated);
  // Fichier supprimé depuis : l'état retombe sur l'analyse.
  assert.strictEqual(S.status(game, 'linux', { g: { linux: { tag: 'v1.1', exists: false } } }, {}), S.STATUS.none);
});

test('état : trouvé dans le dossier, par version ou par date', () => {
  const rel = Date.parse('2026-10-01T00:00:00');
  assert.strictEqual(S.status(game, 'linux', {}, { g: { linux: { version: 'v1.2.0', date: 0 } } }), S.STATUS.upToDate);
  assert.strictEqual(S.status(game, 'linux', {}, { g: { linux: { version: '1.1', date: rel + 1 } } }), S.STATUS.outdated);
  assert.strictEqual(S.status(game, 'linux', {}, { g: { linux: { version: null, date: rel + 1000 } } }), S.STATUS.upToDate);
  assert.strictEqual(S.status(game, 'linux', {}, { g: { linux: { version: null, date: rel - 1000 } } }), S.STATUS.outdated);
});

test('bouton rapide : la mise à jour, sinon Linux', () => {
  assert.strictEqual(S.preferredSystem(game, {}, {}), 'linux');
  const inst = { g: { linux: { tag: 'v1.2', exists: true }, windows: { tag: 'v1.0', version: '1.0', exists: true } } };
  assert.strictEqual(S.preferredSystem(game, inst, {}), 'windows');
  const all = { g: { linux: { tag: 'v1.2', exists: true }, windows: { tag: 'v1.2', exists: true } } };
  assert.strictEqual(S.preferredSystem(game, all, {}), null);
});

test('jeu à venir : sans tag, ou assets en liste vide', () => {
  assert.strictEqual(S.isSoon({ ...game, tag: null }), true);
  assert.strictEqual(S.isSoon({ ...game, assets: [] }), true);
  assert.strictEqual(S.isSoon(game), false);
});

test('filtres : recherche sans accents, tri par nom', () => {
  const apps = [{ ...game, id: 'b', name: 'Été' }, { ...game, id: 'a', name: 'Azur', author: 'Moi' }];
  const f = { scope: 'all', console: '', genre: '', system: '', search: 'ete', sort: 'name' };
  assert.deepStrictEqual(S.filtered(apps, f, {}, {}).map((a) => a.id), ['b']);
  assert.deepStrictEqual(S.filtered(apps, { ...f, search: '' }, {}, {}).map((a) => a.id), ['a', 'b']);
});

test('notes : HTML échappé, titres en gras, puces', () => {
  const html = S.notesHTML('## Nouveau\n- **Rapide** <script>\n![img](x)');
  assert.ok(html.includes('<b>Nouveau</b>'));
  assert.ok(html.includes('•  <b>Rapide</b>'));
  assert.ok(!html.includes('<script>'));
  assert.ok(!html.includes('img'));
});
