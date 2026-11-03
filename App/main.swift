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

struct Installed: Codable { var tag: String?; var version: String?; var file: String; var date: Date }

enum Status: Int, Comparable {
    case none = 0, upToDate, unknown, outdated
    static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
}

struct Local { var path: URL; var version: String?; var date: Date }

func norm(_ v: String?) -> String? {
    guard var v = v?.trimmingCharacters(in: .whitespaces).lowercased(), !v.isEmpty else { return nil }
    if v.hasPrefix("v"), v.dropFirst().first?.isNumber == true { v.removeFirst() }
    return v
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

    @Published var library: URL = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "library")
        ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("Recomps").path) {
        didSet { UserDefaults.standard.set(library.path, forKey: "library"); rescan() }
    }

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

    // Fichiers déjà là : ceux téléchargés ici (installed.json), et ceux dont le nom suit le modèle du jeu
    // (archive, ou dossier décompressé du même nom) dans la bibliothèque, jusqu'à 3 niveaux.
    func rescan() {
        let apps = self.apps, root = library
        Task.detached(priority: .utility) {
            let entries = listFiles(root)
            var out: [String: [String: Local]] = [:]
            if !entries.isEmpty {
                for a in apps {
                    for s in a.sysList {
                        guard let p = a.pattern(s) else { continue }
                        let res = [globRegex(p), globRegex(p, stripExt: true)].compactMap { $0 }
                        var best: Local?
                        for (n, u, d) in entries {
                            for re in res {
                                let r = firstCapture(re, n)
                                if r.matched, best == nil || d > best!.date { best = Local(path: u, version: r.capture, date: d) }
                            }
                        }
                        if let b = best { out[a.id, default: [:]][s.rawValue] = b }
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
        if let v = norm(f.version) { return (v == norm(a.version) || v == norm(a.tag)) ? .upToDate : .outdated }
        guard let r = a.released.flatMap(isoDay.date(from:)) else { return .unknown }
        return f.date >= r ? .upToDate : .outdated    // nom sans version : on compare à la date de la release
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

    func download(_ a: Recomp, _ s: Sys) {
        let k = key(a, s)
        guard downloads[k] == nil else { return }
        downloads[k] = DL(progress: 0, done: 0, total: 0)
        Task {
            do {
                let (url, name, sha) = try await resolve(a, s)
                let dir = library.appendingPathComponent(safe(a.name), isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent(name)
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
                if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.moveItem(at: tmp, to: dest)
                // L'ancienne version de ce système, téléchargée ici, est remplacée.
                if let old = installed[a.id]?[s.rawValue]?.file, old != dest.path, old.hasPrefix(library.path) {
                    try? FileManager.default.trashItem(at: URL(fileURLWithPath: old), resultingItemURL: nil)
                }
                installed[a.id, default: [:]][s.rawValue] = Installed(tag: a.tag, version: a.version, file: dest.path, date: Date())
                saveManifest()
                downloads[k] = nil
                message = "\(a.name) (\(s.label)) téléchargé : \(dest.lastPathComponent)"
                rescan()
            } catch {
                downloads[k] = nil
                if (error as? URLError)?.code != .cancelled {
                    message = "\(a.name) (\(s.label)) : \(error.localizedDescription)"
                }
            }
        }
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

// MARK: - Interface

struct Badge: View {
    let st: Status
    var body: some View {
        switch st {
        case .none: EmptyView()
        case .upToDate: Label("À jour", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .outdated: Label("Mise à jour", systemImage: "arrow.down.circle.fill").foregroundStyle(.orange)
        case .unknown: Label("Présent", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }
}

struct Icon: View {
    let url: String?; var size: CGFloat = 40
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { img in img.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
            .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}

struct Row: View {
    @EnvironmentObject var m: Model
    let a: Recomp
    var body: some View {
        HStack(spacing: 10) {
            Icon(url: a.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name).fontWeight(.semibold).lineLimit(1)
                Text([m.origins[a.origin ?? ""] ?? a.origin, genreFR[a.genre ?? ""], a.isSoon ? "bientôt" : a.version.map { "v" + (norm($0) ?? $0) }]
                    .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 3) { ForEach(a.sysList) { Image(systemName: $0.symbol).font(.caption2).foregroundStyle(.tertiary) } }
            Badge(st: m.status(a)).labelStyle(.iconOnly)
        }.padding(.vertical, 2)
    }
}

struct SysRow: View {
    @EnvironmentObject var m: Model
    let a: Recomp; let s: Sys
    @State private var confirmRed = false
    var body: some View {
        let st = m.status(a, s), dl = m.downloads[m.key(a, s)], f = a.files?[s.rawValue]
        HStack(spacing: 10) {
            Label(s.label, systemImage: s.symbol).frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(f?.name ?? a.pattern(s) ?? "").font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Badge(st: st).font(.caption)
                    if let scan = f?.scan {
                        Text(["green": "analyse OK", "yellow": "analyse : à vérifier", "red": "analyse : alerte", "pending": "analyse en cours"][scan] ?? scan)
                            .font(.caption).foregroundStyle(scan == "green" ? .green : scan == "red" ? .red : scan == "yellow" ? .orange : .secondary)
                    }
                    if let p = m.localPath(a, s) { Text(p.lastPathComponent).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle) }
                }
                if let dl {
                    ProgressView(value: dl.progress).frame(maxWidth: 260)
                    Text(dl.total > 0 ? "\(ByteCountFormatter.string(fromByteCount: dl.done, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: dl.total, countStyle: .file))" : "Préparation…")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let p = m.localPath(a, s) {
                Button { NSWorkspace.shared.activateFileViewerSelecting([p]) } label: { Image(systemName: "folder") }.help("Afficher dans le Finder")
            }
            if dl != nil {
                Button("Annuler") { m.cancel(a, s) }
            } else {
                Button(st == .upToDate ? "Retélécharger" : st == .none ? "Télécharger" : "Mettre à jour") {
                    if f?.scan == "red" { confirmRed = true } else { m.download(a, s) }
                }.buttonStyle(.borderedProminent).tint(st == .upToDate ? .gray : .accentColor)
            }
        }
        .confirmationDialog("L'analyse antivirus du site a signalé ce fichier.", isPresented: $confirmRed) {
            Button("Télécharger quand même", role: .destructive) { m.download(a, s) }
        } message: { Text("Vérifie le dépôt GitHub du projet avant de l'ouvrir.") }
    }
}

struct Detail: View {
    @EnvironmentObject var m: Model
    let a: Recomp
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AsyncImage(url: a.cover.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.1) }
                    .frame(height: 170).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 12) {
                    Icon(url: a.icon, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.name).font(.title2.bold())
                        if let g = a.game, g != a.name { Text(g).foregroundStyle(.secondary) }
                        Text([m.origins[a.origin ?? ""], genreFR[a.genre ?? ""], a.author.map { "par " + $0 }, a.license].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !a.isSoon {
                    Text("Version \(a.version ?? "?") · sortie le \(day(a.released))\(a.size.map { $0.isEmpty ? "" : " · " + $0 } ?? "")\(a.downloads.map { " · \($0.formatted()) téléchargements" } ?? "")")
                        .font(.callout)
                }
                if let b = a.blurb, !b.isEmpty { Text(b) }
                if let n = a.needs, !n.isEmpty { Label(n, systemImage: "opticaldisc").font(.callout).foregroundStyle(.secondary) }

                if a.isSoon {
                    Label("Pas encore de version téléchargeable.", systemImage: "clock").foregroundStyle(.secondary)
                } else {
                    GroupBox("Télécharger") {
                        VStack(spacing: 10) { ForEach(a.sysList) { SysRow(a: a, s: $0); if $0 != a.sysList.last { Divider() } } }.padding(6)
                    }
                    Text("Dans « \(m.library.path)/\(safe(a.name)) »").font(.caption).foregroundStyle(.tertiary)
                }
                if let steps = a.setup_steps, !steps.isEmpty {
                    GroupBox("Installation") {
                        VStack(alignment: .leading, spacing: 4) { ForEach(Array(steps.enumerated()), id: \.offset) { Text("\($0.offset + 1). \($0.element)") } }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                }
                if let f = a.features, !f.isEmpty {
                    VStack(alignment: .leading, spacing: 3) { ForEach(f, id: \.self) { Label($0, systemImage: "checkmark").font(.callout) } }
                }
                if let s = a.about?.summary, !s.isEmpty { Text(s).font(.callout).foregroundStyle(.secondary) }
                HStack {
                    if let r = a.repo { Link("Dépôt GitHub", destination: URL(string: "https://github.com/\(r)")!) }
                    Link("Page sur recomplauncher.com", destination: URL(string: "https://recomplauncher.com/pc/game/\(a.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? a.id)")!)
                }.font(.callout)
            }.padding(20)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: Model
    @State private var selection: String?
    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { m.scope }, set: { if let v = $0 { m.scope = v } })) {
                Section("Bibliothèque") {
                    ForEach(Scope.allCases) { s in
                        Label(s.rawValue, systemImage: s.symbol).badge(m.count(s)).tag(s)
                    }
                }
                Section("Filtres") {
                    Picker("Console", selection: $m.console) {
                        Text("Toutes").tag("")
                        Divider()
                        ForEach(m.consoles, id: \.0) { Text("\($0.1) (\($0.2))").tag($0.0) }
                    }
                    Picker("Genre", selection: $m.genre) {
                        Text("Tous").tag("")
                        Divider()
                        ForEach(m.genres, id: \.0) { Text("\(genreFR[$0.0] ?? $0.0) (\($0.1))").tag($0.0) }
                    }
                    Picker("Système", selection: $m.system) {
                        Text("Tous").tag("")
                        ForEach(Sys.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Tri", selection: $m.sort) { ForEach(SortKey.allCases) { Text($0.rawValue).tag($0) } }
                    if !m.console.isEmpty || !m.genre.isEmpty || !m.system.isEmpty {
                        Button("Effacer les filtres") { m.console = ""; m.genre = ""; m.system = "" }.buttonStyle(.link)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if let e = m.error { Text(e).foregroundStyle(.orange) }
                    if let u = m.updated { Text("Catalogue du \(day(String(u.prefix(10))))") }
                    Button("Dossier…") { chooseFolder() }.buttonStyle(.link)
                    Text(m.library.path).lineLimit(2).truncationMode(.middle).foregroundStyle(.tertiary)
                }.font(.caption).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
        } content: {
            let list = m.filtered
            List(list, selection: $selection) { Row(a: $0).tag($0.id) }
                .overlay { if list.isEmpty && !m.loading { Text(m.apps.isEmpty ? "Chargement du catalogue…" : "Aucun jeu ne correspond.").foregroundStyle(.secondary) } }
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
                .navigationTitle(m.scope.rawValue)
                .navigationSubtitle("\(list.count) jeu\(list.count > 1 ? "x" : "")")
                .toolbar {
                    ToolbarItemGroup {
                        Button { Task { await m.refresh() } } label: {
                            if m.loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                        }.help("Actualiser le catalogue et la bibliothèque")
                    }
                }
        } detail: {
            if let id = selection, let a = m.apps.first(where: { $0.id == id }) { Detail(a: a).id(a.id) }
            else { Text("Choisis un jeu.").foregroundStyle(.secondary) }
        }
        .searchable(text: $m.search, placement: .sidebar, prompt: "Jeu, auteur, tag…")
        .overlay(alignment: .bottom) {
            if let msg = m.message {
                Text(msg).padding(.horizontal, 14).padding(.vertical, 8).background(.regularMaterial, in: Capsule()).padding(14)
                    .onTapGesture { m.message = nil }
                    .task(id: msg) { try? await Task.sleep(for: .seconds(6)); if m.message == msg { m.message = nil } }
            }
        }
    }

    func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Choisir"; p.message = "Dossier où ranger les jeux téléchargés (et où chercher ceux déjà là)"
        p.directoryURL = m.library
        if p.runModal() == .OK, let u = p.url { m.library = u }
    }
}

@main
struct RecompsApp: App {
    @StateObject private var m = Model()
    var body: some Scene {
        WindowGroup("Recomps") {
            ContentView().environmentObject(m).frame(minWidth: 960, minHeight: 600)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in m.rescan() }
        }
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
