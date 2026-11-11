// app.js — l'interface de Recomps : barre latérale (bibliothèque, filtres,
// dossiers), grille de jaquettes ou liste, fiche du jeu à droite.
(function () {
  'use strict';
  const S = window.Shared;
  const { esc, h, menu, menuFromButton } = window.UI;
  const $ = (id) => document.getElementById(id);
  const api = window.api;

  let st = null;                 // dernier état envoyé par main.js
  const ui = { scope: 'all', console: '', genre: '', system: '', search: '', selection: null, showAll: {}, expanded: {} };
  const sysIcon = { macos: 'apple', windows: 'windows', linux: 'linux' };
  const scopeIcon = { all: 'grid', mine: 'folder', updates: 'downCircle', new: 'sparkles', soon: 'clock' };

  const statusOf = (a, s) => S.status(a, s, st.installed, st.found);
  const overall = (a) => S.overall(a, st.installed, st.found);
  const subtitle = (a) => [st.origins[a.origin || ''] || a.origin, S.genreFR[a.genre || '']].filter(Boolean).join(' · ');
  const k = (a, s) => `${a.id}|${s}`;

  function pill(status, compact) {
    if (status === S.STATUS.none) return '';
    const [t, i, c] = status === S.STATUS.upToDate ? ['À jour', 'check', 'ok']
      : status === S.STATUS.outdated ? ['Mise à jour', 'download', 'warm'] : ['Présent', 'question', 'unknown'];
    return `<span class="pill ${c}${compact ? ' compact' : ''}">${icon(i, 10)}${compact ? '' : esc(t)}</span>`;
  }

  const sysIcons = (a) => `<span class="sysicons">${S.sysList(a).map((s) => icon(sysIcon[s], 11)).join('')}</span>`;

  function ring(p) {
    const r = 9, c = 2 * Math.PI * r;
    return `<svg class="ring" viewBox="0 0 22 22" title="Téléchargement : ${Math.round(p * 100)} %"><circle cx="11" cy="11" r="${r}" fill="none" stroke="rgba(255,255,255,.15)" stroke-width="2.5"/>`
      + `<circle cx="11" cy="11" r="${r}" fill="none" stroke="var(--accent)" stroke-width="2.5" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - p)}" transform="rotate(-90 11 11)"/></svg>`;
  }

  /** Bouton pour télécharger sans ouvrir la fiche ; les autres systèmes dans le petit menu à côté. */
  function quick(a, compact) {
    const syss = S.sysList(a);
    if (S.isSoon(a) || !syss.length) return '';
    const dl = syss.map((s) => st.downloads[k(a, s)]).find(Boolean);
    if (dl) return ring(dl.progress);
    const pref = S.preferredSystem(a, st.installed, st.found);
    if (!pref) return '';
    const upd = statusOf(a, pref) === S.STATUS.outdated;
    const red = a.files && a.files[pref] && a.files[pref].scan === 'red';
    const others = syss.filter((s) => s !== pref);
    return `<span class="quickdl"><button class="quick${compact ? ' compact' : ''}" data-act="quick" data-sys="${pref}" ${red ? 'disabled' : ''}
      title="${red ? "L'analyse du site a signalé ce fichier : télécharge-le depuis la fiche" : `${upd ? 'Mettre à jour' : 'Télécharger'} pour ${S.sysLabel(pref)}`}">
      ${icon(upd ? 'sync' : 'download', 11)}${compact ? '' : esc(upd ? 'Mettre à jour' : S.sysLabel(pref))}</button>`
      + (others.length ? `<button class="quick-more" data-act="quickMore" title="Autres systèmes">${icon('chevronDown', 13)}</button>` : '')
      + '</span>';
  }

  // ── Barre latérale ───────────────────────────────────────────────────────

  function renderSidebar() {
    const count = (sc) => st.apps.filter((a) => S.inScope(a, sc, st.installed, st.found)).length;
    const consoles = {};
    for (const a of st.apps) { const o = a.origin || 'other'; consoles[o] = (consoles[o] || 0) + 1; }
    const genres = {};
    for (const a of st.apps) { const g = a.genre || 'other'; genres[g] = (genres[g] || 0) + 1; }
    const opt = (v, label, cur) => `<option value="${esc(v)}" ${v === cur ? 'selected' : ''}>${esc(label)}</option>`;
    const short = (p) => { const c = p.split('/').filter(Boolean); return c.length > 3 ? '…/' + c.slice(-3).join('/') : p; };

    $('sidebar').innerHTML = `
      <div class="brand-head"><img src="icon.png" alt="">Recomps</div>
      <h3>Bibliothèque</h3>
      ${S.SCOPES.map((s) => `<button class="side-row${ui.scope === s.id ? ' active' : ''}" data-scope="${s.id}">${icon(scopeIcon[s.id])}<span class="label">${esc(s.label)}</span><span class="count">${count(s.id)}</span></button>`).join('')}
      <h3>Filtres</h3>
      <div class="filters">
        <label>Console <select id="fConsole">${opt('', 'Toutes', ui.console)}${Object.entries(consoles).sort((x, y) => y[1] - x[1]).map(([id, n]) => opt(id, `${st.origins[id] || id} (${n})`, ui.console)).join('')}</select></label>
        <label>Genre <select id="fGenre">${opt('', 'Tous', ui.genre)}${Object.entries(genres).sort((x, y) => y[1] - x[1]).map(([id, n]) => opt(id, `${S.genreFR[id] || id} (${n})`, ui.genre)).join('')}</select></label>
        <label>Système <select id="fSystem">${opt('', 'Tous', ui.system)}${S.SYS.map((s) => opt(s.id, s.label, ui.system)).join('')}</select></label>
        <label>Tri <select id="fSort">${S.SORTS.map((s) => opt(s.id, s.label, st.sort)).join('')}</select></label>
        ${ui.console || ui.genre || ui.system ? '<button class="linkbtn" id="fClear" style="align-self:flex-start">Effacer les filtres</button>' : ''}
      </div>
      <h3>Dossiers des jeux</h3>
      ${S.SYS.map((s) => `<div class="folder-row" data-folder="${s.id}" title="${esc(st.folders[s.id])}\nClic : choisir un autre dossier · clic droit : plus">${icon(sysIcon[s.id])}<div style="min-width:0"><div>${esc(s.label)}</div><div class="p">${esc(short(st.folders[s.id]))}</div></div></div>`).join('')}
    `;
    $('sidefoot').innerHTML = [
      st.error ? `<div style="color:var(--warm)">${esc(st.error)}</div>` : '',
      st.updated ? `<div>Catalogue du ${esc(S.day(String(st.updated).slice(0, 10)))}</div>` : '',
      '<div>Données : recomplauncher.com</div>',
    ].join('');

    $('sidebar').querySelectorAll('[data-scope]').forEach((b) => b.addEventListener('click', () => { ui.scope = b.dataset.scope; render(); }));
    $('fConsole').onchange = (e) => { ui.console = e.target.value; render(); };
    $('fGenre').onchange = (e) => { ui.genre = e.target.value; render(); };
    $('fSystem').onchange = (e) => { ui.system = e.target.value; render(); };
    $('fSort').onchange = (e) => api.call('setSort', e.target.value);
    if ($('fClear')) $('fClear').onclick = () => { ui.console = ''; ui.genre = ''; ui.system = ''; render(); };
    $('sidebar').querySelectorAll('[data-folder]').forEach((row) => {
      row.addEventListener('click', () => api.call('chooseFolder', row.dataset.folder));
      row.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        menu(e.clientX, e.clientY, [
          { label: 'Choisir…', action: () => api.call('chooseFolder', row.dataset.folder) },
          { label: 'Ouvrir le dossier', action: () => api.call('openFolder', row.dataset.folder) },
        ]);
      });
    });
  }

  // ── Barre d'outils ───────────────────────────────────────────────────────

  function renderToolbar(list) {
    const scope = S.SCOPES.find((s) => s.id === ui.scope);
    $('title').textContent = scope.label;
    $('subtitle').textContent = `${list.length} jeu${list.length > 1 ? 'x' : ''}`;
    $('updateAll').innerHTML = updateAllButton();
    $('viewSeg').innerHTML = `<button class="${st.grid ? 'on' : ''}" data-grid="1" title="Grille">${icon('grid')}</button><button class="${st.grid ? '' : 'on'}" data-grid="0" title="Liste">${icon('list')}</button>`;
    $('refresh').innerHTML = st.loading ? '<span class="spinner"></span>' : icon('refresh');
  }

  function updateAllButton() {
    if (st.updating) {
      return `<span class="hstack"><span class="spinner"></span><span class="num" style="font-size:12px">Mise à jour ${Math.min(st.updating.done + 1, st.updating.total)}/${st.updating.total}</span><button class="btn ghost" data-act="stopAll">Arrêter</button></span>`;
    }
    const n = S.outdated(st.apps, st.installed, st.found).length;
    return n ? `<button class="btn brand" data-act="updateAll" title="Télécharge la dernière version de chaque jeu marqué « Mise à jour », l'un après l'autre">${icon('downCircle')}Tout mettre à jour (${n})</button>` : '';
  }

  // ── Grille et liste ──────────────────────────────────────────────────────

  function cardHTML(a) {
    const img = a.cover || a.icon;
    const st0 = overall(a);
    return `<div class="cover">${img ? `<img class="art" loading="lazy" src="${esc(img)}" alt="">` : ''}<div class="shade"></div>
      <div class="foot">${sysIcons(a)}${S.isSoon(a) ? '<span class="soon">Bientôt</span>' : a.version ? `<span class="v">${esc(S.norm(a.version) || a.version)}</span>` : ''}</div>
      <div class="pill-pos">${pill(st0, true)}</div></div>
      <div class="under"><div class="names"><div class="t1">${esc(a.name)}</div><div class="t2">${esc(subtitle(a))}</div></div>${quick(a, true)}</div>`;
  }

  function rowHTML(a) {
    return `<div class="icon40" style="${a.icon ? `background-image:url('${esc(a.icon)}')` : ''}"></div>
      <div class="names"><div class="t1">${esc(a.name)}</div><div class="t2">${esc(subtitle(a))}</div></div>
      ${sysIcons(a)}<div class="ver">${esc(S.isSoon(a) ? 'Bientôt' : (a.version ? S.norm(a.version) || a.version : ''))}</div>
      <div class="pillcol">${pill(overall(a), false)}</div><div class="qcol">${quick(a, false)}</div>`;
  }

  function bannerHTML() {
    const o = S.outdated(st.apps, st.installed, st.found);
    if (ui.scope !== 'updates' || (!o.length && !st.updating)) return '';
    return `<div class="banner">${icon('downCircle', 26)}<div style="flex:1;min-width:0">
      <div class="bt">${st.updating ? 'Mise à jour en cours…' : `${o.length} mise${o.length > 1 ? 's' : ''} à jour disponible${o.length > 1 ? 's' : ''}`}</div>
      <div class="bs">${esc(o.map(([a, s]) => `${a.name} (${S.sysLabel(s)})`).join(' · '))}</div></div>${updateAllButton()}</div>`;
  }

  let lastLayout = null;
  function renderContent(list) {
    const c = $('content');
    const layout = st.grid ? 'grid' : 'rows';
    if (lastLayout !== layout) {
      c.innerHTML = `<div id="banner"></div><div class="${layout}" id="items"></div><div id="emptyState"></div>`;
      lastLayout = layout;
    }
    $('banner').innerHTML = bannerHTML();
    const items = $('items');
    if (st.grid) {
      UI.patchList(items, list, (a) => a.id, cardHTML, (a) => 'card' + (ui.selection === a.id ? ' selected' : ''));
    } else {
      UI.patchList(items, list, (a) => a.id, rowHTML, (a) => 'lrow' + (ui.selection === a.id ? ' selected' : ''));
    }
    $('emptyState').innerHTML = !list.length && !st.loading
      ? `<div class="empty"><div class="m">${st.apps.length ? 'Aucun jeu ne correspond.' : 'Chargement du catalogue…'}</div></div>` : '';
  }

  // ── Fiche ────────────────────────────────────────────────────────────────

  function sysRowHTML(a, s) {
    const status = statusOf(a, s), dl = st.downloads[k(a, s)], f = a.files && a.files[s];
    const inst = st.installed[a.id] && st.installed[a.id][s];
    const found = st.found[a.id] && st.found[a.id][s];
    const local = inst && inst.exists ? inst.file : found ? found.path : null;
    const err = st.errors[k(a, s)];
    const scan = f && f.scan ? ({ green: ['Analyse OK', 'var(--ok)'], yellow: ['Analyse : à vérifier', 'var(--warm)'], red: ['Analyse : alerte', 'var(--red)'] }[f.scan] || ['Analyse en cours', 'var(--muted)']) : null;
    const name = local ? local.split('/').pop() : '';
    const extra = found && found.version && !(inst && inst.exists) ? ` · v${esc(S.norm(found.version) || found.version)}` : '';
    let action;
    if (dl) action = `<button class="btn ghost" data-act="cancel" data-sys="${s}">Annuler</button>`;
    else if (status === S.STATUS.upToDate) action = `<button class="btn ghost" data-act="dl" data-sys="${s}">Retélécharger</button>`;
    else action = `<button class="btn brand" data-act="dl" data-sys="${s}">${status === S.STATUS.none ? 'Télécharger' : 'Mettre à jour'}</button>`;
    return `<div class="sysrow">
      <div class="hstack">${icon(sysIcon[s], 15, '')}<div style="flex:1;min-width:0"><div style="font-weight:600">${S.sysLabel(s)}</div><div class="file" title="${esc((f && f.name) || S.pattern(a, s) || '')}">${esc((f && f.name) || S.pattern(a, s) || '')}</div></div>${pill(status, false)}</div>
      ${local ? `<div class="hstack muted" style="font-size:11px">${icon(/\.(zip|7z|tar|gz|xz|dmg|exe)/i.test(name) ? 'zip' : 'folder', 13)}<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(name)}${extra}</span></div>` : ''}
      ${!dl && err ? `<div class="warnline">${icon('warning', 13)}<span>${esc(err)}</span></div>` : ''}
      ${dl ? `<div><div class="progress"><div style="width:${Math.round(dl.progress * 100)}%;background:var(--accent)"></div></div><div class="muted" style="font-size:10.5px;margin-top:3px">${dl.total ? `${UI.bytes(dl.done)} / ${UI.bytes(dl.total)}` : 'Préparation…'}</div></div>` : ''}
      <div class="hstack">${scan ? `<span class="scan" style="color:${scan[1]}">${icon('shield', 11)}${scan[0]}</span>` : ''}<span class="grow"></span>
        ${local ? `<button class="btn ghost icon" data-act="reveal" data-path="${esc(local)}" title="Afficher dans le gestionnaire de fichiers">${icon('folder')}</button>` : ''}
        ${local && s === 'linux' ? `<button class="btn ghost" data-act="launch" data-sys="${s}">${icon('play', 11)}Lancer</button>` : ''}
        ${action}</div>
    </div>`;
  }

  function changelogHTML(a) {
    const repo = a.repo || '';
    const rels = st.notes[repo];
    let body;
    if (rels) {
      // Version présente : celle téléchargée ici, sinon celle lue sur le fichier.
      let lv = null, ld = null;
      for (const s of S.sysList(a)) { const i = st.installed[a.id] && st.installed[a.id][s]; if (i) { lv = i.tag || i.version; ld = i.date; break; } }
      if (lv == null && ld == null) for (const s of S.sysList(a)) { const f = st.found[a.id] && st.found[a.id][s]; if (f) { lv = f.version; ld = f.date; break; } }
      const mineIdx = lv ? rels.findIndex((r) => S.norm(lv) === S.norm(r.tag_name) || S.norm(lv) === S.norm(r.name)) : -1;
      const isNew = (i, r) => {
        if (lv == null && ld == null) return false;
        if (mineIdx >= 0) return i < mineIdx;
        return !!(ld && r.published_at && Date.parse(r.published_at) > ld);
      };
      const showAll = ui.showAll[a.id];
      const shown = showAll ? rels : rels.slice(0, 3);
      body = (rels.length ? '' : '<div class="muted" style="font-size:12px">Aucune release publiée.</div>')
        + shown.map((r, i) => {
          const ek = `${a.id}:${r.tag_name}`;
          const expanded = ui.expanded[ek] != null ? ui.expanded[ek] : i === 0;
          const text = S.notesHTML(r.body || '');
          const date = r.published_at ? new Date(r.published_at).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' }) : '';
          return `<div class="rel${isNew(i, r) ? ' new' : ''}"><div class="rh"><b class="num">${esc(r.tag_name)}</b>
            ${r.name && r.name !== r.tag_name ? `<span class="muted" style="font-size:12px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis">${esc(r.name)}</span>` : ''}
            <span style="flex:1"></span>
            ${isNew(i, r) ? '<span class="tag" style="color:var(--accent);background:rgba(52,242,232,.12)">nouveau</span>' : ''}
            ${mineIdx === i ? '<span class="tag" style="color:var(--ok);background:rgba(60,220,140,.12)">ta version</span>' : ''}
            ${r.prerelease ? '<span class="tag" style="color:var(--warm);background:rgba(255,181,71,.12)">préversion</span>' : ''}
            <span class="muted" style="font-size:11px">${esc(date)}</span></div>
            ${text ? `<div class="rbody${expanded ? '' : ' clamp'}">${text}</div>
            <div class="hstack" style="font-size:11.5px"><button class="linkbtn" data-act="toggleRel" data-key="${esc(ek)}" data-exp="${expanded ? 1 : 0}">${expanded ? 'Réduire' : 'Lire la suite'}</button><span class="grow"></span>
            ${r.html_url ? `<button class="linkbtn muted" data-act="open" data-url="${esc(r.html_url)}">${/gitlab/.test(r.html_url) ? 'Sur GitLab' : 'Sur GitHub'}</button>` : ''}</div>` : ''}</div>`;
        }).join('')
        + (rels.length > 3 ? `<button class="linkbtn" data-act="showAll" style="align-self:flex-start">${showAll ? 'Moins' : `Toutes les versions (${rels.length})`}</button>` : '');
    } else if (st.notesError[repo]) {
      body = `<div style="color:var(--warm);font-size:12px">${esc(st.notesError[repo])}</div>`;
    } else {
      body = '<div class="hstack muted" style="font-size:12px"><span class="spinner"></span>Chargement…</div>';
    }
    return `<div class="caps">NOTES DE VERSION</div><div class="stack">${body}</div>`;
  }

  function detailHTML(a) {
    const chips = [st.origins[a.origin || ''], S.genreFR[a.genre || ''], a.author ? 'par ' + a.author : null, a.license,
      a.status === 'ended' ? 'arrêté' : a.status === 'paused' ? 'en pause' : a.archived === true ? 'archivé' : null].filter(Boolean);
    const stat = (kk, v) => `<div class="stat"><div class="k">${esc(kk)}</div><div class="v">${esc(v)}</div></div>`;
    const compact = (n) => new Intl.NumberFormat('fr-FR', { notation: 'compact' }).format(n);
    let statusLine = '';
    if (a.status && (['ended', 'paused'].includes(a.status) || a.archived === true)) {
      statusLine = `<div class="warnline" style="font-size:12px">${icon(a.status === 'paused' ? 'pause' : 'x', 13)}<span>${esc(a.status_note || (a.status === 'paused' ? 'Le développement est en pause.' : 'Le développeur a arrêté le projet : plus de mise à jour prévue.'))}</span></div>`;
    } else if (a.archived === true) {
      statusLine = `<div class="warnline" style="font-size:12px">${icon('stack', 13)}<span>Dépôt archivé : plus de mise à jour prévue.</span></div>`;
    }
    const repoURL = a.repo ? (a.host === 'gitlab' ? 'https://gitlab.com/' : 'https://github.com/') + a.repo : null;
    return `<div class="hero" style="${(a.hero || a.cover) ? `background-image:url('${esc(a.hero || a.cover)}')` : ''}">
        <div class="head"><div class="icon58" style="${a.icon ? `background-image:url('${esc(a.icon)}')` : ''}"></div>
        <div style="min-width:0"><h2>${esc(a.name)}</h2>${a.game && a.game !== a.name ? `<div class="muted" style="font-size:12.5px">${esc(a.game)}</div>` : ''}</div></div></div>
      <div class="detail">
        <div class="chips">${chips.map((c) => `<span class="chip" style="color:var(--text)">${esc(c)}</span>`).join('')}</div>
        ${S.isSoon(a) ? '' : `<div class="stats">${stat('Version', a.version ? S.norm(a.version) || a.version : '?')}${stat('Sortie', S.day(a.released))}${a.size ? stat('Taille', a.size) : ''}${a.downloads != null ? stat('Téléch.', compact(a.downloads)) : ''}</div>`}
        ${statusLine}
        ${a.blurb ? `<div class="selectable" style="font-size:13px">${esc(a.blurb)}</div>` : ''}
        ${a.needs ? `<div class="hstack muted" style="font-size:12px;align-items:flex-start">${icon('disc', 14)}<span>${esc(a.needs)}</span></div>` : ''}
        ${S.isSoon(a) ? `<div class="hstack muted">${icon('clock')}Pas encore de version téléchargeable.</div>`
        : `<div class="caps">TÉLÉCHARGER</div>${S.sysList(a).map((s) => sysRowHTML(a, s)).join('')}`}
        ${a.repo && !S.isSoon(a) ? changelogHTML(a) : ''}
        ${a.setup_steps && a.setup_steps.length ? `<div class="caps">INSTALLATION</div>${a.setup_steps.map((t, i) => `<div class="step"><span class="n">${i + 1}</span><span class="selectable">${esc(t)}</span></div>`).join('')}` : ''}
        ${a.features && a.features.length ? `<div class="caps">POINTS FORTS</div>${a.features.map((t) => `<div class="hstack" style="font-size:12.5px;align-items:flex-start">${icon('check', 13)}<span>${esc(t)}</span></div>`).join('')}` : ''}
        ${a.about && a.about.summary ? `<div class="caps">LE JEU</div><div class="muted selectable" style="font-size:12.5px">${esc(a.about.summary)}</div>` : ''}
        <div class="hstack" style="flex-wrap:wrap;padding-top:4px">
          ${repoURL ? `<button class="btn ghost" data-act="open" data-url="${esc(repoURL)}">${a.host === 'gitlab' ? 'GitLab' : 'GitHub'}</button>` : ''}
          ${a.report_url && /^https:/.test(a.report_url) ? `<button class="btn ghost" data-act="open" data-url="${esc(a.report_url)}">Signaler un problème</button>` : ''}
          <button class="btn ghost" data-act="open" data-url="https://recomplauncher.com/pc/game/${encodeURIComponent(a.id)}">Page du site</button>
        </div>
      </div>`;
  }

  let lastDetail = null;
  function renderInspector() {
    const insp = $('inspector');
    const a = ui.selection && st.apps.find((x) => x.id === ui.selection);
    if (!a) { insp.classList.add('hidden'); lastDetail = null; return; }
    insp.classList.remove('hidden');
    const html = detailHTML(a);
    if (html !== lastDetail) {
      const top = insp.scrollTop;
      insp.innerHTML = html;
      insp.dataset.id = a.id;
      if (insp.dataset.prev === a.id) insp.scrollTop = top;
      insp.dataset.prev = a.id;
      lastDetail = html;
    }
    if (a.repo && !st.notes[a.repo] && !st.notesError[a.repo]) api.call('loadNotes', a.id);
  }

  function renderToast() {
    const t = $('toast');
    if (!st.message) { t.classList.add('hidden'); return; }
    t.textContent = st.message;
    t.classList.remove('hidden');
    clearTimeout(renderToast.timer);
    const msg = st.message;
    renderToast.timer = setTimeout(() => { if (st.message === msg) api.call('clearMessage'); }, 6000);
  }

  function render() {
    if (!st) return;
    const list = S.filtered(st.apps, { scope: ui.scope, console: ui.console, genre: ui.genre, system: ui.system, search: ui.search, sort: st.sort }, st.installed, st.found);
    renderSidebar();
    renderToolbar(list);
    renderContent(list);
    renderInspector();
    renderToast();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  const findApp = (id) => st.apps.find((x) => x.id === id);

  async function download(a, s) {
    const f = a.files && a.files[s];
    if (f && f.scan === 'red' && !(await api.call('confirmRed'))) return;
    api.call('download', a.id, s);
  }

  function onAction(e) {
    const el = e.target.closest('[data-act]');
    if (!el) return false;
    const holder = el.closest('[data-key]');
    const a = holder && holder.closest('#items') ? findApp(holder.dataset.key) : findApp(ui.selection);
    const act = el.dataset.act;
    switch (act) {
      case 'quick': if (a) download(a, el.dataset.sys); break;
      case 'quickMore': if (a) {
        const pref = S.preferredSystem(a, st.installed, st.found);
        menuFromButton(el, S.sysList(a).filter((s) => s !== pref).map((s) => ({
          label: `${statusOf(a, s) === S.STATUS.outdated ? 'Mettre à jour' : 'Télécharger'} pour ${S.sysLabel(s)}`,
          disabled: !!(a.files && a.files[s] && a.files[s].scan === 'red'),
          action: () => download(a, s),
        })));
      } break;
      case 'dl': if (a) download(a, el.dataset.sys); break;
      case 'cancel': if (a) api.call('cancel', a.id, el.dataset.sys); break;
      case 'reveal': api.call('reveal', el.dataset.path); break;
      case 'launch': if (a) api.call('launch', a.id, el.dataset.sys); break;
      case 'open': api.call('openExternal', el.dataset.url); break;
      case 'updateAll': api.call('updateAll'); break;
      case 'stopAll': api.call('stopAll'); break;
      case 'showAll': if (a) { ui.showAll[a.id] = !ui.showAll[a.id]; render(); } break;
      case 'toggleRel': ui.expanded[el.dataset.key] = el.dataset.exp !== '1'; render(); break;
      default: return false;
    }
    e.stopPropagation();
    return true;
  }

  document.addEventListener('click', (e) => {
    if (onAction(e)) return;
    const card = e.target.closest('#items > [data-key]');
    if (card) { ui.selection = card.dataset.key; render(); return; }
    // Un clic dans le vide de la grille ferme la fiche.
    if (e.target.closest('#content')) { ui.selection = null; render(); }
  });

  $('viewSeg').addEventListener('click', (e) => { const b = e.target.closest('[data-grid]'); if (b) { e.stopPropagation(); api.call('setGrid', b.dataset.grid === '1'); } });
  $('refresh').addEventListener('click', () => api.call('refreshAll'));
  $('searchIcon').innerHTML = icon('search', 14);
  $('searchClear').innerHTML = icon('x', 12);
  $('search').addEventListener('input', (e) => { ui.search = e.target.value; $('searchBox').classList.toggle('has-text', !!ui.search); render(); });
  $('searchClear').addEventListener('click', (e) => { e.preventDefault(); $('search').value = ''; ui.search = ''; $('searchBox').classList.remove('has-text'); render(); });
  $('toast').addEventListener('click', () => api.call('clearMessage'));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && ui.selection && !document.querySelector('.sheet-back, .ctx-menu')) {
      if (document.activeElement === $('search') && ui.search) return;
      ui.selection = null; render();
    }
  });
  api.on('focusSearch', () => { $('search').focus(); $('search').select(); });
  api.on('state', (s) => { st = s; render(); });
  api.call('ready');
}());
