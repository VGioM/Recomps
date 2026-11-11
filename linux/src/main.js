// Recomps pour Linux : catalogue des recomps PC de recomplauncher.com, avec
// recherche, filtres, téléchargement (Windows, Mac, Linux) et suivi des versions
// présentes dans un dossier par système.
//
// Données : https://recomplauncher.com/pc-catalog.json (le fichier que le site lit
// lui-même, mis en cache avec son ETag). Fichiers : releases GitHub ou GitLab de
// chaque jeu. Pour Linux, l'archive est décompressée (ou l'AppImage rendue
// exécutable) dans le dossier Linux, et « Lancer » démarre le jeu.
'use strict';

const { app, BrowserWindow, ipcMain, dialog, shell, Menu } = require('electron');
const fs = require('fs');
const fsp = require('fs/promises');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawn, execFile } = require('child_process');
const S = require('./shared');
const { Settings, readJSON, writeJSON } = require('./store');
const SelfUpdate = require('./selfupdate');

app.setName('Recomps');
const REPO = 'VGioM/Recomps';
const CATALOG_URL = 'https://recomplauncher.com/pc-catalog.json';
const supportDir = app.getPath('userData');
const settings = new Settings(path.join(supportDir, 'settings.json'), { sort: 'name', grid: true });
const manifestFile = path.join(supportDir, 'installed.json');
const cacheFile = path.join(supportDir, 'pc-catalog.json');
const notesDir = path.join(supportDir, 'notes');

let win = null;

// ── État ───────────────────────────────────────────────────────────────────

const M = {
  apps: [], origins: {}, updated: null, loading: false, error: null,
  installed: readJSON(manifestFile, {}),   // id → système → { tag, version, file, date }
  found: {},                               // id → système → { path, version, date }
  downloads: {},                           // "id|système" → { progress, done, total }
  errors: {},
  message: null,
  updating: null,
  notes: {}, notesError: {},
};
const controllers = {};                    // "id|système" → AbortController
let stopUpdating = false;

function folder(sys) {
  return settings.get(`folder.${sys}`, path.join(app.getPath('downloads'), 'Recomps'));
}

/** `installed` avec, pour chaque entrée, si le fichier est encore là. */
function installedView() {
  const out = {};
  for (const [id, bySys] of Object.entries(M.installed)) {
    out[id] = {};
    for (const [s, i] of Object.entries(bySys)) out[id][s] = { ...i, exists: fs.existsSync(i.file) };
  }
  return out;
}

let pushTimer = null;
function push() {
  if (pushTimer) return;
  pushTimer = setTimeout(() => {
    pushTimer = null;
    if (!win || win.isDestroyed()) return;
    win.webContents.send('state', {
      apps: M.apps, origins: M.origins, updated: M.updated, loading: M.loading, error: M.error,
      installed: installedView(), found: M.found, downloads: M.downloads, errors: M.errors,
      message: M.message, updating: M.updating, notes: M.notes, notesError: M.notesError,
      folders: Object.fromEntries(S.SYS.map((s) => [s.id, folder(s.id)])),
      sort: settings.get('sort'), grid: settings.get('grid'), autoUpdate: SelfUpdate.automatic(),
    });
  }, 60);
}

function say(text) { M.message = text; push(); }
function saveManifest() { writeJSON(manifestFile, M.installed); }

// ── Catalogue ──────────────────────────────────────────────────────────────

function apply(text) {
  try {
    const c = JSON.parse(text);
    M.apps = (Array.isArray(c.apps) ? c.apps : []).filter((a) => a && typeof a.id === 'string' && typeof a.name === 'string');
    M.origins = {};
    for (const o of c.origins || []) if (o && o.id && !(o.id in M.origins)) M.origins[o.id] = o.name;
    M.updated = c.updated || null;
    rescan();
  } catch (e) {
    M.error = `Catalogue illisible : ${e.message}`;
  }
  push();
}

async function refresh() {
  M.loading = true; push();
  try {
    const headers = {};
    const etag = settings.get('etag', null);
    if (M.apps.length && etag) headers['If-None-Match'] = etag;
    const res = await fetch(CATALOG_URL, { headers, cache: 'no-store', signal: AbortSignal.timeout(60000) });
    if (res.status === 304) { M.error = null; rescan(); return; }
    if (res.status !== 200) throw new Error(`code ${res.status}`);
    const text = await res.text();
    fs.mkdirSync(supportDir, { recursive: true });
    fs.writeFileSync(cacheFile, text);
    settings.set('etag', res.headers.get('etag'));
    M.error = null;
    apply(text);
  } catch (e) {
    M.error = M.apps.length ? 'Hors ligne : catalogue en cache.' : `Catalogue injoignable : ${e.message}`;
  } finally {
    M.loading = false; push();
  }
}

/** Actualisation demandée (bouton, Ctrl+R) : catalogue, dossiers, et notes de version rechargées. */
async function refreshAll() {
  M.notes = {}; M.notesError = {};
  await fsp.rm(notesDir, { recursive: true, force: true });
  await refresh();
}

// ── Jeux déjà là ───────────────────────────────────────────────────────────

/** Fichiers et dossiers de la bibliothèque, jusqu'à 3 niveaux. */
async function listFiles(root) {
  const out = [];
  async function walk(dir, level) {
    let entries;
    try { entries = await fsp.readdir(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (e.name.startsWith('.')) continue;
      const p = path.join(dir, e.name);
      let st;
      try { st = await fsp.stat(p); } catch { continue; }
      out.push([e.name, p, st.mtimeMs]);
      if (st.isDirectory() && level < 3 && !e.name.endsWith('.app')) await walk(p, level + 1);
    }
  }
  await walk(root, 1);
  return out;
}

let scanning = null;
function rescan() {
  if (scanning) { scanning.again = true; return; }
  scanning = { again: false };
  (async () => {
    const listing = {};
    for (const s of S.SYS) {
      const f = folder(s.id);
      if (!(f in listing)) listing[f] = await listFiles(f);
    }
    const out = {};
    const keep = (id, s, l) => {
      const o = out[id] && out[id][s];
      if (o && o.date >= l.date) return;
      (out[id] = out[id] || {})[s] = l;
    };
    for (const s of S.SYS) {
      const entries = listing[folder(s.id)] || [];
      if (!entries.length) continue;
      for (const a of M.apps) {
        const p = S.pattern(a, s.id);
        if (!p) continue;
        const res = [S.globRegex(p), S.globRegex(p, true)].filter(Boolean);
        for (const [n, u, d] of entries) {
          for (const re of res) {
            const r = S.firstCapture(re, n);
            if (r.matched) keep(a.id, s.id, { path: u, version: r.capture, date: d });
          }
        }
      }
    }
    M.found = out;
    push();
  })().finally(() => {
    const again = scanning.again;
    scanning = null;
    if (again) rescan();
  });
}

function localPath(a, sys) {
  const i = M.installed[a.id] && M.installed[a.id][sys];
  if (i && fs.existsSync(i.file)) return i.file;
  return M.found[a.id] && M.found[a.id][sys] ? M.found[a.id][sys].path : null;
}

// ── Téléchargement ─────────────────────────────────────────────────────────

const key = (a, s) => `${a.id}|${s}`;
const enc = (s) => encodeURIComponent(s).replace(/%2F/g, '/');

async function resolve(a, sys) {
  const repo = a.repo, pattern = S.pattern(a, sys);
  if (!repo || !pattern) throw new Error(`pas de fichier pour ${S.sysLabel(sys)}`);
  const f = a.files && a.files[sys];
  if (a.host === 'gitlab') return resolveGitLab(repo, a.tag, pattern, f);
  const direct = (tag, name) => `https://github.com/${repo}/releases/download/${enc(tag)}/${enc(name)}`;
  if (a.tag && f && f.name) return { url: direct(a.tag, f.name), name: f.name, sha: f.sha256 || null };
  if (a.tag && !pattern.includes('*')) return { url: direct(a.tag, pattern), name: pattern, sha: null };
  // Modèle avec « * » : on cherche le fichier dans la release (API GitHub, sans compte : 60 requêtes / heure).
  const api = `https://api.github.com/repos/${repo}/releases/${a.tag ? 'tags/' + enc(a.tag) : 'latest'}`;
  const res = await fetch(api, { headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'Recomps' } });
  if (res.status !== 200) throw new Error(`release introuvable sur GitHub (code ${res.status})`);
  const rel = await res.json();
  const re = S.globRegex(pattern);
  const hit = re && (rel.assets || []).find((x) => S.firstCapture(re, x.name).matched);
  if (!hit) throw new Error(`aucun fichier « ${pattern} » dans la release`);
  return { url: hit.browser_download_url, name: hit.name, sha: null };
}

/** GitLab : les fichiers d'une release sont des liens (assets.links) ; celui du nom exact, sinon celui du modèle. */
async function resolveGitLab(repo, tag, pattern, f) {
  const p = encodeURIComponent(repo);
  const rel = tag ? `releases/${encodeURIComponent(tag)}` : 'releases/permalink/latest';
  const res = await fetch(`https://gitlab.com/api/v4/projects/${p}/${rel}`);
  if (res.status !== 200) throw new Error(`release introuvable sur GitLab (code ${res.status})`);
  const r = await res.json();
  const links = (r.assets && r.assets.links) || [];
  const exact = f && links.find((l) => l.name === f.name);
  const full = S.globRegex(pattern), bare = S.globRegex(pattern, true);
  const byPattern = full && links.find((l) => S.firstCapture(full, l.name).matched);
  const byBare = bare && links.find((l) => S.firstCapture(bare, l.name).matched);
  const hit = exact || byPattern || byBare;
  if (!hit) throw new Error(`aucun fichier « ${pattern} » dans la release GitLab`);
  let name = hit.name;
  if (!exact && !byPattern && S.archiveExt(pattern)) name += S.archiveExt(pattern);
  return { url: hit.direct_asset_url || hit.url, name, sha: f && hit.name === f.name ? f.sha256 || null : null };
}

async function fetchTo(url, k) {
  const ctl = new AbortController();
  controllers[k] = ctl;
  const res = await fetch(url, { signal: ctl.signal, headers: { 'User-Agent': 'Recomps' } });
  if (res.status !== 200) throw new Error(`téléchargement refusé (code ${res.status})`);
  const total = Number(res.headers.get('content-length')) || 0;
  const tmp = path.join(os.tmpdir(), `recomps-${crypto.randomUUID()}`);
  const out = fs.createWriteStream(tmp);
  const hash = crypto.createHash('sha256');
  let done = 0;
  try {
    for await (const chunk of res.body) {
      hash.update(chunk);
      done += chunk.length;
      if (!out.write(chunk)) await new Promise((r) => out.once('drain', r));
      if (M.downloads[k]) { M.downloads[k] = { progress: total ? done / total : 0, done, total }; push(); }
    }
    await new Promise((r, j) => out.end((e) => (e ? j(e) : r())));
  } catch (e) {
    out.destroy();
    await fsp.rm(tmp, { force: true });
    throw e;
  }
  return { file: tmp, sha256: hash.digest('hex') };
}

function run(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    execFile(cmd, args, { maxBuffer: 16 << 20, ...opts }, (err, stdout, stderr) => {
      if (err) reject(new Error(`${path.basename(cmd)} : ${String(stderr || err.message).slice(-200)}`));
      else resolve(stdout);
    });
  });
}

/** Décompresse une archive dans `dir` avec les outils du système. */
async function extract(archive, name, dir) {
  const n = name.toLowerCase();
  if (n.endsWith('.zip')) {
    try { await run('unzip', ['-q', '-o', archive, '-d', dir]); }
    catch { await run('7z', ['x', '-y', `-o${dir}`, archive]); }
  } else if (/\.(tar(\.(gz|xz|bz2|zst))?|tgz)$/.test(n)) {
    await run('tar', ['-xf', archive, '-C', dir]);
  } else if (n.endsWith('.7z')) {
    await run('7z', ['x', '-y', `-o${dir}`, archive]);
  } else return false;
  return true;
}

async function isELF(file) {
  try {
    const fh = await fsp.open(file, 'r');
    const b = Buffer.alloc(4);
    await fh.read(b, 0, 4, 0);
    await fh.close();
    return b.equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]));
  } catch { return false; }
}

/** Rend exécutables les programmes d'un jeu décompressé (un zip perd souvent ce droit). */
async function markExecutables(dir, depth = 0) {
  if (depth > 4) return;
  let entries;
  try { entries = await fsp.readdir(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) await markExecutables(p, depth + 1);
    else if (e.isFile() && (/\.(sh|x86_64|appimage)$/i.test(e.name) || await isELF(p))) {
      try { await fsp.chmod(p, (await fsp.stat(p)).mode | 0o755); } catch { /* lecture seule */ }
    }
  }
}

/** Pose le fichier téléchargé dans le dossier du système, et rend le chemin final. */
async function place(a, sys, tmp, name) {
  const root = folder(sys);
  const dir = path.join(root, S.safe(a.name));
  await fsp.mkdir(dir, { recursive: true });
  const ext = S.archiveExt(name);

  if (sys === 'linux' && ext && ext !== '.appimage') {
    // Linux : le jeu est sorti de son archive, prêt à lancer.
    const stem = name.slice(0, name.length - ext.length);
    const work = path.join(root, `.recomps-${crypto.randomUUID()}`);
    await fsp.mkdir(work, { recursive: true });
    try {
      if (await extract(tmp, name, work)) {
        const inside = (await fsp.readdir(work)).filter((x) => !x.startsWith('.'));
        const single = inside.length === 1 && (await fsp.stat(path.join(work, inside[0]))).isDirectory();
        const src = single ? path.join(work, inside[0]) : work;
        const dest = path.join(dir, stem);
        if (fs.existsSync(dest)) await shell.trashItem(dest);
        await fsp.rename(src, dest);
        await markExecutables(dest);
        await fsp.rm(tmp, { force: true });
        return dest;
      }
    } finally {
      await fsp.rm(work, { recursive: true, force: true });
    }
  }

  const dest = path.join(dir, name);
  if (fs.existsSync(dest)) await shell.trashItem(dest);
  try { await fsp.rename(tmp, dest); }
  catch { await fsp.copyFile(tmp, dest); await fsp.rm(tmp, { force: true }); }
  if (ext === '.appimage') await fsp.chmod(dest, 0o755);
  return dest;
}

async function perform(a, sys) {
  const k = key(a, sys);
  if (M.downloads[k]) return false;
  M.downloads[k] = { progress: 0, done: 0, total: 0 };
  push();
  try {
    const { url, name, sha } = await resolve(a, sys);
    const got = await fetchTo(url, k);
    if (sha && got.sha256 !== String(sha).toLowerCase()) {
      await fsp.rm(got.file, { force: true });
      throw new Error("le fichier reçu ne correspond pas à l'empreinte SHA-256 du catalogue");
    }
    const old = localPath(a, sys);
    const oldManaged = !!(M.installed[a.id] && M.installed[a.id][sys]);
    const dest = await place(a, sys, got.file, name);
    // L'ancienne version part à la corbeille, si c'est l'app qui l'avait téléchargée.
    if (old && old !== dest && oldManaged && fs.existsSync(old)) {
      try { await shell.trashItem(old); } catch { /* laissée en place */ }
    }
    (M.installed[a.id] = M.installed[a.id] || {})[sys] = { tag: a.tag || null, version: a.version || null, file: dest, date: Date.now() };
    saveManifest();
    delete M.errors[k];
    if (!M.updating) M.message = `${a.name} (${S.sysLabel(sys)}) : ${path.basename(dest)} dans ${path.basename(folder(sys))}`;
    rescan();
    return true;
  } catch (e) {
    if (e.name !== 'AbortError') {
      M.errors[k] = e.message;
      if (!M.updating) M.message = `${a.name} (${S.sysLabel(sys)}) : ${e.message}`;
    }
    return false;
  } finally {
    delete M.downloads[k];
    delete controllers[k];
    push();
  }
}

/** Tout mettre à jour : un téléchargement après l'autre (GitHub n'aime pas les rafales). */
async function updateAll() {
  if (M.updating) return;
  const todo = S.outdated(M.apps, installedView(), M.found);
  if (!todo.length) return;
  stopUpdating = false;
  M.updating = { done: 0, total: todo.length };
  push();
  let ok = 0;
  for (let i = 0; i < todo.length; i++) {
    if (stopUpdating) break;
    if (await perform(todo[i][0], todo[i][1])) ok++;
    M.updating = { done: i + 1, total: todo.length };
    push();
  }
  M.updating = null;
  const pl = (n) => (n > 1 ? 's' : '');
  say(stopUpdating ? `Mises à jour arrêtées : ${ok} faite${pl(ok)}.`
    : `${ok} mise${pl(ok)} à jour sur ${todo.length}${ok < todo.length ? ' (voir les erreurs sur les fiches)' : ''}.`);
}

function stopAll() {
  stopUpdating = true;
  for (const c of Object.values(controllers)) c.abort();
}

// ── Notes de version (releases GitHub ou GitLab, gardées 6 h sur disque) ───

async function loadNotes(id) {
  const a = M.apps.find((x) => x.id === id);
  if (!a || !a.repo || M.notes[a.repo]) return;
  const repo = a.repo;
  const file = path.join(notesDir, repo.replace(/\//g, '__') + '.json');
  let fresh = false;
  try {
    const st = fs.statSync(file);
    fresh = st.mtimeMs > Date.now() - 6 * 3600 * 1000;
    M.notes[repo] = JSON.parse(fs.readFileSync(file, 'utf8'));
    push();
    if (fresh) return;
  } catch { /* pas encore en cache */ }
  const gl = a.host === 'gitlab';
  const url = gl ? `https://gitlab.com/api/v4/projects/${encodeURIComponent(repo)}/releases?per_page=10`
    : `https://api.github.com/repos/${repo}/releases?per_page=10`;
  try {
    const res = await fetch(url, { headers: { Accept: 'application/json', 'User-Agent': 'Recomps' } });
    if (res.status !== 200) {
      if (!M.notes[repo]) {
        M.notesError[repo] = res.status === 403 || res.status === 429
          ? `${gl ? 'GitLab' : 'GitHub'} limite les requêtes sans compte : réessaie dans un moment.`
          : `Notes indisponibles (code ${res.status}).`;
      }
      return;
    }
    const data = await res.json();
    const rels = gl
      ? data.map((g) => ({ id: g.tag_name, tag_name: g.tag_name, name: g.name, body: g.description, published_at: g.released_at,
        html_url: `https://gitlab.com/${repo}/-/releases/${encodeURIComponent(g.tag_name)}`, prerelease: false }))
      : data.filter((r) => !r.draft).map((r) => ({ id: r.id, tag_name: r.tag_name, name: r.name, body: r.body,
        published_at: r.published_at, html_url: r.html_url, prerelease: !!r.prerelease }));
    M.notes[repo] = rels;
    delete M.notesError[repo];
    writeJSON(file, rels);
  } catch (e) {
    if (!M.notes[repo]) M.notesError[repo] = `Notes indisponibles : ${e.message}`;
  } finally {
    push();
  }
}

// ── Lancer un jeu Linux ────────────────────────────────────────────────────

/** Le programme qui démarre le jeu, dans le dossier décompressé. */
async function findLauncher(dir, gameName) {
  const want = S.fold(gameName).replace(/[^a-z0-9]/g, '');
  const found = [];
  async function walk(d, depth) {
    if (depth > 3) return;
    let entries;
    try { entries = await fsp.readdir(d, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) { if (!/^(lib|lib64|libs|share|doc|docs)$/i.test(e.name)) await walk(p, depth + 1); continue; }
      if (!e.isFile() || /\.so(\.|$)/.test(e.name)) continue;
      const appimage = /\.appimage$/i.test(e.name);
      if (!appimage && !(await isELF(p)) && !/\.(sh|x86_64)$/i.test(e.name)) continue;
      const stem = S.fold(e.name).replace(/\.(appimage|sh|x86_64)$/, '').replace(/[^a-z0-9]/g, '');
      let score = 10 - depth * 2;
      if (appimage) score += 20;
      if (stem && want && (want.includes(stem) || stem.includes(want))) score += 15;
      if (/x86_64|linux/i.test(e.name)) score += 3;
      if (/(crash|handler|helper|update|uninst|setup|config)/i.test(e.name)) score -= 30;
      found.push({ p, score });
    }
  }
  await walk(dir, 0);
  found.sort((x, y) => y.score - x.score);
  return found.length ? found[0].p : null;
}

async function launch(id, sys) {
  const a = M.apps.find((x) => x.id === id);
  const p = a && localPath(a, sys);
  if (!p) return;
  const st = fs.statSync(p);
  const exe = st.isDirectory() ? await findLauncher(p, a.name) : (/\.appimage$/i.test(p) ? p : null);
  if (!exe) { shell.openPath(p); return; }
  try { await fsp.chmod(exe, (await fsp.stat(exe)).mode | 0o755); } catch { /* lecture seule */ }
  const child = spawn(exe, [], { cwd: path.dirname(exe), detached: true, stdio: 'ignore' });
  child.on('error', (e) => say(`${a.name} : ${e.message}`));
  child.unref();
  say(`${a.name} : ${path.basename(exe)} lancé.`);
}

// ── Canaux de l'interface ──────────────────────────────────────────────────

const calls = {
  ready: () => { push(); },
  refreshAll: () => refreshAll(),
  download: (id, sys) => { const a = M.apps.find((x) => x.id === id); if (a) perform(a, sys); },
  cancel: (id, sys) => { const c = controllers[`${id}|${sys}`]; if (c) c.abort(); },
  updateAll: () => updateAll(),
  stopAll: () => stopAll(),
  loadNotes: (id) => loadNotes(id),
  clearMessage: () => { M.message = null; push(); },
  setSort: (s) => { settings.set('sort', s); push(); },
  setGrid: (g) => { settings.set('grid', !!g); push(); },
  chooseFolder: async (sys) => {
    const r = await dialog.showOpenDialog(win, {
      title: `Dossier des jeux ${S.sysLabel(sys)}`,
      message: `Dossier des jeux ${S.sysLabel(sys)} : les téléchargements y vont, et les jeux déjà là y sont cherchés`,
      defaultPath: folder(sys), properties: ['openDirectory', 'createDirectory'], buttonLabel: 'Choisir',
    });
    if (!r.canceled && r.filePaths[0]) { settings.set(`folder.${sys}`, r.filePaths[0]); rescan(); push(); }
  },
  openFolder: (sys) => { fs.mkdirSync(folder(sys), { recursive: true }); shell.openPath(folder(sys)); },
  reveal: (p) => shell.showItemInFolder(p),
  launch: (id, sys) => launch(id, sys),
  openExternal: (url) => { if (/^https:\/\//.test(url)) shell.openExternal(url); },
  confirmRed: async () => {
    const r = await dialog.showMessageBox(win, {
      type: 'warning', message: "L'analyse antivirus du site a signalé ce fichier.",
      detail: "Vérifie le dépôt du projet avant de l'ouvrir.", buttons: ['Télécharger quand même', 'Annuler'], defaultId: 1, cancelId: 1,
    });
    return r.response === 0;
  },
};

ipcMain.handle('call', async (_e, channel, ...args) => {
  const fn = calls[channel];
  if (!fn) throw new Error(`canal inconnu : ${channel}`);
  return fn(...args);
});

// ── Fenêtre et menus ───────────────────────────────────────────────────────

function buildMenu() {
  const template = [
    { label: 'Fichier', submenu: [
      { label: 'Actualiser', accelerator: 'CmdOrCtrl+R', click: () => refreshAll() },
      { type: 'separator' },
      { role: 'quit', label: 'Quitter' },
    ] },
    { label: 'Édition', submenu: [
      { role: 'undo', label: 'Annuler' }, { role: 'redo', label: 'Rétablir' }, { type: 'separator' },
      { role: 'cut', label: 'Couper' }, { role: 'copy', label: 'Copier' }, { role: 'paste', label: 'Coller' },
      { role: 'selectAll', label: 'Tout sélectionner' },
      { type: 'separator' },
      { label: 'Rechercher', accelerator: 'CmdOrCtrl+F', click: () => win && win.webContents.send('focusSearch') },
    ] },
    { label: 'Affichage', submenu: [
      { role: 'resetZoom', label: 'Taille réelle' }, { role: 'zoomIn', label: 'Agrandir' }, { role: 'zoomOut', label: 'Réduire' },
      { type: 'separator' }, { role: 'togglefullscreen', label: 'Plein écran' },
      { role: 'toggleDevTools', label: 'Outils de développement' },
    ] },
    { label: 'Aide', submenu: [
      { label: SelfUpdate.menuTitle, click: () => SelfUpdate.checkNow() },
      { label: SelfUpdate.automaticTitle, type: 'checkbox', checked: SelfUpdate.automatic(),
        click: (item) => { SelfUpdate.setAutomatic(item.checked); push(); } },
      { type: 'separator' },
      { label: 'Page du projet', click: () => shell.openExternal(`https://github.com/${REPO}`) },
      { label: 'recomplauncher.com', click: () => shell.openExternal('https://recomplauncher.com/all') },
      { type: 'separator' },
      { label: `À propos de Recomps ${app.getVersion()}`, click: () => dialog.showMessageBox(win, {
        message: `Recomps ${app.getVersion()}`,
        detail: "Recomps n'est pas affilié à recomplauncher.com ni aux projets listés : il lit leur catalogue public et télécharge depuis les dépôts GitHub ou GitLab de chaque projet.",
      }) },
    ] },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function createWindow() {
  win = new BrowserWindow({
    width: 1280, height: 820, minWidth: 980, minHeight: 620,
    title: 'Recomps', backgroundColor: '#0B1220', autoHideMenuBar: true,
    icon: path.join(__dirname, '..', 'resources', 'icon.png'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true, nodeIntegration: false },
  });
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.on('focus', () => rescan());
  // Les liens s'ouvrent dans le navigateur, jamais dans la fenêtre de l'app.
  win.webContents.setWindowOpenHandler(({ url }) => { if (/^https:\/\//.test(url)) shell.openExternal(url); return { action: 'deny' }; });
  win.webContents.on('will-navigate', (e) => e.preventDefault());
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });
  app.whenReady().then(() => {
    fs.mkdirSync(supportDir, { recursive: true });
    SelfUpdate.start(REPO, settings);
    buildMenu();
    createWindow();
    try { apply(fs.readFileSync(cacheFile, 'utf8')); } catch { /* premier lancement */ }
    refresh();
  });
  app.on('window-all-closed', () => app.quit());
}
