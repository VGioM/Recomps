//! L'état de Recomps et ce qui tourne en fond : catalogue (mis en cache avec
//! son ETag), analyse des dossiers, téléchargements, notes de version, lancement
//! des jeux Linux. Traduction de main.swift / main.js.

use crate::common::images::ImageCache;
use crate::common::selfupdate::SelfUpdate;
use crate::common::store::{self, Settings};
use crate::common::sys;
use crate::common::theme;
use crate::common::ui::Toast;
use crate::model::{self, Found, FoundMap, Installed, InstalledMap, Recomp, State};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc, Mutex};

pub const REPO: &str = "VGioM/Recomps";
const CATALOG_URL: &str = "https://recomplauncher.com/pc-catalog.json";

#[derive(Clone, Default)]
pub struct Dl { pub done: u64, pub total: u64 }

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct Release { pub tag_name: String, pub name: Option<String>, pub body: Option<String>, pub published_at: Option<String>, pub html_url: Option<String>, #[serde(default)] pub prerelease: bool }

pub enum Bg {
    Catalog(Result<Option<String>, String>, Option<String>),
    Found(FoundMap),
    Downloaded(String, String, Result<PathBuf, String>),
    Notes(String, Result<Vec<Release>, String>),
    Message(String),
    UpdateAllDone(usize, usize, bool),
}

pub struct App {
    pub p: theme::Palette,
    pub dir: PathBuf,
    pub settings: Settings,
    pub images: ImageCache,
    pub apps: Vec<Recomp>,
    pub origins: HashMap<String, String>,
    pub updated: Option<String>,
    pub loading: bool,
    pub error: Option<String>,
    pub installed: InstalledMap,
    pub found: FoundMap,
    pub downloads: Arc<Mutex<HashMap<String, Dl>>>,
    cancels: Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
    pub errors: HashMap<String, String>,
    pub notes: HashMap<String, Vec<Release>>,
    pub notes_error: HashMap<String, String>,
    notes_loading: std::collections::HashSet<String>,
    pub updating: Arc<Mutex<Option<(usize, usize)>>>,
    stop_updating: Arc<AtomicBool>,

    pub scope: String,
    pub console: String,
    pub genre: String,
    pub system: String,
    pub search: String,
    pub focus_search: bool,
    pub selection: Option<String>,
    pub show_all: std::collections::HashSet<String>,
    pub expanded: HashMap<String, bool>,
    pub confirm_red: Option<(String, String)>,
    pub pending_folder: Option<(String, mpsc::Receiver<Vec<PathBuf>>)>,

    pub tx: mpsc::Sender<Bg>,
    rx: mpsc::Receiver<Bg>,
    scanning: bool,
    scan_again: bool,
    pub toast: Toast,
    pub update: SelfUpdate,
    pub test: crate::common::testhook::TestHook,
    test_done: bool,
    was_focused: bool,
}

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder().timeout_global(Some(std::time::Duration::from_secs(60))).user_agent("Recomps").http_status_as_error(false).build().into()
}

impl App {
    pub fn new(cc: &eframe::CreationContext) -> Self {
        let p = theme::RECOMPS;
        theme::install(&cc.egui_ctx, &p);
        egui_extras::install_image_loaders(&cc.egui_ctx);
        let dir = store::support_dir("Recomps", None);
        let settings = Settings::new(dir.join("settings.json"), json!({ "sort": "name", "grid": true }));
        let (tx, rx) = mpsc::channel();
        let mut app = App {
            p, images: ImageCache::new(&cc.egui_ctx, store::cache_dir("Recomps").join("images"), 8),
            installed: store::read_json(&dir.join("installed.json")).unwrap_or_default(), settings, dir,
            apps: vec![], origins: HashMap::new(), updated: None, loading: false, error: None, found: HashMap::new(),
            downloads: Arc::default(), cancels: Arc::default(), errors: HashMap::new(), notes: HashMap::new(), notes_error: HashMap::new(),
            notes_loading: Default::default(), updating: Arc::default(), stop_updating: Arc::default(),
            scope: "all".into(), console: String::new(), genre: String::new(), system: String::new(), search: String::new(), focus_search: false,
            selection: None, show_all: Default::default(), expanded: HashMap::new(), confirm_red: None, pending_folder: None,
            tx, rx, scanning: false, scan_again: false, toast: Toast::default(), update: SelfUpdate::new(REPO, "Recomps"),
            test: Default::default(), test_done: false, was_focused: true,
        };
        if let Ok(t) = std::fs::read_to_string(app.dir.join("pc-catalog.json")) { app.apply(&t, &cc.egui_ctx); }
        app.refresh(&cc.egui_ctx);
        app
    }

    pub fn folder(&self, sys: &str) -> PathBuf {
        let s = self.settings.string(&format!("folder.{sys}"));
        if s.is_empty() { dirs::download_dir().unwrap_or_else(|| dirs::home_dir().unwrap_or_default()).join("Recomps") } else { PathBuf::from(s) }
    }

    pub fn state(&self) -> State<'_> { State { installed: &self.installed, found: &self.found } }
    pub fn app(&self, id: &str) -> Option<&Recomp> { self.apps.iter().find(|a| a.id == id) }
    pub fn key(id: &str, sys: &str) -> String { format!("{id}|{sys}") }

    fn apply(&mut self, text: &str, ctx: &egui::Context) {
        match model::parse_catalog(text) {
            Ok(c) => { self.apps = c.apps; self.origins = c.origins; self.updated = c.updated; self.rescan(ctx); }
            Err(e) => self.error = Some(format!("Catalogue illisible : {e}")),
        }
    }

    pub fn refresh(&mut self, ctx: &egui::Context) {
        if self.loading { return; }
        self.loading = true;
        let etag = if self.apps.is_empty() { None } else { Some(self.settings.string("etag")).filter(|e| !e.is_empty()) };
        let (tx, ctx) = (self.tx.clone(), ctx.clone());
        std::thread::spawn(move || {
            let mut req = agent().get(CATALOG_URL).header("Cache-Control", "no-cache");
            if let Some(e) = &etag { req = req.header("If-None-Match", e); }
            let msg = match req.call() {
                Ok(mut r) if r.status().as_u16() == 304 => Bg::Catalog(Ok(None), None),
                Ok(mut r) if r.status().as_u16() == 200 => {
                    let tag = r.headers().get("etag").and_then(|v| v.to_str().ok()).map(String::from);
                    match r.body_mut().with_config().limit(64 << 20).read_to_string() { Ok(t) => Bg::Catalog(Ok(Some(t)), tag), Err(e) => Bg::Catalog(Err(e.to_string()), None) }
                }
                Ok(r) => Bg::Catalog(Err(format!("code {}", r.status().as_u16())), None),
                Err(e) => Bg::Catalog(Err(e.to_string()), None),
            };
            let _ = tx.send(msg);
            ctx.request_repaint();
        });
    }

    /// Actualisation demandée (bouton, Ctrl+R) : catalogue, dossiers, et notes de version rechargées.
    pub fn refresh_all(&mut self, ctx: &egui::Context) {
        self.notes.clear();
        self.notes_error.clear();
        let _ = std::fs::remove_dir_all(self.dir.join("notes"));
        self.refresh(ctx);
        self.rescan(ctx);
    }

    // ── Jeux déjà là ──────────────────────────────────────────────────────

    pub fn rescan(&mut self, ctx: &egui::Context) {
        if self.scanning { self.scan_again = true; return; }
        self.scanning = true;
        let folders: Vec<(&'static str, PathBuf)> = model::SYSTEMS.iter().map(|s| (s.0, self.folder(s.0))).collect();
        let apps = self.apps.clone();
        let (tx, ctx) = (self.tx.clone(), ctx.clone());
        std::thread::spawn(move || {
            let mut listing: HashMap<PathBuf, Vec<(String, PathBuf, i64)>> = HashMap::new();
            for (_, f) in &folders { listing.entry(f.clone()).or_insert_with(|| list_files(f)); }
            let mut out: FoundMap = HashMap::new();
            for (sys, f) in &folders {
                let entries = &listing[f];
                if entries.is_empty() { continue; }
                for a in &apps {
                    let Some(p) = a.pattern(sys) else { continue };
                    for (n, u, d) in entries {
                        for strip in [false, true] {
                            let (ok, cap) = model::glob_match(p, n, strip);
                            if !ok { continue; }
                            let slot = out.entry(a.id.clone()).or_default();
                            if slot.get(*sys).map(|o| o.date >= *d).unwrap_or(false) { continue; }
                            slot.insert(sys.to_string(), Found { path: u.clone(), version: cap, date: *d });
                        }
                    }
                }
            }
            let _ = tx.send(Bg::Found(out));
            ctx.request_repaint();
        });
    }

    // ── Téléchargement ────────────────────────────────────────────────────

    pub fn download(&mut self, ctx: &egui::Context, id: &str, sys: &str) {
        let Some(a) = self.app(id).cloned() else { return };
        let k = Self::key(id, sys);
        if self.downloads.lock().unwrap().contains_key(&k) { return; }
        self.downloads.lock().unwrap().insert(k.clone(), Dl::default());
        let cancel = Arc::new(AtomicBool::new(false));
        self.cancels.lock().unwrap().insert(k.clone(), cancel.clone());
        let old = self.state().local_path(&a, sys);
        let old_managed = self.installed.get(id).and_then(|m| m.get(sys)).is_some();
        let (tx, ctx, root, dls, sys) = (self.tx.clone(), ctx.clone(), self.folder(sys), self.downloads.clone(), sys.to_string());
        std::thread::spawn(move || {
            let r = perform(&a, &sys, &root, &dls, &k, &cancel, &ctx);
            // L'ancienne version part à la corbeille, si c'est l'app qui l'avait téléchargée.
            if let (Ok(dest), Some(old)) = (&r, &old) { if old != dest && old_managed && old.exists() { let _ = sys::trash(old); } }
            dls.lock().unwrap().remove(&k);
            let _ = tx.send(Bg::Downloaded(a.id.clone(), sys, r));
            ctx.request_repaint();
        });
    }

    pub fn cancel(&self, id: &str, sys: &str) {
        if let Some(c) = self.cancels.lock().unwrap().get(&Self::key(id, sys)) { c.store(true, Ordering::SeqCst); }
    }

    /// Tout mettre à jour : un téléchargement après l'autre (GitHub n'aime pas les rafales).
    pub fn update_all(&mut self, ctx: &egui::Context) {
        if self.updating.lock().unwrap().is_some() { return; }
        let todo: Vec<(Recomp, &'static str)> = self.state().outdated(&self.apps).into_iter().map(|(i, s)| (self.apps[i].clone(), s)).collect();
        if todo.is_empty() { return; }
        self.stop_updating.store(false, Ordering::SeqCst);
        *self.updating.lock().unwrap() = Some((0, todo.len()));
        let roots: HashMap<&str, PathBuf> = model::SYSTEMS.iter().map(|s| (s.0, self.folder(s.0))).collect();
        let installed = self.installed.clone();
        let found = self.found.clone();
        let (tx, ctx, dls, upd, stop, cancels) = (self.tx.clone(), ctx.clone(), self.downloads.clone(), self.updating.clone(), self.stop_updating.clone(), self.cancels.clone());
        std::thread::spawn(move || {
            let mut ok = 0;
            let total = todo.len();
            for (i, (a, sys)) in todo.into_iter().enumerate() {
                if stop.load(Ordering::SeqCst) { break; }
                let k = Self::key(&a.id, sys);
                dls.lock().unwrap().insert(k.clone(), Dl::default());
                let cancel = Arc::new(AtomicBool::new(false));
                cancels.lock().unwrap().insert(k.clone(), cancel.clone());
                let st = State { installed: &installed, found: &found };
                let old = st.local_path(&a, sys);
                let managed = installed.get(&a.id).and_then(|m| m.get(sys)).is_some();
                let r = perform(&a, sys, &roots[sys], &dls, &k, &cancel, &ctx);
                if let (Ok(dest), Some(old)) = (&r, &old) { if old != dest && managed && old.exists() { let _ = sys::trash(old); } }
                if r.is_ok() { ok += 1; }
                dls.lock().unwrap().remove(&k);
                let _ = tx.send(Bg::Downloaded(a.id.clone(), sys.to_string(), r));
                *upd.lock().unwrap() = Some((i + 1, total));
                ctx.request_repaint();
            }
            *upd.lock().unwrap() = None;
            let _ = tx.send(Bg::UpdateAllDone(ok, total, stop.load(Ordering::SeqCst)));
            ctx.request_repaint();
        });
    }

    pub fn stop_all(&self) {
        self.stop_updating.store(true, Ordering::SeqCst);
        for c in self.cancels.lock().unwrap().values() { c.store(true, Ordering::SeqCst); }
    }

    // ── Notes de version (GitHub ou GitLab, gardées 6 h sur disque) ───────

    pub fn load_notes(&mut self, ctx: &egui::Context, id: &str) {
        let Some(a) = self.app(id).cloned() else { return };
        let Some(repo) = a.repo.clone() else { return };
        if self.notes.contains_key(&repo) && !self.notes_loading.contains(&repo) { return; }
        if self.notes_loading.contains(&repo) || self.notes_error.contains_key(&repo) { return; }
        let file = self.dir.join("notes").join(repo.replace('/', "__") + ".json");
        let fresh = std::fs::metadata(&file).and_then(|m| m.modified()).ok().map(|t| t.elapsed().map(|e| e.as_secs() < 6 * 3600).unwrap_or(false)).unwrap_or(false);
        if let Some(r) = store::read_json::<Vec<Release>>(&file) { self.notes.insert(repo.clone(), r); if fresh { return; } }
        self.notes_loading.insert(repo.clone());
        let (tx, ctx) = (self.tx.clone(), ctx.clone());
        std::thread::spawn(move || {
            let gl = a.gitlab();
            let url = if gl { format!("https://gitlab.com/api/v4/projects/{}/releases?per_page=10", urlenc(&repo)) } else { format!("https://api.github.com/repos/{repo}/releases?per_page=10") };
            let res = (|| -> Result<Vec<Release>, String> {
                let mut r = agent().get(&url).header("Accept", "application/json").call().map_err(|e| format!("Notes indisponibles : {e}"))?;
                let code = r.status().as_u16();
                if code != 200 {
                    return Err(if code == 403 || code == 429 { format!("{} limite les requêtes sans compte : réessaie dans un moment.", if gl { "GitLab" } else { "GitHub" }) } else { format!("Notes indisponibles (code {code}).") });
                }
                let v: Value = r.body_mut().read_json().map_err(|e| e.to_string())?;
                let arr = v.as_array().cloned().unwrap_or_default();
                Ok(if gl {
                    arr.iter().map(|g| Release { tag_name: g["tag_name"].as_str().unwrap_or("").into(), name: g["name"].as_str().map(String::from), body: g["description"].as_str().map(String::from),
                        published_at: g["released_at"].as_str().map(String::from), html_url: Some(format!("https://gitlab.com/{repo}/-/releases/{}", urlenc(g["tag_name"].as_str().unwrap_or("")))), prerelease: false }).collect()
                } else {
                    arr.iter().filter(|r| !r["draft"].as_bool().unwrap_or(false)).filter_map(|r| serde_json::from_value(r.clone()).ok()).collect()
                })
            })();
            if let Ok(r) = &res { let _ = store::write_json(&file, r, false); }
            let _ = tx.send(Bg::Notes(repo, res));
            ctx.request_repaint();
        });
    }

    // ── Lancer un jeu Linux ───────────────────────────────────────────────

    pub fn launch(&mut self, id: &str, sys: &str) {
        let Some(a) = self.app(id).cloned() else { return };
        let Some(p) = self.state().local_path(&a, sys) else { return };
        let exe = if p.is_dir() { find_launcher(&p, &a.name) } else if p.to_string_lossy().to_lowercase().ends_with(".appimage") { Some(p.clone()) } else { None };
        let Some(exe) = exe else { sys::open_path(&p); return };
        use std::os::unix::fs::PermissionsExt;
        if let Ok(m) = std::fs::metadata(&exe) { let _ = std::fs::set_permissions(&exe, std::fs::Permissions::from_mode(m.permissions().mode() | 0o755)); }
        let mut c = sys::clean_command(&exe);
        c.current_dir(exe.parent().unwrap_or(&p));
        match sys::spawn_detached(c) {
            Ok(()) => self.toast.show(format!("{} : {} lancé.", a.name, exe.file_name().unwrap_or_default().to_string_lossy())),
            Err(e) => self.toast.show(format!("{} : {e}", a.name)),
        }
    }

    pub fn choose_folder(&mut self, sys: &str) {
        let start = self.folder(sys);
        let rx = sys::pick(sys::Pick::Folder, &format!("Dossier des jeux {} : les téléchargements y vont, et les jeux déjà là y sont cherchés", model::sys_label(sys)), Some(&start), &[]);
        self.pending_folder = Some((sys.to_string(), rx));
    }

    fn save_manifest(&self) { let _ = store::write_json(&self.dir.join("installed.json"), &self.installed, false); }

    pub fn pump(&mut self, ctx: &egui::Context) {
        while let Ok(m) = self.rx.try_recv() {
            match m {
                Bg::Catalog(r, etag) => {
                    self.loading = false;
                    match r {
                        Ok(None) => { self.error = None; self.rescan(ctx); }
                        Ok(Some(text)) => {
                            let _ = std::fs::write(self.dir.join("pc-catalog.json"), &text);
                            if let Some(e) = etag { self.settings.set("etag", e); }
                            self.error = None;
                            self.apply(&text, ctx);
                        }
                        Err(e) => self.error = Some(if self.apps.is_empty() { format!("Catalogue injoignable : {e}") } else { "Hors ligne : catalogue en cache.".into() }),
                    }
                }
                Bg::Found(f) => { self.found = f; self.scanning = false; if std::mem::take(&mut self.scan_again) { self.rescan(ctx); } }
                Bg::Downloaded(id, sys, r) => {
                    let k = Self::key(&id, &sys);
                    self.cancels.lock().unwrap().remove(&k);
                    let name = self.app(&id).map(|a| a.name.clone()).unwrap_or_default();
                    let quiet = self.updating.lock().unwrap().is_some();
                    match r {
                        Ok(dest) => {
                            let (tag, version) = self.app(&id).map(|a| (a.tag.clone(), a.version.clone())).unwrap_or_default();
                            self.installed.entry(id.clone()).or_default().insert(sys.clone(), Installed { tag, version, file: dest.to_string_lossy().into(), date: sys::now_ms() });
                            self.save_manifest();
                            self.errors.remove(&k);
                            if !quiet { self.toast.show(format!("{name} ({}) : {} dans {}", model::sys_label(&sys), dest.file_name().unwrap_or_default().to_string_lossy(), self.folder(&sys).file_name().unwrap_or_default().to_string_lossy())); }
                            self.rescan(ctx);
                        }
                        Err(e) if e == "annulé" => {}
                        Err(e) => { if !quiet { self.toast.show(format!("{name} ({}) : {e}", model::sys_label(&sys))); } self.errors.insert(k, e); }
                    }
                }
                Bg::Notes(repo, r) => {
                    self.notes_loading.remove(&repo);
                    match r { Ok(v) => { self.notes.insert(repo.clone(), v); self.notes_error.remove(&repo); } Err(e) => { if !self.notes.contains_key(&repo) { self.notes_error.insert(repo, e); } } }
                }
                Bg::Message(t) => self.toast.show(t),
                Bg::UpdateAllDone(ok, total, stopped) => {
                    let pl = |n: usize| if n > 1 { "s" } else { "" };
                    self.toast.show(if stopped { format!("Mises à jour arrêtées : {ok} faite{}.", pl(ok)) }
                        else { format!("{ok} mise{} à jour sur {total}{}.", pl(ok), if ok < total { " (voir les erreurs sur les fiches)" } else { "" }) });
                }
            }
        }
        if let Some((sys, rx)) = &self.pending_folder {
            if let Ok(v) = rx.try_recv() {
                let sys = sys.clone();
                self.pending_folder = None;
                if let Some(p) = v.into_iter().next() { self.settings.set(&format!("folder.{sys}"), p.to_string_lossy().to_string()); self.rescan(ctx); }
            } else { ctx.request_repaint_after(std::time::Duration::from_millis(250)); }
        }
        if !self.downloads.lock().unwrap().is_empty() || self.updating.lock().unwrap().is_some() { ctx.request_repaint_after(std::time::Duration::from_millis(150)); }
        // Revenir dans la fenêtre relit les dossiers.
        let focused = ctx.input(|i| i.focused);
        if focused && !self.was_focused { self.rescan(ctx); }
        self.was_focused = focused;
    }

    fn run_test_script(&mut self, ctx: &egui::Context) {
        if self.test_done || self.apps.is_empty() { return; }
        self.test_done = true;
        if let Ok(id) = std::env::var("RECOMPS_TEST_SELECT") { self.selection = Some(id.clone()); self.load_notes(ctx, &id); }
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.images.begin_frame(ctx);
        self.pump(ctx);
        self.run_test_script(ctx);
        crate::views::show(self, ctx);
        self.toast.ui(ctx, &self.p);
        let p = self.p;
        self.update.ui(ctx, &mut self.settings, &p);
        self.test.ui(ctx);
    }
    fn on_exit(&mut self, _gl: Option<&egui_glow::glow::Context>) { self.update.relaunch_if_needed(); }
}

pub fn urlenc(s: &str) -> String {
    s.bytes().map(|b| if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") }).collect()
}
fn path_enc(s: &str) -> String { urlenc(s).replace("%2F", "/") }

/// Fichiers et dossiers de la bibliothèque, jusqu'à 3 niveaux.
fn list_files(root: &Path) -> Vec<(String, PathBuf, i64)> {
    let mut out = vec![];
    fn walk(dir: &Path, level: u32, out: &mut Vec<(String, PathBuf, i64)>) {
        let Ok(rd) = std::fs::read_dir(dir) else { return };
        for e in rd.flatten() {
            let n = e.file_name().to_string_lossy().to_string();
            if n.starts_with('.') { continue; }
            let p = e.path();
            let Ok(m) = std::fs::metadata(&p) else { continue };
            let d = m.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_millis() as i64).unwrap_or(0);
            out.push((n.clone(), p.clone(), d));
            if m.is_dir() && level < 3 && !n.ends_with(".app") { walk(&p, level + 1, out); }
        }
    }
    walk(root, 1, &mut out);
    out
}

/// Le fichier à télécharger : (adresse, nom, empreinte SHA-256 éventuelle).
fn resolve(a: &Recomp, sys: &str) -> Result<(String, String, Option<String>), String> {
    let (Some(repo), Some(pattern)) = (a.repo.as_deref(), a.pattern(sys)) else { return Err(format!("pas de fichier pour {}", model::sys_label(sys))) };
    let f = a.files.get(sys);
    let ag = agent();
    if a.gitlab() {
        // GitLab : les fichiers d'une release sont des liens ; celui du nom exact, sinon celui du modèle.
        let rel = a.tag.as_deref().map(|t| format!("releases/{}", urlenc(t))).unwrap_or("releases/permalink/latest".into());
        let mut r = ag.get(&format!("https://gitlab.com/api/v4/projects/{}/{rel}", urlenc(repo))).call().map_err(|e| e.to_string())?;
        if r.status().as_u16() != 200 { return Err(format!("release introuvable sur GitLab (code {})", r.status().as_u16())); }
        let v: Value = r.body_mut().read_json().map_err(|e| e.to_string())?;
        let links = v["assets"]["links"].as_array().cloned().unwrap_or_default();
        let name_of = |l: &Value| l["name"].as_str().unwrap_or("").to_string();
        let exact = f.and_then(|f| f.name.as_ref()).and_then(|n| links.iter().find(|l| &name_of(l) == n));
        let by_pattern = links.iter().find(|l| model::glob_match(pattern, &name_of(l), false).0);
        let by_bare = links.iter().find(|l| model::glob_match(pattern, &name_of(l), true).0);
        let hit = exact.or(by_pattern).or(by_bare).ok_or(format!("aucun fichier « {pattern} » dans la release GitLab"))?;
        let mut name = name_of(hit);
        if exact.is_none() && by_pattern.is_none() { if let Some(e) = model::archive_ext(pattern) { name += e; } }
        let url = hit["direct_asset_url"].as_str().or(hit["url"].as_str()).unwrap_or("").to_string();
        let sha = if f.and_then(|f| f.name.as_deref()) == Some(name_of(hit).as_str()) { f.and_then(|f| f.sha256.clone()) } else { None };
        return Ok((url, name, sha));
    }
    let direct = |tag: &str, name: &str| format!("https://github.com/{repo}/releases/download/{}/{}", path_enc(tag), path_enc(name));
    if let (Some(tag), Some(n)) = (a.tag.as_deref(), f.and_then(|f| f.name.as_deref())) { return Ok((direct(tag, n), n.into(), f.and_then(|f| f.sha256.clone()))); }
    if let Some(tag) = a.tag.as_deref() { if !pattern.contains('*') { return Ok((direct(tag, pattern), pattern.into(), None)); } }
    // Modèle avec « * » : on cherche le fichier dans la release (API GitHub, sans compte : 60 requêtes / heure).
    let api = format!("https://api.github.com/repos/{repo}/releases/{}", a.tag.as_deref().map(|t| format!("tags/{}", path_enc(t))).unwrap_or("latest".into()));
    let mut r = ag.get(&api).header("Accept", "application/vnd.github+json").call().map_err(|e| e.to_string())?;
    if r.status().as_u16() != 200 { return Err(format!("release introuvable sur GitHub (code {})", r.status().as_u16())); }
    let v: Value = r.body_mut().read_json().map_err(|e| e.to_string())?;
    let hit = v["assets"].as_array().and_then(|a| a.iter().find(|x| model::glob_match(pattern, x["name"].as_str().unwrap_or(""), false).0).cloned())
        .ok_or(format!("aucun fichier « {pattern} » dans la release"))?;
    Ok((hit["browser_download_url"].as_str().unwrap_or("").into(), hit["name"].as_str().unwrap_or("").into(), None))
}

fn perform(a: &Recomp, sys: &str, root: &Path, dls: &Arc<Mutex<HashMap<String, Dl>>>, k: &str, cancel: &AtomicBool, ctx: &egui::Context) -> Result<PathBuf, String> {
    let (url, name, sha) = resolve(a, sys)?;
    let resp = agent().get(&url).call().map_err(|e| e.to_string())?;
    let code = resp.status().as_u16();
    if code != 200 { return Err(format!("téléchargement refusé (code {code})")); }
    let total = resp.headers().get("content-length").and_then(|v| v.to_str().ok()).and_then(|s| s.parse().ok()).unwrap_or(0);
    let tmp = std::env::temp_dir().join(format!("recomps-{}-{}", std::process::id(), sys::now_ms()));
    let mut out = std::fs::File::create(&tmp).map_err(|e| e.to_string())?;
    let mut reader = resp.into_body().into_reader();
    let mut hash = Sha256::new();
    let mut buf = vec![0u8; 1 << 16];
    let mut done = 0u64;
    let mut last = std::time::Instant::now();
    loop {
        if cancel.load(Ordering::SeqCst) { drop(out); let _ = std::fs::remove_file(&tmp); return Err("annulé".into()); }
        let n = reader.read(&mut buf).map_err(|e| { let _ = std::fs::remove_file(&tmp); e.to_string() })?;
        if n == 0 { break; }
        hash.update(&buf[..n]);
        out.write_all(&buf[..n]).map_err(|e| e.to_string())?;
        done += n as u64;
        if last.elapsed().as_millis() > 100 { dls.lock().unwrap().insert(k.to_string(), Dl { done, total }); ctx.request_repaint(); last = std::time::Instant::now(); }
    }
    drop(out);
    let hex: String = hash.finalize().iter().map(|b| format!("{b:02x}")).collect();
    if let Some(s) = sha { if hex != s.to_lowercase() { let _ = std::fs::remove_file(&tmp); return Err("le fichier reçu ne correspond pas à l'empreinte SHA-256 du catalogue".into()); } }
    let r = place(a, sys, &tmp, &name, root);
    let _ = std::fs::remove_file(&tmp);
    r
}

fn run(cmd: &str, args: &[&str]) -> Result<(), String> {
    let o = sys::clean_command(cmd).args(args).output().map_err(|e| format!("{cmd} : {e}"))?;
    if o.status.success() { Ok(()) } else { Err(format!("{cmd} : {}", String::from_utf8_lossy(&o.stderr).chars().rev().take(200).collect::<String>().chars().rev().collect::<String>())) }
}

/// Décompresse une archive dans `dir` avec les outils du système.
fn extract(archive: &Path, name: &str, dir: &Path) -> Result<bool, String> {
    let n = name.to_lowercase();
    let (a, d) = (archive.to_string_lossy().to_string(), dir.to_string_lossy().to_string());
    if n.ends_with(".zip") { if run("unzip", &["-q", "-o", &a, "-d", &d]).is_err() { run("7z", &["x", "-y", &format!("-o{d}"), &a])?; } }
    else if [".tar", ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tgz"].iter().any(|e| n.ends_with(e)) { run("tar", &["-xf", &a, "-C", &d])?; }
    else if n.ends_with(".7z") { run("7z", &["x", "-y", &format!("-o{d}"), &a])?; }
    else { return Ok(false); }
    Ok(true)
}

fn is_elf(p: &Path) -> bool {
    let mut b = [0u8; 4];
    std::fs::File::open(p).and_then(|mut f| f.read_exact(&mut b)).map(|_| b == [0x7f, b'E', b'L', b'F']).unwrap_or(false)
}

/// Rend exécutables les programmes d'un jeu décompressé (un zip perd souvent ce droit).
fn mark_executables(dir: &Path, depth: u32) {
    use std::os::unix::fs::PermissionsExt;
    if depth > 4 { return; }
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        if p.is_dir() { mark_executables(&p, depth + 1); continue; }
        let n = p.to_string_lossy().to_lowercase();
        if n.ends_with(".sh") || n.ends_with(".x86_64") || n.ends_with(".appimage") || is_elf(&p) {
            if let Ok(m) = std::fs::metadata(&p) { let _ = std::fs::set_permissions(&p, std::fs::Permissions::from_mode(m.permissions().mode() | 0o755)); }
        }
    }
}

/// Pose le fichier téléchargé dans le dossier du système, et rend le chemin final.
fn place(a: &Recomp, sys: &str, tmp: &Path, name: &str, root: &Path) -> Result<PathBuf, String> {
    let dir = root.join(model::safe(&a.name));
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let ext = model::archive_ext(name);
    if sys == "linux" && ext.is_some() && ext != Some(".appimage") {
        // Linux : le jeu est sorti de son archive, prêt à lancer.
        let stem = &name[..name.len() - ext.unwrap().len()];
        let work = root.join(format!(".recomps-{}", sys::now_ms()));
        std::fs::create_dir_all(&work).map_err(|e| e.to_string())?;
        let r = (|| -> Result<Option<PathBuf>, String> {
            if !extract(tmp, name, &work)? { return Ok(None); }
            let inside: Vec<PathBuf> = std::fs::read_dir(&work).map_err(|e| e.to_string())?.flatten().map(|e| e.path()).filter(|p| !p.file_name().unwrap().to_string_lossy().starts_with('.')).collect();
            let src = if inside.len() == 1 && inside[0].is_dir() { inside[0].clone() } else { work.clone() };
            let dest = dir.join(stem);
            if dest.exists() { sys::trash(&dest)?; }
            std::fs::rename(&src, &dest).map_err(|e| e.to_string())?;
            mark_executables(&dest, 0);
            Ok(Some(dest))
        })();
        let _ = std::fs::remove_dir_all(&work);
        if let Some(d) = r? { return Ok(d); }
    }
    let dest = dir.join(name);
    if dest.exists() { sys::trash(&dest)?; }
    if std::fs::rename(tmp, &dest).is_err() { std::fs::copy(tmp, &dest).map_err(|e| e.to_string())?; }
    if ext == Some(".appimage") {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&dest, std::fs::Permissions::from_mode(0o755));
    }
    Ok(dest)
}

/// Le programme qui démarre le jeu, dans le dossier décompressé.
fn find_launcher(dir: &Path, game: &str) -> Option<PathBuf> {
    let norm = |s: &str| s.to_lowercase().chars().filter(|c| c.is_ascii_alphanumeric()).collect::<String>();
    let want = norm(game);
    let mut found: Vec<(i32, PathBuf)> = vec![];
    fn walk(d: &Path, depth: i32, want: &str, found: &mut Vec<(i32, PathBuf)>, norm: &dyn Fn(&str) -> String) {
        if depth > 3 { return; }
        let Ok(rd) = std::fs::read_dir(d) else { return };
        for e in rd.flatten() {
            let p = e.path();
            let n = e.file_name().to_string_lossy().to_string();
            if p.is_dir() { if !["lib", "lib64", "libs", "share", "doc", "docs"].contains(&n.to_lowercase().as_str()) { walk(&p, depth + 1, want, found, norm); } continue; }
            let l = n.to_lowercase();
            if l.contains(".so") { continue; }
            let appimage = l.ends_with(".appimage");
            if !appimage && !is_elf(&p) && !l.ends_with(".sh") && !l.ends_with(".x86_64") { continue; }
            let stem = norm(l.trim_end_matches(".appimage").trim_end_matches(".sh").trim_end_matches(".x86_64"));
            let mut score = 10 - depth * 2;
            if appimage { score += 20; }
            if !stem.is_empty() && !want.is_empty() && (want.contains(&stem) || stem.contains(want)) { score += 15; }
            if l.contains("x86_64") || l.contains("linux") { score += 3; }
            if ["crash", "handler", "helper", "update", "uninst", "setup", "config"].iter().any(|w| l.contains(w)) { score -= 30; }
            found.push((score, p));
        }
    }
    walk(dir, 0, &want, &mut found, &norm);
    found.sort_by(|a, b| b.0.cmp(&a.0));
    found.into_iter().next().map(|x| x.1)
}
