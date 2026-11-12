//! La logique de Recomps qui ne touche ni au disque ni au réseau : catalogue,
//! versions, modèles de fichiers, état de chaque jeu, filtres et tri.
//! Traduction directe de main.swift.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;

pub const SYSTEMS: &[(&str, &str, &str)] = &[("linux", "Linux", "linux"), ("windows", "Windows", "windows"), ("macos", "Mac", "apple")];
pub fn sys_label(id: &str) -> &'static str { SYSTEMS.iter().find(|s| s.0 == id).map(|s| s.1).unwrap_or("?") }
pub fn sys_icon(id: &str) -> &'static str { SYSTEMS.iter().find(|s| s.0 == id).map(|s| s.2).unwrap_or("question") }

pub fn genre_fr(g: &str) -> Option<&'static str> {
    Some(match g {
        "action" => "Action", "platformer" => "Plateformes", "fighting" => "Combat", "rpg" => "RPG", "racing" => "Course",
        "shooter" => "Tir", "adventure" => "Aventure", "sports" => "Sport", "puzzle" => "Réflexion", "other" => "Autre", _ => return None,
    })
}

pub const SCOPES: &[(&str, &str, &str)] = &[("all", "Tous les jeux", "grid"), ("mine", "Mes jeux", "folder"), ("updates", "Mises à jour", "downCircle"),
    ("new", "Nouvelles versions", "sparkles"), ("soon", "Bientôt", "clock")];
pub const SORTS: &[(&str, &str)] = &[("name", "Nom"), ("released", "Dernière version"), ("added", "Ajout au catalogue"), ("popular", "Popularité")];

#[derive(Clone, Debug, Default, Deserialize)]
pub struct FileInfo { pub name: Option<String>, pub sha256: Option<String>, pub scan: Option<String> }

#[derive(Clone, Debug, Default, Deserialize)]
pub struct About { pub genres: Option<Vec<String>>, pub summary: Option<String> }

/// Un jeu du catalogue. Les champs inconnus ou mal formés sont ignorés plutôt
/// que de rendre tout le catalogue illisible.
#[derive(Clone, Debug, Default)]
pub struct Recomp {
    pub id: String, pub name: String, pub game: Option<String>, pub origin: Option<String>, pub repo: Option<String>,
    pub version: Option<String>, pub released: Option<String>, pub size: Option<String>, pub downloads: Option<i64>,
    pub blurb: Option<String>, pub needs: Option<String>, pub author: Option<String>, pub icon: Option<String>, pub cover: Option<String>,
    pub hero: Option<String>, pub systems: Vec<String>, pub assets: HashMap<String, String>, pub tags: Vec<String>, pub added: Option<String>,
    pub features: Vec<String>, pub genre: Option<String>, pub tag: Option<String>, pub files: HashMap<String, FileInfo>, pub about: About,
    pub soon: bool, pub setup_steps: Vec<String>, pub license: Option<String>, pub host: Option<String>, pub status: Option<String>,
    pub status_note: Option<String>, pub archived: bool, pub report_url: Option<String>,
}

fn st(v: &Value, k: &str) -> Option<String> { v.get(k).and_then(|x| x.as_str()).map(String::from) }
fn strs(v: &Value, k: &str) -> Vec<String> { v.get(k).and_then(|x| x.as_array()).map(|a| a.iter().filter_map(|s| s.as_str().map(String::from)).collect()).unwrap_or_default() }

impl Recomp {
    pub fn from_json(v: &Value) -> Option<Recomp> {
        let id = st(v, "id")?;
        let name = st(v, "name")?;
        // « assets » est un objet {système: modèle} ou, pour un jeu à venir, une liste vide.
        let assets = v.get("assets").and_then(|a| a.as_object()).map(|o| o.iter().filter_map(|(k, x)| x.as_str().map(|s| (k.clone(), s.to_string()))).collect()).unwrap_or_default();
        let files = v.get("files").and_then(|f| f.as_object()).map(|o| o.iter().filter_map(|(k, x)| serde_json::from_value(x.clone()).ok().map(|f| (k.clone(), f))).collect()).unwrap_or_default();
        Some(Recomp {
            id, name, game: st(v, "game"), origin: st(v, "origin"), repo: st(v, "repo"), version: st(v, "version"), released: st(v, "released"),
            size: st(v, "size"), downloads: v.get("downloads").and_then(|x| x.as_i64()), blurb: st(v, "blurb"), needs: st(v, "needs"),
            author: st(v, "author"), icon: st(v, "icon"), cover: st(v, "cover"), hero: st(v, "hero"), systems: strs(v, "systems"), assets,
            tags: strs(v, "tags"), added: st(v, "added"), features: strs(v, "features"), genre: st(v, "genre"), tag: st(v, "tag"), files,
            about: v.get("about").and_then(|a| serde_json::from_value(a.clone()).ok()).unwrap_or_default(),
            soon: v.get("soon").and_then(|x| x.as_bool()).unwrap_or(false), setup_steps: strs(v, "setup_steps"), license: st(v, "license"),
            host: st(v, "host"), status: st(v, "status"), status_note: st(v, "status_note"), archived: v.get("archived").and_then(|x| x.as_bool()).unwrap_or(false),
            report_url: st(v, "report_url"),
        })
    }
    pub fn pattern(&self, sys: &str) -> Option<&str> { self.assets.get(sys).map(|s| s.as_str()) }
    pub fn sys_list(&self) -> Vec<&'static str> {
        SYSTEMS.iter().map(|s| s.0).filter(|s| self.systems.iter().any(|x| x == s) && self.pattern(s).is_some()).collect()
    }
    pub fn is_soon(&self) -> bool { self.soon || self.tag.is_none() || self.sys_list().is_empty() }
    pub fn gitlab(&self) -> bool { self.host.as_deref() == Some("gitlab") }
}

pub struct Catalog { pub apps: Vec<Recomp>, pub origins: HashMap<String, String>, pub updated: Option<String> }

pub fn parse_catalog(text: &str) -> Result<Catalog, String> {
    let v: Value = serde_json::from_str(text).map_err(|e| e.to_string())?;
    let apps = v.get("apps").and_then(|a| a.as_array()).ok_or("pas de liste « apps »")?.iter().filter_map(Recomp::from_json).collect();
    let mut origins = HashMap::new();
    for o in v.get("origins").and_then(|a| a.as_array()).cloned().unwrap_or_default() {
        if let (Some(id), Some(n)) = (st(&o, "id"), st(&o, "name")) { origins.entry(id).or_insert(n); }
    }
    Ok(Catalog { apps, origins, updated: st(&v, "updated") })
}

// ── Versions et modèles de fichiers ───────────────────────────────────────

/// 1.0.0 = 1.0 = 1, « v1.2 » = « 1.2 ».
pub fn norm(v: Option<&str>) -> Option<String> {
    let mut s = v?.trim().to_lowercase();
    if s.is_empty() { return None; }
    if s.starts_with('v') && s.chars().nth(1).map(|c| c.is_ascii_digit()).unwrap_or(false) { s.remove(0); }
    let mut parts: Vec<&str> = s.split('.').collect();
    while parts.len() > 1 && parts.last() == Some(&"0") { parts.pop(); }
    Some(parts.join("."))
}

pub const ARCHIVE_EXTS: &[&str] = &[".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".zip", ".7z", ".dmg", ".tar", ".appimage", ".exe", ".pkg", ".tgz"];
pub fn archive_ext(name: &str) -> Option<&'static str> { let n = name.to_lowercase(); ARCHIVE_EXTS.iter().copied().find(|e| n.ends_with(e)) }

/// Modèle « Nom-*-macOS.zip » : le « * » capture la version (la plus courte
/// possible, comme `(.+?)`). Rend (correspond, première capture). Sans casse.
pub fn glob_match(glob: &str, name: &str, strip_ext: bool) -> (bool, Option<String>) {
    let mut g = glob.to_lowercase();
    if strip_ext { if let Some(e) = archive_ext(&g) { g.truncate(g.len() - e.len()); } }
    let lower = name.to_lowercase();
    // La casse ne change pas la longueur des noms de fichiers ASCII ; sinon on renonce à la capture.
    let same_len = lower.len() == name.len();
    let parts: Vec<&str> = g.split('*').collect();
    fn go(parts: &[&str], s: &str, at: usize, caps: &mut Vec<(usize, usize)>) -> bool {
        let Some(rest) = s.strip_prefix(parts[0]) else { return false };
        if parts.len() == 1 { return rest.is_empty(); }
        let base = at + parts[0].len();
        for (i, _) in rest.char_indices().skip(1).chain(std::iter::once((rest.len(), ' '))) {
            if i == 0 { continue; }
            caps.push((base, base + i));
            if go(&parts[1..], &rest[i..], base + i, caps) { return true; }
            caps.pop();
        }
        false
    }
    let mut caps = vec![];
    if !go(&parts, &lower, 0, &mut caps) { return (false, None); }
    let cap = caps.first().map(|&(a, b)| if same_len { name[a..b].to_string() } else { lower[a..b].to_string() });
    (true, cap)
}

pub fn iso_day(s: Option<&str>) -> Option<i64> {
    let s = s?;
    if s.len() < 10 { return None; }
    let d = chrono::NaiveDate::parse_from_str(&s[..10], "%Y-%m-%d").ok()?;
    Some(d.and_hms_opt(0, 0, 0)?.and_local_timezone(chrono::Local).single()?.timestamp_millis())
}

pub fn day(s: Option<&str>) -> String {
    let Some(t) = s.and_then(|s| chrono::NaiveDate::parse_from_str(s.get(..10)?, "%Y-%m-%d").ok()) else { return String::new() };
    const M: [&str; 12] = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."];
    use chrono::Datelike;
    format!("{} {} {}", t.day(), M[t.month0() as usize], t.year())
}

// ── État d'un jeu ─────────────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub enum Status { None = 0, UpToDate = 1, Unknown = 2, Outdated = 3 }

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Installed { pub tag: Option<String>, pub version: Option<String>, pub file: String, pub date: i64 }

#[derive(Clone, Debug)]
pub struct Found { pub path: std::path::PathBuf, pub version: Option<String>, pub date: i64 }

pub type InstalledMap = HashMap<String, HashMap<String, Installed>>;
pub type FoundMap = HashMap<String, HashMap<String, Found>>;

pub struct State<'a> { pub installed: &'a InstalledMap, pub found: &'a FoundMap }

impl State<'_> {
    pub fn inst(&self, a: &Recomp, sys: &str) -> Option<&Installed> {
        self.installed.get(&a.id).and_then(|m| m.get(sys)).filter(|i| std::path::Path::new(&i.file).exists())
    }

    pub fn status(&self, a: &Recomp, sys: &str) -> Status {
        if let Some(i) = self.inst(a, sys) {
            return if norm(i.tag.as_deref()) == norm(a.tag.as_deref()) || norm(i.version.as_deref()) == norm(a.version.as_deref()) { Status::UpToDate } else { Status::Outdated };
        }
        let Some(f) = self.found.get(&a.id).and_then(|m| m.get(sys)) else { return Status::None };
        let rel = iso_day(a.released.as_deref());
        if let Some(v) = norm(f.version.as_deref()) {
            if Some(&v) == norm(a.version.as_deref()).as_ref() || Some(&v) == norm(a.tag.as_deref()).as_ref() { return Status::UpToDate; }
            if let Some(r) = rel { if f.date < r { return Status::Outdated; } }
            return Status::Outdated;
        }
        // Nom sans version : on compare à la date de la release.
        match rel { None => Status::Unknown, Some(r) => if f.date >= r { Status::UpToDate } else { Status::Outdated } }
    }

    pub fn overall(&self, a: &Recomp) -> Status { a.sys_list().iter().map(|s| self.status(a, s)).max().unwrap_or(Status::None) }

    pub fn local_path(&self, a: &Recomp, sys: &str) -> Option<std::path::PathBuf> {
        if let Some(i) = self.inst(a, sys) { return Some(i.file.clone().into()); }
        self.found.get(&a.id).and_then(|m| m.get(sys)).map(|f| f.path.clone())
    }

    pub fn in_scope(&self, a: &Recomp, scope: &str, now: i64) -> bool {
        match scope {
            "mine" => self.overall(a) != Status::None,
            "updates" => self.overall(a) == Status::Outdated,
            "soon" => a.is_soon(),
            "new" => iso_day(a.released.as_deref()).map(|d| !a.is_soon() && d > now - 14 * 86_400_000).unwrap_or(false),
            _ => !a.is_soon(),
        }
    }

    /// Ce qui a une mise à jour : chaque jeu × système marqué « Mise à jour ».
    pub fn outdated(&self, apps: &[Recomp]) -> Vec<(usize, &'static str)> {
        let mut out = vec![];
        for (i, a) in apps.iter().enumerate() { for s in a.sys_list() { if self.status(a, s) == Status::Outdated { out.push((i, s)); } } }
        out
    }

    /// Le système du bouton rapide : celui qui a une mise à jour, sinon Linux, sinon le premier pas à jour.
    pub fn preferred(&self, a: &Recomp) -> Option<&'static str> {
        let l = a.sys_list();
        l.iter().copied().find(|s| self.status(a, s) == Status::Outdated)
            .or_else(|| if l.contains(&"linux") && self.status(a, "linux") != Status::UpToDate { Some("linux") } else { None })
            .or_else(|| l.iter().copied().find(|s| self.status(a, s) != Status::UpToDate))
    }
}

fn fold(s: &str) -> String {
    use unicode_normalization::UnicodeNormalization;
    s.nfd().filter(|c| !('\u{300}'..='\u{36f}').contains(c)).collect::<String>().to_lowercase()
}

pub struct Filter<'a> { pub scope: &'a str, pub console: &'a str, pub genre: &'a str, pub system: &'a str, pub search: &'a str, pub sort: &'a str }

pub fn filtered(apps: &[Recomp], f: &Filter, s: &State) -> Vec<usize> {
    let q = fold(f.search.trim());
    let now = chrono::Utc::now().timestamp_millis();
    let mut list: Vec<usize> = (0..apps.len()).filter(|&i| {
        let a = &apps[i];
        s.in_scope(a, f.scope, now)
            && (f.console.is_empty() || a.origin.as_deref() == Some(f.console))
            && (f.genre.is_empty() || a.genre.as_deref() == Some(f.genre))
            && (f.system.is_empty() || a.systems.iter().any(|x| x == f.system))
            && (q.is_empty() || fold(&[a.name.as_str(), a.game.as_deref().unwrap_or(""), a.author.as_deref().unwrap_or(""),
                &a.about.genres.clone().unwrap_or_default().join(" "), &a.tags.join(" ")].join(" ")).contains(&q))
    }).collect();
    match f.sort {
        "released" => list.sort_by(|&x, &y| apps[y].released.cmp(&apps[x].released)),
        "added" => list.sort_by(|&x, &y| apps[y].added.cmp(&apps[x].added)),
        "popular" => list.sort_by(|&x, &y| apps[y].downloads.unwrap_or(0).cmp(&apps[x].downloads.unwrap_or(0))),
        _ => list.sort_by(|&x, &y| fold(&apps[x].name).cmp(&fold(&apps[y].name))),
    }
    list
}

pub fn safe(s: &str) -> String { s.replace('/', "-").replace(':', " -").trim().to_string() }

/// Une ligne de notes de version, mise en forme : (texte, gras).
pub fn notes_lines(md: &str) -> Vec<(String, bool)> {
    let mut lines: Vec<(String, bool)> = vec![];
    let tag = |s: &str| -> String { let mut out = String::new(); let mut inside = false; for c in s.chars() { if c == '<' { inside = true } else if c == '>' { inside = false } else if !inside { out.push(c) } } out };
    for raw in md.replace('\r', "").lines() {
        let mut l = tag(raw).trim().to_string();
        if l.starts_with("![") || l.starts_with("[![") { continue; }
        while let Some(r) = l.strip_prefix('>') { l = r.trim().to_string(); }
        if l.starts_with("[!") && l.ends_with(']') { continue; }
        let mut bold = false;
        if l.starts_with('#') { l = l.trim_start_matches('#').trim().replace("**", ""); bold = !l.is_empty(); }
        else if let Some(r) = l.strip_prefix("- ").or_else(|| l.strip_prefix("* ")).or_else(|| l.strip_prefix("+ ")) { l = format!("•  {r}"); }
        // Les liens Markdown gardent leur texte ; le gras et le code perdent leurs marques.
        let mut t = String::new();
        let mut rest = l.as_str();
        while let Some(i) = rest.find('[') {
            t.push_str(&rest[..i]);
            let after = &rest[i + 1..];
            match (after.find("]("), after.find(')')) {
                (Some(j), Some(k)) if j < k => { t.push_str(&after[..j]); rest = &after[k + 1..]; }
                _ => { t.push('['); rest = after; }
            }
        }
        t.push_str(rest);
        let t = t.replace("**", "").replace('`', "");
        if t.is_empty() && lines.last().map(|x| x.0.is_empty()).unwrap_or(true) { continue; }
        lines.push((t, bold));
    }
    while lines.last().map(|x| x.0.is_empty()).unwrap_or(false) { lines.pop(); }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn versions() {
        assert_eq!(norm(Some("v1.2.0")).as_deref(), Some("1.2"));
        assert_eq!(norm(Some("1.0.0")).as_deref(), Some("1"));
        assert_eq!(norm(Some(" V2 ")).as_deref(), Some("2"));
        assert_eq!(norm(Some("version")).as_deref(), Some("version"));
        assert_eq!(norm(Some("")), None);
    }
    #[test]
    fn globs() {
        assert_eq!(glob_match("Zelda64Recomp-*-Linux.tar.gz", "Zelda64Recomp-v1.2.0-Linux.tar.gz", false), (true, Some("v1.2.0".into())));
        assert_eq!(glob_match("Zelda64Recomp-*-Linux.tar.gz", "Zelda64Recomp-v1.2.0-Linux", true).1.as_deref(), Some("v1.2.0"));
        assert!(!glob_match("Zelda64Recomp-*-Linux.tar.gz", "autre.zip", false).0);
        assert!(glob_match("DOOM3DO-x86_64.AppImage", "doom3do-x86_64.appimage", false).0);
        assert_eq!(archive_ext("Jeu-1.0.tar.gz"), Some(".tar.gz"));
        assert_eq!(archive_ext("Jeu.AppImage"), Some(".appimage"));
    }
    fn game() -> Recomp {
        Recomp { id: "g".into(), name: "Jeu".into(), tag: Some("v1.2".into()), version: Some("1.2".into()), released: Some("2026-10-01".into()),
            systems: vec!["linux".into(), "windows".into()], assets: [("linux".to_string(), "Jeu-*-Linux.zip".to_string()), ("windows".to_string(), "Jeu-*-Windows.zip".to_string())].into(), ..Default::default() }
    }
    #[test]
    fn statuses() {
        let a = game();
        let tmp = std::env::temp_dir().join("recomps-test-file");
        std::fs::write(&tmp, "x").unwrap();
        let file = tmp.to_string_lossy().to_string();
        let mut inst: InstalledMap = HashMap::new();
        inst.entry("g".into()).or_default().insert("linux".into(), Installed { tag: Some("v1.2".into()), version: None, file: file.clone(), date: 0 });
        let found = FoundMap::new();
        let s = State { installed: &inst, found: &found };
        assert_eq!(s.status(&a, "linux"), Status::UpToDate);
        assert_eq!(s.preferred(&a), Some("windows"));
        let rel = iso_day(Some("2026-10-01")).unwrap();
        let mut f = FoundMap::new();
        f.entry("g".into()).or_default().insert("linux".into(), Found { path: "/x".into(), version: None, date: rel - 1000 });
        let s2 = State { installed: &HashMap::new(), found: &f };
        assert_eq!(s2.status(&a, "linux"), Status::Outdated);
        assert!(Recomp { tag: None, ..game() }.is_soon());
    }
    #[test]
    fn notes() {
        let n = notes_lines("## Nouveau\n- **Rapide** [lien](https://x)\n![img](x)");
        assert_eq!(n, vec![("Nouveau".into(), true), ("•  Rapide lien".into(), false)]);
    }
}
