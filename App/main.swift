// Recomps : catalogue des recomps PC de recomplauncher.com, avec recherche, filtres, téléchargement
// (Windows, Mac, Linux) et suivi des versions présentes dans un dossier de bibliothèque.
//
// Données : https://recomplauncher.com/pc-catalog.json (le fichier que le site lit lui-même, mis en cache avec son ETag).
// Fichiers : releases GitHub de chaque jeu (nom exact du catalogue, sinon modèle « assets » cherché dans la release).

import SwiftUI
import AppKit
import CryptoKit

// MARK: - Catalogue

let catalogURL = URL(string: "https://recomplauncher.com/pc-catalog.json")!
let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Recomps")

enum Sys: String, CaseIterable, Identifiable, Codable {
    case macos, windows, linux
    var id: String { rawValue }
    var label: String { ["macos": "Mac", "windows": "Windows", "linux": "Linux"][rawValue]! }
    var symbol: String { ["macos": "apple.logo", "windows": "pc", "linux": "terminal"][rawValue]! }
}

struct Origin: Decodable { let id: String; let name: String }
struct FileInfo: Decodable { let name: String?; let sha256: String?; let scan: String? }
struct About: Decodable { let genres: [String]?; let released: String?; let developer: String?; let summary: String? }

/// « assets » est un objet {système: modèle} ou, pour un jeu à venir, une liste vide.
struct Assets: Decodable {
    var map: [String: String] = [:]
    init(from d: Decoder) throws { map = (try? d.singleValueContainer().decode([String: String].self)) ?? [:] }
}

struct Recomp: Decodable, Identifiable {
    let id: String
    let name: String
    let game: String?
    let origin: String?
    let repo: String?
    let version: String?
    let released: String?
    let size: String?
    let downloads: Int?
    let stars: Int?
    let blurb: String?
    let needs: String?
    let author: String?
    let icon: String?
    let cover: String?
    let hero: String?
    let systems: [String]?
    let assets: Assets?
    let tags: [String]?
    let added: String?
    let features: [String]?
    let genre: String?
    let tag: String?
    let files: [String: FileInfo]?
    let about: About?
    let soon: Bool?
    let setup_steps: [String]?
    let license: String?

    var sysList: [Sys] { Sys.allCases.filter { (systems ?? []).contains($0.rawValue) && pattern($0) != nil } }
    func pattern(_ s: Sys) -> String? { assets?.map[s.rawValue] }
    var isSoon: Bool { soon == true || tag == nil || sysList.isEmpty }
}

struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from d: Decoder) throws { value = try? T(from: d) }
}

struct Catalog: Decodable {
    let updated: String?
    let apps: [Recomp]
    let origins: [Origin]
    enum K: String, CodingKey { case updated, apps, origins }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        updated = try? c.decode(String.self, forKey: .updated)
        apps = (try c.decode([Failable<Recomp>].self, forKey: .apps)).compactMap(\.value)
        origins = (try? c.decode([Origin].self, forKey: .origins)) ?? []
    }
}

let genreFR = ["action": "Action", "platformer": "Plateformes", "fighting": "Combat", "rpg": "RPG", "racing": "Course",
               "shooter": "Tir", "adventure": "Aventure", "sports": "Sport", "puzzle": "Réflexion", "other": "Autre"]

// MARK: - Versions présentes

struct Release: Decodable, Identifiable {
    let id: Int
    let tag_name: String
    let name: String?
    let body: String?
    let published_at: Date?
    let html_url: String?
    let prerelease: Bool
    let draft: Bool
}

struct Installed: Codable { var tag: String?; var version: String?; var file: String; var date: Date }

enum Status: Int, Comparable {
    case none = 0, upToDate, unknown, outdated
    static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
}

struct Local { var path: URL; var version: String?; var date: Date; var isApp = false }

func norm(_ v: String?) -> String? {
    guard var v = v?.trimmingCharacters(in: .whitespaces).lowercased(), !v.isEmpty else { return nil }
    if v.hasPrefix("v"), v.dropFirst().first?.isNumber == true { v.removeFirst() }
    var parts = v.split(separator: ".", omittingEmptySubsequences: false)   // 1.0.0 = 1.0 = 1
    while parts.count > 1, parts.last == "0" { parts.removeLast() }
    return parts.joined(separator: ".")
}

/// Modèle « Nom-*-macOS.zip » → expression régulière ; le « * » capture la version.
func globRegex(_ glob: String, stripExt: Bool = false) -> NSRegularExpression? {
    var g = glob
    if stripExt {
        for e in [".tar.gz", ".tar.xz", ".zip", ".7z", ".dmg", ".tar", ".AppImage", ".exe"] where g.lowercased().hasSuffix(e.lowercased()) {
            g = String(g.dropLast(e.count)); break
        }
    }
    let parts = g.components(separatedBy: "*").map(NSRegularExpression.escapedPattern(for:))
    return try? NSRegularExpression(pattern: "^" + parts.joined(separator: "(.+?)") + "$", options: [.caseInsensitive])
}

func firstCapture(_ re: NSRegularExpression, _ s: String) -> (matched: Bool, capture: String?) {
    guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return (false, nil) }
    if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) { return (true, String(s[r])) }
    return (true, nil)
}

let isoDay: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
let shortDay: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: "fr_FR"); return f }()
func day(_ s: String?) -> String { s.flatMap(isoDay.date(from:)).map(shortDay.string(from:)) ?? "" }

// MARK: - Modèle

enum Scope: String, CaseIterable, Identifiable {
    case all = "Tous les jeux", mine = "Mes jeux", updates = "Mises à jour", new = "Nouvelles versions", soon = "Bientôt"
    var id: String { rawValue }
    var symbol: String { ["Tous les jeux": "square.grid.2x2", "Mes jeux": "folder", "Mises à jour": "arrow.down.circle", "Nouvelles versions": "sparkles", "Bientôt": "clock"][rawValue]! }
}
enum SortKey: String, CaseIterable, Identifiable {
    case name = "Nom", released = "Dernière version", added = "Ajout au catalogue", popular = "Popularité"
    var id: String { rawValue }
}

struct DL { var progress: Double; var done: Int64; var total: Int64; var task: URLSessionDownloadTask? }

@MainActor
final class Model: ObservableObject {
    @Published var apps: [Recomp] = []
    @Published var origins: [String: String] = [:]
    @Published var updated: String?
    @Published var loading = false
    @Published var error: String?
    @Published var installed: [String: [String: Installed]] = [:]
    @Published var found: [String: [String: Local]] = [:]   // id → système → fichier trouvé dans la bibliothèque
    @Published var downloads: [String: DL] = [:]             // "id|système"
    @Published var message: String?

    @Published var search = ""
    @Published var scope: Scope = .all
    @Published var console = ""          // "" = toutes
    @Published var genre = ""
    @Published var system = ""           // "" = tous ; sinon Sys.rawValue
    @Published var sort: SortKey = SortKey(rawValue: UserDefaults.standard.string(forKey: "sort") ?? "") ?? .name {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "sort") }
    }

    /// Un dossier par système (ex. Mac → Lexar/Jeux/ROM/MacOS) : on y range les téléchargements et on y cherche les jeux déjà là.
    @Published var folders: [Sys: URL] = Dictionary(uniqueKeysWithValues: Sys.allCases.map { s in
        (s, URL(fileURLWithPath: UserDefaults.standard.string(forKey: "folder.\(s.rawValue)") ?? UserDefaults.standard.string(forKey: "library")
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("Recomps").path))
    })
    func folder(_ s: Sys) -> URL { folders[s]! }
    func setFolder(_ s: Sys, _ u: URL) { folders[s] = u; UserDefaults.standard.set(u.path, forKey: "folder.\(s.rawValue)"); rescan() }

    let downloader = Downloader()
    private var manifestURL: URL { supportDir.appendingPathComponent("installed.json") }
    private var cacheURL: URL { supportDir.appendingPathComponent("pc-catalog.json") }

    init() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: manifestURL), let m = try? JSONDecoder().decode([String: [String: Installed]].self, from: d) { installed = m }
        if let d = try? Data(contentsOf: cacheURL) { apply(d) }
        Task { await refresh() }
    }

    func apply(_ data: Data) {
        do {
            let c = try JSONDecoder().decode(Catalog.self, from: data)
            apps = c.apps
            origins = Dictionary(c.origins.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            updated = c.updated
            rescan()
        } catch { self.error = "Catalogue illisible : \(error.localizedDescription)" }
    }

    /// Actualisation demandée (bouton, ⌘R) : catalogue, dossiers, et notes de version rechargées depuis GitHub.
    func refreshAll() async {
        notes = [:]; notesError = [:]
        try? FileManager.default.removeItem(at: supportDir.appendingPathComponent("notes"))
        await refresh()
    }

    func refresh() async {
        loading = true; defer { loading = false }
        var req = URLRequest(url: catalogURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        if !apps.isEmpty, let etag = UserDefaults.standard.string(forKey: "etag") { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            if http?.statusCode == 304 { error = nil; rescan(); return }
            guard http?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try? data.write(to: cacheURL, options: .atomic)
            UserDefaults.standard.set(http?.value(forHTTPHeaderField: "ETag"), forKey: "etag")
            apply(data); error = nil
        } catch {
            self.error = apps.isEmpty ? "Catalogue injoignable : \(error.localizedDescription)" : "Hors ligne : catalogue en cache."
        }
    }

    // Jeux déjà là, dans le dossier de chaque système (3 niveaux) : ceux téléchargés ici (installed.json),
    // les archives ou dossiers dont le nom suit le modèle du catalogue, et (Mac) les .app reconnues à leur nom et bundle ID.
    func rescan() {
        let apps = self.apps, folders = self.folders
        Task.detached(priority: .utility) {
            var listing: [URL: [(String, URL, Date)]] = [:]
            for u in Set(folders.values) { listing[u] = listFiles(u) }
            var out: [String: [String: Local]] = [:]
            func keep(_ id: String, _ s: Sys, _ l: Local) {
                if let o = out[id]?[s.rawValue], o.date >= l.date { return }
                out[id, default: [:]][s.rawValue] = l
            }
            for s in Sys.allCases {
                let entries = listing[folders[s]!] ?? []
                guard !entries.isEmpty else { continue }
                for a in apps {
                    guard let p = a.pattern(s) else { continue }
                    let res = [globRegex(p), globRegex(p, stripExt: true)].compactMap { $0 }
                    for (n, u, d) in entries where !n.hasSuffix(".app") {
                        for re in res {
                            let r = firstCapture(re, n)
                            if r.matched { keep(a.id, s, Local(path: u, version: r.capture, date: d)) }
                        }
                    }
                }
                if s == .macos {
                    let keys = apps.compactMap(AppKeys.init)
                    for (n, u, _) in entries where n.hasSuffix(".app") {
                        if let (id, ver, d) = matchApp(u, keys) { keep(id, .macos, Local(path: u, version: ver, date: d, isApp: true)) }
                    }
                }
            }
            let result = out
            await MainActor.run { self.found = result }
        }
    }

    func status(_ a: Recomp, _ s: Sys) -> Status {
        if let i = installed[a.id]?[s.rawValue], FileManager.default.fileExists(atPath: i.file) {
            return (norm(i.tag) == norm(a.tag) || norm(i.version) == norm(a.version)) ? .upToDate : .outdated
        }
        guard let f = found[a.id]?[s.rawValue] else { return .none }
        let rel = a.released.flatMap(isoDay.date(from:))
        if let v = norm(f.version) {
            if v == norm(a.version) || v == norm(a.tag) { return .upToDate }
            // Version différente : une .app peut afficher une version figée (« 1.0 ») ; on ne conclut que si le fichier date d'avant la release.
            if let rel, f.date < rel { return .outdated }
            return f.isApp ? .unknown : .outdated
        }
        guard let rel else { return .unknown }
        return f.date >= rel ? .upToDate : .outdated    // nom sans version : on compare à la date de la release
    }
    func status(_ a: Recomp) -> Status { a.sysList.map { status(a, $0) }.max() ?? .none }
    func localPath(_ a: Recomp, _ s: Sys) -> URL? {
        if let i = installed[a.id]?[s.rawValue], FileManager.default.fileExists(atPath: i.file) { return URL(fileURLWithPath: i.file) }
        return found[a.id]?[s.rawValue]?.path
    }

    var consoles: [(String, String, Int)] {
        Dictionary(grouping: apps, by: { $0.origin ?? "other" }).map { ($0.key, origins[$0.key] ?? $0.key, $0.value.count) }
            .sorted { $0.2 > $1.2 }
    }
    var genres: [(String, Int)] { Dictionary(grouping: apps, by: { $0.genre ?? "other" }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 } }

    func inScope(_ a: Recomp, _ sc: Scope) -> Bool {
        switch sc {
        case .all: return !a.isSoon
        case .mine: return status(a) != .none
        case .updates: return status(a) == .outdated
        case .soon: return a.isSoon
        case .new:
            guard let d = a.released.flatMap(isoDay.date(from:)) else { return false }   // version sortie ces 14 derniers jours
            return !a.isSoon && d > Date().addingTimeInterval(-14 * 86400)
        }
    }
    func count(_ sc: Scope) -> Int { apps.filter { inScope($0, sc) }.count }

    var filtered: [Recomp] {
        let q = search.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let list = apps.filter { a in
            inScope(a, scope)
            && (console.isEmpty || a.origin == console)
            && (genre.isEmpty || a.genre == genre)
            && (system.isEmpty || (a.systems ?? []).contains(system))
            && (q.isEmpty || [a.name, a.game ?? "", a.author ?? "", a.about?.genres?.joined(separator: " ") ?? "", (a.tags ?? []).joined(separator: " ")]
                .joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q))
        }
        switch sort {
        case .name: return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .released: return list.sorted { ($0.released ?? "") > ($1.released ?? "") }
        case .added: return list.sorted { ($0.added ?? "") > ($1.added ?? "") }
        case .popular: return list.sorted { ($0.downloads ?? 0) > ($1.downloads ?? 0) }
        }
    }

    // MARK: Téléchargement

    func key(_ a: Recomp, _ s: Sys) -> String { "\(a.id)|\(s.rawValue)" }

    func download(_ a: Recomp, _ s: Sys) { Task { await perform(a, s) } }

    /// Ce qui a une mise à jour : chaque jeu × système marqué « Mise à jour ».
    var outdated: [(Recomp, Sys)] { apps.flatMap { a in a.sysList.filter { status(a, $0) == .outdated }.map { (a, $0) } } }
    @Published var updating: (done: Int, total: Int)?
    private var stopUpdating = false

    /// Tout mettre à jour : un téléchargement après l'autre (GitHub n'aime pas les rafales), jusqu'au bout ou jusqu'à « Arrêter ».
    func updateAll() {
        guard updating == nil else { return }
        let todo = outdated
        guard !todo.isEmpty else { return }
        stopUpdating = false
        updating = (0, todo.count)
        Task {
            var ok = 0
            for (i, (a, s)) in todo.enumerated() {
                if stopUpdating { break }
                if await perform(a, s) { ok += 1 }
                updating = (i + 1, todo.count)
            }
            updating = nil
            message = stopUpdating ? "Mises à jour arrêtées : \(ok) faite\(ok > 1 ? "s" : "")." : "\(ok) mise\(ok > 1 ? "s" : "") à jour sur \(todo.count)\(ok < todo.count ? " (voir les erreurs sur les fiches)" : "")."
        }
    }
    func stopAll() {
        stopUpdating = true
        for d in downloads.values { d.task?.cancel() }
    }

    @discardableResult
    func perform(_ a: Recomp, _ s: Sys) async -> Bool {
        let k = key(a, s)
        guard downloads[k] == nil else { return false }
        downloads[k] = DL(progress: 0, done: 0, total: 0)
        do {
                let (url, name, sha) = try await resolve(a, s)
                let root = folder(s)
                let tmp = try await downloader.fetch(url, key: k) { done, total, task in
                    Task { @MainActor in
                        guard self.downloads[k] != nil else { return }
                        self.downloads[k] = DL(progress: total > 0 ? Double(done) / Double(total) : 0, done: done, total: total, task: task)
                    }
                }
                if let sha, try await sha256(tmp) != sha.lowercased() {
                    try? FileManager.default.removeItem(at: tmp)
                    throw NSError(domain: "Recomps", code: 1, userInfo: [NSLocalizedDescriptionKey: "le fichier reçu ne correspond pas à l'empreinte SHA-256 du catalogue"])
                }
                let old = localPath(a, s), oldManaged = installed[a.id]?[s.rawValue] != nil
                let dest = try await Task.detached(priority: .utility) { () throws -> URL in
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    // Mac : l'app est sortie de son archive (.zip, .dmg, .tar.gz) et posée directement dans le dossier Mac.
                    if s == .macos, let app = try installApp(from: tmp, named: name, into: root) {
                        try? FileManager.default.removeItem(at: tmp)
                        return app
                    }
                    let dir = root.appendingPathComponent(safe(a.name), isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let d = dir.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: d.path) { try FileManager.default.trashItem(at: d, resultingItemURL: nil) }
                    try FileManager.default.moveItem(at: tmp, to: d)
                    return d
                }.value
                // L'ancienne version part à la corbeille : si l'app l'avait téléchargée, ou si c'est la même app (même bundle ID).
                if let old, old.path != dest.path, FileManager.default.fileExists(atPath: old.path),
                   oldManaged || (bundleID(old) != nil && bundleID(old) == bundleID(dest)) {
                    try? FileManager.default.trashItem(at: old, resultingItemURL: nil)
                }
                installed[a.id, default: [:]][s.rawValue] = Installed(tag: a.tag, version: a.version, file: dest.path, date: Date())
                saveManifest()
                downloads[k] = nil
                errors[k] = nil
                if updating == nil { message = "\(a.name) (\(s.label)) : \(dest.lastPathComponent) dans \(root.lastPathComponent)" }
                rescan()
                return true
            } catch {
                downloads[k] = nil
                if (error as? URLError)?.code != .cancelled {
                    errors[k] = error.localizedDescription
                    if updating == nil { message = "\(a.name) (\(s.label)) : \(error.localizedDescription)" }
                }
                return false
            }
    }

    @Published var errors: [String: String] = [:]   // dernière erreur de téléchargement, par "id|système"

    // MARK: Notes de version (releases GitHub, gardées 6 h sur disque)

    @Published var notes: [String: [Release]] = [:]
    @Published var notesError: [String: String] = [:]

    func loadNotes(_ a: Recomp) async {
        guard let repo = a.repo, notes[repo] == nil else { return }
        let file = supportDir.appendingPathComponent("notes").appendingPathComponent(repo.replacingOccurrences(of: "/", with: "__") + ".json")
        let fresh = ((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > Date().addingTimeInterval(-6 * 3600)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: file), let r = try? dec.decode([Release].self, from: d) {
            notes[repo] = r
            if fresh { return }
        }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=10")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                if notes[repo] == nil { notesError[repo] = code == 403 || code == 429 ? "GitHub limite les requêtes sans compte : réessaie dans un moment." : "Notes indisponibles (code \(code))." }
                return
            }
            let r = try dec.decode([Release].self, from: data).filter { !$0.draft }
            notes[repo] = r; notesError[repo] = nil
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        } catch {
            if notes[repo] == nil { notesError[repo] = "Notes indisponibles : \(error.localizedDescription)" }
        }
    }

    /// Version présente pour l'affichage des notes : celle téléchargée ici, sinon celle lue sur le fichier ou l'app.
    func localVersion(_ a: Recomp) -> (String?, Date?) {
        for s in a.sysList {
            if let i = installed[a.id]?[s.rawValue] { return (i.tag ?? i.version, i.date) }
        }
        for s in a.sysList { if let f = found[a.id]?[s.rawValue] { return (f.version, f.date) } }
        return (nil, nil)
    }

    func cancel(_ a: Recomp, _ s: Sys) { downloads[key(a, s)]?.task?.cancel() }

    func resolve(_ a: Recomp, _ s: Sys) async throws -> (URL, String, String?) {
        guard let repo = a.repo, let pattern = a.pattern(s) else { throw NSError(domain: "Recomps", code: 2, userInfo: [NSLocalizedDescriptionKey: "pas de fichier pour \(s.label)"]) }
        func direct(_ tag: String, _ name: String) -> URL {
            URL(string: "https://github.com/\(repo)/releases/download/\(tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag)/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)")!
        }
        let f = a.files?[s.rawValue]
        if let tag = a.tag, let n = f?.name { return (direct(tag, n), n, f?.sha256) }
        if let tag = a.tag, !pattern.contains("*") { return (direct(tag, pattern), pattern, nil) }
        // Modèle avec « * » : on cherche le fichier dans la release (API GitHub, sans compte : 60 requêtes / heure).
        let api = URL(string: "https://api.github.com/repos/\(repo)/releases/" + (a.tag.map { "tags/" + ($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0) } ?? "latest"))!
        var req = URLRequest(url: api); req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "Recomps", code: 3, userInfo: [NSLocalizedDescriptionKey: "release introuvable sur GitHub (code \((resp as? HTTPURLResponse)?.statusCode ?? 0))"])
        }
        struct Rel: Decodable { struct A: Decodable { let name: String; let browser_download_url: String }; let assets: [A] }
        let rel = try JSONDecoder().decode(Rel.self, from: data)
        guard let re = globRegex(pattern), let hit = rel.assets.first(where: { firstCapture(re, $0.name).matched }), let u = URL(string: hit.browser_download_url) else {
            throw NSError(domain: "Recomps", code: 4, userInfo: [NSLocalizedDescriptionKey: "aucun fichier « \(pattern) » dans la release"])
        }
        return (u, hit.name, nil)
    }

    func saveManifest() {
        if let d = try? JSONEncoder().encode(installed) { try? d.write(to: manifestURL, options: .atomic) }
    }
}

/// Fichiers et dossiers de la bibliothèque, jusqu'à 3 niveaux (sans entrer dans les .app).
func listFiles(_ root: URL) -> [(String, URL, Date)] {
    var out: [(String, URL, Date)] = []
    guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return out }
    while let u = en.nextObject() as? URL {
        if en.level > 3 { en.skipDescendants(); continue }
        let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        out.append((u.lastPathComponent, u, d))
    }
    return out
}

// MARK: - Apps Mac déjà installées

func normKey(_ s: String?) -> String { (s ?? "").lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) } }

/// Ce qui permet de reconnaître la .app d'un jeu : début du nom de fichier du catalogue, dépôt, identifiant, nom, auteur.
struct AppKeys: Sendable {
    let id: String; let keys: Set<String>; let owner: String; let repo: String
    init?(_ a: Recomp) {
        guard let p = a.pattern(.macos), let r = a.repo?.split(separator: "/"), r.count == 2 else { return nil }
        let pre = normKey(p.split(whereSeparator: { "-_*. ".contains($0) }).first.map(String.init))
        id = a.id; owner = String(r[0]).lowercased(); repo = normKey(String(r[1]))
        keys = Set([pre, repo, normKey(a.id), normKey(a.name)].filter { $0.count >= 3 })
    }
}

func bundleID(_ u: URL) -> String? {
    (NSDictionary(contentsOf: u.appendingPathComponent("Contents/Info.plist")) as? [String: Any])?["CFBundleIdentifier"] as? String
}

/// La .app correspond-elle à un jeu du catalogue ? → (id du jeu, version de l'app, date de son Info.plist)
func matchApp(_ u: URL, _ all: [AppKeys]) -> (String, String?, Date)? {
    let plist = u.appendingPathComponent("Contents/Info.plist")
    guard let info = NSDictionary(contentsOf: plist) as? [String: Any] else { return nil }
    let stem = normKey(u.deletingPathExtension().lastPathComponent), bname = normKey(info["CFBundleName"] as? String)
    let bid = (info["CFBundleIdentifier"] as? String ?? "").lowercased(), nbid = normKey(bid)
    var best: (Int, String)?
    for k in all {
        var sc = 0
        if k.keys.contains(stem) || k.keys.contains(bname) { sc += 3 }
        if k.keys.contains(where: { min($0.count, stem.count) >= 5 && ($0.hasPrefix(stem) || stem.hasPrefix($0)) }) { sc += 1 }
        if k.owner.count >= 4, bid.contains(k.owner) { sc += 2 }
        if k.repo.count >= 4, nbid.contains(k.repo) { sc += 2 }
        if sc >= 4, sc > (best?.0 ?? 0) { best = (sc, k.id) }
    }
    guard let id = best?.1 else { return nil }
    let d = (try? plist.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    return (id, (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String), d)
}

@discardableResult
func run(_ tool: String, _ args: [String]) throws -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
    try p.run()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        throw NSError(domain: "Recomps", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "\((tool as NSString).lastPathComponent) : \(out.suffix(200))"])
    }
    return out
}

func findApp(_ root: URL) -> URL? {
    guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
    while let u = en.nextObject() as? URL {
        if en.level > 3 { en.skipDescendants(); continue }
        if u.pathExtension == "app" { return u }
    }
    return nil
}

/// Sort la .app d'une archive et la pose dans le dossier (l'ancienne du même nom va à la corbeille). nil : pas de .app dedans.
func installApp(from archive: URL, named name: String, into folder: URL) throws -> URL? {
    let fm = FileManager.default, n = name.lowercased()
    let work = fm.temporaryDirectory.appendingPathComponent("recomps-" + UUID().uuidString)
    try fm.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: work) }
    var mount: URL?
    if n.hasSuffix(".zip") { try run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path]) }
    else if [".tar.gz", ".tgz", ".tar.xz", ".tar.bz2", ".tar"].contains(where: n.hasSuffix) { try run("/usr/bin/tar", ["-xf", archive.path, "-C", work.path]) }
    else if n.hasSuffix(".dmg") {
        let m = work.appendingPathComponent("mnt")
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", m.path, archive.path])
        mount = m
    } else { return nil }
    defer { if let m = mount { _ = try? run("/usr/bin/hdiutil", ["detach", m.path, "-force"]) } }
    guard let app = findApp(mount ?? work) else { return nil }
    let dest = folder.appendingPathComponent(app.lastPathComponent)
    if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
    try run("/usr/bin/ditto", [app.path, dest.path])
    return dest
}

func safe(_ s: String) -> String {
    s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -").trimmingCharacters(in: .whitespaces)
}

func sha256(_ url: URL) async throws -> String {
    try await Task.detached(priority: .utility) {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }.value
}

/// Téléchargements avec progression (URLSessionDownloadDelegate) ; le fichier fini est déplacé hors du dossier temporaire du système.
final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias Progress = (Int64, Int64, URLSessionDownloadTask) -> Void
    private var session: URLSession!
    private var waiting: [Int: (CheckedContinuation<URL, Error>, Progress)] = [:]
    private let lock = NSLock()

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func fetch(_ url: URL, key: String, progress: @escaping Progress) async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            let t = session.downloadTask(with: url)
            lock.lock(); waiting[t.taskIdentifier] = (c, progress); lock.unlock()
            progress(0, 0, t)
            t.resume()
        }
    }

    private func take(_ t: URLSessionTask) -> (CheckedContinuation<URL, Error>, Progress)? {
        lock.lock(); defer { lock.unlock() }; return waiting.removeValue(forKey: t.taskIdentifier)
    }

    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        lock.lock(); let p = waiting[t.taskIdentifier]?.1; lock.unlock()
        p?(w, e, t)
    }

    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
        let code = (t.response as? HTTPURLResponse)?.statusCode ?? 0
        guard let (c, _) = take(t) else { return }
        guard code == 200 else {
            c.resume(throwing: NSError(domain: "Recomps", code: code, userInfo: [NSLocalizedDescriptionKey: "téléchargement refusé (code \(code))"])); return
        }
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try FileManager.default.moveItem(at: loc, to: keep); c.resume(returning: keep) } catch { c.resume(throwing: error) }
    }

    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
        if let e, let (c, _) = take(t) { c.resume(throwing: e) }
    }
}

