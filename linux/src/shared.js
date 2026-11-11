// shared.js — la logique de Recomps qui ne touche ni au disque ni au réseau :
// versions, modèles de fichiers, état de chaque jeu, filtres et tri. Chargé à
// la fois par main.js (require) et par l'interface (<script>), pour que les
// deux côtés comptent pareil. Traduction directe de main.swift.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.Shared = factory();
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const SYS = [
    { id: 'linux', label: 'Linux' },
    { id: 'windows', label: 'Windows' },
    { id: 'macos', label: 'Mac' },
  ];
  const sysLabel = (id) => (SYS.find((s) => s.id === id) || { label: id }).label;

  const genreFR = {
    action: 'Action', platformer: 'Plateformes', fighting: 'Combat', rpg: 'RPG', racing: 'Course',
    shooter: 'Tir', adventure: 'Aventure', sports: 'Sport', puzzle: 'Réflexion', other: 'Autre',
  };

  const STATUS = { none: 0, upToDate: 1, unknown: 2, outdated: 3 };

  const SCOPES = [
    { id: 'all', label: 'Tous les jeux' },
    { id: 'mine', label: 'Mes jeux' },
    { id: 'updates', label: 'Mises à jour' },
    { id: 'new', label: 'Nouvelles versions' },
    { id: 'soon', label: 'Bientôt' },
  ];
  const SORTS = [
    { id: 'name', label: 'Nom' },
    { id: 'released', label: 'Dernière version' },
    { id: 'added', label: 'Ajout au catalogue' },
    { id: 'popular', label: 'Popularité' },
  ];

  /** 1.0.0 = 1.0 = 1, « v1.2 » = « 1.2 ». */
  function norm(v) {
    if (v == null) return null;
    let s = String(v).trim().toLowerCase();
    if (!s) return null;
    if (s.startsWith('v') && /[0-9]/.test(s[1] || '')) s = s.slice(1);
    const parts = s.split('.');
    while (parts.length > 1 && parts[parts.length - 1] === '0') parts.pop();
    return parts.join('.');
  }

  const archiveExts = ['.tar.gz', '.tar.xz', '.tar.bz2', '.tar.zst', '.zip', '.7z', '.dmg', '.tar', '.appimage', '.exe', '.pkg', '.tgz'];
  function archiveExt(name) {
    const n = String(name).toLowerCase();
    return archiveExts.find((e) => n.endsWith(e)) || null;
  }

  const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

  /** Modèle « Nom-*-macOS.zip » → expression régulière ; le « * » capture la version. */
  function globRegex(glob, stripExt) {
    let g = String(glob);
    if (stripExt) {
      const e = archiveExt(g);
      if (e) g = g.slice(0, g.length - e.length);
    }
    const parts = g.split('*').map(escapeRe);
    try { return new RegExp('^' + parts.join('(.+?)') + '$', 'i'); } catch { return null; }
  }

  function firstCapture(re, s) {
    const m = re.exec(s);
    if (!m) return { matched: false, capture: null };
    return { matched: true, capture: m.length > 1 ? m[1] : null };
  }

  function pattern(a, sys) {
    const assets = a.assets;
    if (!assets || Array.isArray(assets) || typeof assets !== 'object') return null;
    const p = assets[sys];
    return typeof p === 'string' ? p : null;
  }

  function sysList(a) {
    return SYS.map((s) => s.id).filter((s) => (a.systems || []).includes(s) && pattern(a, s) != null);
  }

  function isSoon(a) { return a.soon === true || a.tag == null || sysList(a).length === 0; }

  function isoDay(s) {
    if (!s || !/^\d{4}-\d{2}-\d{2}/.test(s)) return null;
    const d = new Date(s.slice(0, 10) + 'T00:00:00');
    return isNaN(d) ? null : d.getTime();
  }

  function day(s) {
    const t = isoDay(s);
    if (t == null) return '';
    return new Date(t).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' });
  }

  /**
   * État d'un jeu pour un système. `installed` : ce que l'app a téléchargé
   * (avec `exists` vérifié côté disque) ; `found` : ce que l'analyse des
   * dossiers a reconnu ({ version, date }).
   */
  function status(a, sys, installed, found) {
    const i = installed && installed[a.id] && installed[a.id][sys];
    if (i && i.exists) {
      return (norm(i.tag) === norm(a.tag) || norm(i.version) === norm(a.version)) ? STATUS.upToDate : STATUS.outdated;
    }
    const f = found && found[a.id] && found[a.id][sys];
    if (!f) return STATUS.none;
    const rel = isoDay(a.released);
    const v = norm(f.version);
    if (v) {
      if (v === norm(a.version) || v === norm(a.tag)) return STATUS.upToDate;
      if (rel != null && f.date < rel) return STATUS.outdated;
      return f.isApp ? STATUS.unknown : STATUS.outdated;
    }
    if (rel == null) return STATUS.unknown;
    return f.date >= rel ? STATUS.upToDate : STATUS.outdated;   // nom sans version : on compare à la date de la release
  }

  function overall(a, installed, found) {
    return sysList(a).reduce((m, s) => Math.max(m, status(a, s, installed, found)), STATUS.none);
  }

  function inScope(a, scope, installed, found, now) {
    switch (scope) {
      case 'all': return !isSoon(a);
      case 'mine': return overall(a, installed, found) !== STATUS.none;
      case 'updates': return overall(a, installed, found) === STATUS.outdated;
      case 'soon': return isSoon(a);
      case 'new': {
        const d = isoDay(a.released);
        return d != null && !isSoon(a) && d > (now || Date.now()) - 14 * 86400000;
      }
      default: return true;
    }
  }

  const fold = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const collator = new Intl.Collator('fr', { numeric: true, sensitivity: 'base' });

  function filtered(apps, f, installed, found) {
    const q = fold(f.search.trim());
    const list = apps.filter((a) => inScope(a, f.scope, installed, found)
      && (!f.console || a.origin === f.console)
      && (!f.genre || a.genre === f.genre)
      && (!f.system || (a.systems || []).includes(f.system))
      && (!q || fold([a.name, a.game, a.author, (a.about && a.about.genres || []).join(' '), (a.tags || []).join(' ')].join(' ')).includes(q)));
    switch (f.sort) {
      case 'released': return list.sort((x, y) => String(y.released || '').localeCompare(String(x.released || '')));
      case 'added': return list.sort((x, y) => String(y.added || '').localeCompare(String(x.added || '')));
      case 'popular': return list.sort((x, y) => (y.downloads || 0) - (x.downloads || 0));
      default: return list.sort((x, y) => collator.compare(x.name, y.name));
    }
  }

  /** Ce qui a une mise à jour : chaque jeu × système marqué « Mise à jour ». */
  function outdated(apps, installed, found) {
    const out = [];
    for (const a of apps) for (const s of sysList(a)) {
      if (status(a, s, installed, found) === STATUS.outdated) out.push([a, s]);
    }
    return out;
  }

  /** Le système proposé par le bouton rapide : celui qui a une mise à jour, sinon Linux, sinon le premier pas à jour. */
  function preferredSystem(a, installed, found) {
    const syss = sysList(a);
    const st = (s) => status(a, s, installed, found);
    return syss.find((s) => st(s) === STATUS.outdated)
      || (syss.includes('linux') && st('linux') !== STATUS.upToDate ? 'linux' : null)
      || syss.find((s) => st(s) !== STATUS.upToDate)
      || null;
  }

  /** Markdown de GitHub → HTML sûr : titres en gras, puces, sans images ni HTML. */
  function notesHTML(md) {
    const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const lines = [];
    for (const raw of String(md || '').replace(/\r/g, '').split('\n')) {
      let l = raw.replace(/<[^>]+>/g, '').trim();
      if (l.startsWith('![') || l.startsWith('[![')) continue;
      while (l.startsWith('>')) l = l.slice(1).trim();
      if (/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$/.test(l)) continue;
      let bold = false;
      const h = l.match(/^#{1,6}\s*/);
      if (h) { l = l.slice(h[0].length).replace(/\*\*/g, ''); bold = !!l; }
      else {
        const b = l.match(/^[-*+]\s+/);
        if (b) l = '•  ' + l.slice(b[0].length);
      }
      if (!l && (lines.length === 0 || lines[lines.length - 1] === '')) continue;
      let html = esc(l)
        .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
        .replace(/`([^`]+)`/g, '<code>$1</code>')
        .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '$1');
      if (bold) html = `<b>${html}</b>`;
      lines.push(html);
    }
    while (lines.length && lines[lines.length - 1] === '') lines.pop();
    return lines.join('\n');
  }

  function safe(s) {
    return String(s).replace(/\//g, '-').replace(/:/g, ' -').trim();
  }

  return {
    SYS, sysLabel, genreFR, STATUS, SCOPES, SORTS, norm, archiveExt, globRegex, firstCapture, pattern,
    sysList, isSoon, isoDay, day, status, overall, inScope, filtered, outdated, preferredSystem, notesHTML, safe, fold,
  };
}));
