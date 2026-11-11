// Interface : bleu nuit, panneaux, dégradé cyan → bleu (couleurs de recomplauncher.com), jaquettes en grille.

import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, _ a: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: a)
    }
}

enum Theme {
    static let midnight = Color(hex: 0x0B1220)
    static let panel = Color(hex: 0x0F1829)
    static let panel2 = Color(hex: 0x141F33)
    static let frost = Color(hex: 0xF4F8FC)
    static let cyan = Color(hex: 0x34F2E8)
    static let blue = Color(hex: 0x377BB6)
    static let muted = Color(hex: 0xA7B3C4)
    static let edge = Color(hex: 0xF4F8FC, 0.09)
    static let edge2 = Color(hex: 0xF4F8FC, 0.16)
    static let glass = Color(hex: 0xF4F8FC, 0.08)
    static let ok = Color(hex: 0x3CDC8C)
    static let warn = Color(hex: 0xFFB547)
    static let brand = LinearGradient(colors: [cyan, blue], startPoint: .top, endPoint: .bottom)
}

struct BrandButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.midnight)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Theme.brand, in: Capsule())
            .opacity(c.isPressed ? 0.75 : 1)
    }
}

struct GhostButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.frost)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.glass, in: Capsule()).overlay(Capsule().stroke(Theme.edge2))
            .opacity(c.isPressed ? 0.7 : 1)
    }
}

struct Pill: View {
    let st: Status
    var compact = false
    var body: some View {
        let (t, i, c): (String, String, Color) = switch st {
        case .upToDate: ("À jour", "checkmark", Theme.ok)
        case .outdated: ("Mise à jour", "arrow.down", Theme.warn)
        case .unknown: ("Présent", "questionmark", Theme.muted)
        case .none: ("", "", .clear)
        }
        if st != .none {
            HStack(spacing: 4) {
                Image(systemName: i).font(.system(size: 9, weight: .bold))
                if !compact { Text(t).font(.system(size: 11, weight: .semibold)) }
            }
            .foregroundStyle(c).padding(.horizontal, compact ? 6 : 8).padding(.vertical, 4)
            .background(Theme.midnight.opacity(0.85), in: Capsule()).overlay(Capsule().stroke(c.opacity(0.5)))
        }
    }
}

struct Remote: View {
    let url: String?
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:)), transaction: Transaction(animation: .easeOut(duration: 0.2))) { ph in
            if let img = ph.image { img.resizable().scaledToFill() } else { Theme.panel2 }
        }
    }
}

struct Icon: View {
    let url: String?; var size: CGFloat = 40
    var body: some View { Remote(url: url).frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.24)) }
}

@MainActor func subtitle(_ m: Model, _ a: Recomp) -> String {
    [m.origins[a.origin ?? ""] ?? a.origin, genreFR[a.genre ?? ""]].compactMap { $0 }.joined(separator: " · ")
}

struct SysIcons: View {
    let a: Recomp
    var body: some View {
        HStack(spacing: 5) { ForEach(a.sysList) { Image(systemName: $0.symbol).font(.system(size: 10, weight: .semibold)) } }
            .foregroundStyle(Theme.frost.opacity(0.85))
    }
}

// MARK: Grille et liste

struct Card: View {
    @EnvironmentObject var m: Model
    let a: Recomp; let selected: Bool
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.clear.aspectRatio(2 / 3, contentMode: .fit)
                .overlay { Remote(url: a.cover ?? a.icon) }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Theme.midnight.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack {
                        SysIcons(a: a)
                        Spacer()
                        if a.isSoon { Text("Bientôt").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.cyan) }
                        else if let v = a.version { Text(norm(v) ?? v).font(.system(size: 10.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.frost.opacity(0.8)).lineLimit(1) }
                    }.padding(8)
                }
                .overlay(alignment: .topTrailing) { Pill(st: m.status(a), compact: true).padding(7) }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.cyan : hover ? Theme.edge2 : Theme.edge, lineWidth: selected ? 2 : 1))
                .shadow(color: selected ? Theme.cyan.opacity(0.35) : .black.opacity(0.3), radius: selected ? 14 : 6, y: 6)
                .scaleEffect(hover ? 1.02 : 1)
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.frost).lineLimit(1)
                    Text(subtitle(m, a)).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                QuickDownload(a: a, compact: true)
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

struct ListRow: View {
    @EnvironmentObject var m: Model
    let a: Recomp; let selected: Bool
    var body: some View {
        HStack(spacing: 12) {
            Icon(url: a.icon, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.frost).lineLimit(1)
                Text(subtitle(m, a)).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            SysIcons(a: a)
            Text(a.isSoon ? "Bientôt" : a.version.map { norm($0) ?? $0 } ?? "").font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(Theme.muted).frame(width: 90, alignment: .trailing).lineLimit(1)
            Pill(st: m.status(a)).frame(width: 104, alignment: .trailing)
            QuickDownload(a: a, compact: false).frame(width: 118, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(selected ? Theme.panel2 : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.cyan.opacity(0.6) : .clear))
        .contentShape(Rectangle())
    }
}

// MARK: Fiche

struct SysRow: View {
    @EnvironmentObject var m: Model
    let a: Recomp; let s: Sys
    @State private var confirmRed = false
    var body: some View {
        let st = m.status(a, s), dl = m.downloads[m.key(a, s)], f = a.files?[s.rawValue], local = m.localPath(a, s)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: s.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.cyan).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.frost)
                    Text(f?.name ?? a.pattern(s) ?? "").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.muted)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                Pill(st: st)
            }
            if let local {
                HStack(spacing: 6) {
                    Image(systemName: local.pathExtension == "app" ? "app.badge.checkmark" : "doc.zipper").foregroundStyle(Theme.muted)
                    Text(local.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    if let v = m.found[a.id]?[s.rawValue]?.version, m.installed[a.id]?[s.rawValue] == nil { Text("· v\(norm(v) ?? v)") }
                }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            if dl == nil, let e = m.errors[m.key(a, s)] {
                Label(e, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let dl {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: dl.progress).tint(Theme.cyan)
                    Text(dl.total > 0 ? "\(ByteCountFormatter.string(fromByteCount: dl.done, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: dl.total, countStyle: .file))" : "Préparation…")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 8) {
                if let scan = f?.scan {
                    let (t, c): (String, Color) = switch scan {
                    case "green": ("Analyse OK", Theme.ok)
                    case "yellow": ("Analyse : à vérifier", Theme.warn)
                    case "red": ("Analyse : alerte", .red)
                    default: ("Analyse en cours", Theme.muted)
                    }
                    Label(t, systemImage: "shield").font(.system(size: 10.5)).foregroundStyle(c)
                }
                Spacer()
                if let local {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([local]) } label: { Image(systemName: "folder") }
                        .buttonStyle(GhostButton()).help("Afficher dans le Finder")
                    if s == .macos, local.pathExtension == "app" {
                        Button("Ouvrir") { NSWorkspace.shared.open(local) }.buttonStyle(GhostButton())
                    }
                }
                if dl != nil {
                    Button("Annuler") { m.cancel(a, s) }.buttonStyle(GhostButton())
                } else if st == .upToDate {
                    Button("Retélécharger") { go(f) }.buttonStyle(GhostButton())
                } else {
                    Button(st == .none ? "Télécharger" : "Mettre à jour") { go(f) }.buttonStyle(BrandButton())
                }
            }
        }
        .padding(12)
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.edge))
        .confirmationDialog("L'analyse antivirus du site a signalé ce fichier.", isPresented: $confirmRed) {
            Button("Télécharger quand même", role: .destructive) { m.download(a, s) }
        } message: { Text("Vérifie le dépôt du projet avant de l'ouvrir.") }
    }
    func go(_ f: FileInfo?) { if f?.scan == "red" { confirmRed = true } else { m.download(a, s) } }
}

struct Detail: View {
    @EnvironmentObject var m: Model
    let a: Recomp
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    Color.clear.frame(height: 190).overlay { Remote(url: a.hero ?? a.cover) }.clipped()
                    LinearGradient(colors: [.clear, Theme.panel], startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .bottom, spacing: 12) {
                        Icon(url: a.icon, size: 58).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.edge2))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.frost).lineLimit(2)
                            if let g = a.game, g != a.name { Text(g).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lineLimit(1) }
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 4)
                }
                VStack(alignment: .leading, spacing: 14) {
                    FlowChips(items: [m.origins[a.origin ?? ""], genreFR[a.genre ?? ""], a.author.map { "par " + $0 }, a.license,
                                      a.status == "ended" ? "arrêté" : a.status == "paused" ? "en pause" : a.archived == true ? "archivé" : nil].compactMap { $0 })
                    if !a.isSoon {
                        HStack(spacing: 14) {
                            Stat(k: "Version", v: a.version.map { norm($0) ?? $0 } ?? "?")
                            Stat(k: "Sortie", v: day(a.released))
                            if let sz = a.size, !sz.isEmpty { Stat(k: "Taille", v: sz) }
                            if let d = a.downloads { Stat(k: "Téléch.", v: d.formatted(.number.notation(.compactName))) }
                        }
                    }
                    if let st = a.status, ["ended", "paused"].contains(st) || a.archived == true {
                        Label(a.status_note ?? (st == "paused" ? "Le développement est en pause." : "Le développeur a arrêté le projet : plus de mise à jour prévue."),
                              systemImage: st == "paused" ? "pause.circle" : "stop.circle")
                            .font(.system(size: 12)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                    } else if a.archived == true {
                        Label("Dépôt archivé : plus de mise à jour prévue.", systemImage: "archivebox").font(.system(size: 12)).foregroundStyle(Theme.warn)
                    }
                    if let b = a.blurb, !b.isEmpty { Text(b).font(.system(size: 13)).foregroundStyle(Theme.frost.opacity(0.92)) }
                    if let n = a.needs, !n.isEmpty {
                        Label(n, systemImage: "opticaldisc").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    if a.isSoon {
                        Label("Pas encore de version téléchargeable.", systemImage: "clock").foregroundStyle(Theme.muted)
                    } else {
                        Text("TÉLÉCHARGER").font(.system(size: 10.5, weight: .bold)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 4)
                        ForEach(a.sysList) { SysRow(a: a, s: $0) }
                    }
                    if a.repo != nil, !a.isSoon { Changelog(a: a) }
                    if let steps = a.setup_steps, !steps.isEmpty {
                        Section2("INSTALLATION") {
                            ForEach(Array(steps.enumerated()), id: \.offset) { i, t in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(i + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.midnight)
                                        .frame(width: 18, height: 18).background(Theme.brand, in: Circle())
                                    Text(t).font(.system(size: 12.5)).foregroundStyle(Theme.frost.opacity(0.9))
                                }
                            }
                        }
                    }
                    if let f = a.features, !f.isEmpty {
                        Section2("POINTS FORTS") {
                            ForEach(f, id: \.self) { Label($0, systemImage: "checkmark").font(.system(size: 12.5)).foregroundStyle(Theme.frost.opacity(0.9)) }
                        }
                    }
                    if let s = a.about?.summary, !s.isEmpty {
                        Section2("LE JEU") { Text(s).font(.system(size: 12.5)).foregroundStyle(Theme.muted) }
                    }
                    HStack(spacing: 8) {
                        if let u = a.repoURL {
                            Button(a.gitlab ? "GitLab" : "GitHub") { NSWorkspace.shared.open(u) }.buttonStyle(GhostButton())
                        }
                        if let u = a.report_url.flatMap(URL.init(string:)) {
                            Button("Signaler un problème") { NSWorkspace.shared.open(u) }.buttonStyle(GhostButton())
                        }
                        if let u = URL(string: "https://recomplauncher.com/pc/game/\(a.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? a.id)") {
                            Button("Page du site") { NSWorkspace.shared.open(u) }.buttonStyle(GhostButton())
                        }
                    }.padding(.top, 4)
                }.padding(.horizontal, 18).padding(.bottom, 22)
            }
        }
        .background(Theme.panel)
    }
}

struct Stat: View {
    let k: String, v: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.8).foregroundStyle(Theme.muted)
            Text(v).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.frost).lineLimit(1)
        }
    }
}

struct Section2<C: View>: View {
    let title: String; @ViewBuilder let content: C
    init(_ t: String, @ViewBuilder content: () -> C) { title = t; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10.5, weight: .bold)).tracking(1.2).foregroundStyle(Theme.muted)
            content
        }.padding(.top, 4)
    }
}

struct FlowChips: View {
    let items: [String]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) {
                Text($0).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.frost.opacity(0.9)).lineLimit(1)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(Theme.glass, in: Capsule()).overlay(Capsule().stroke(Theme.edge))
            }
        }
    }
}

// MARK: Fenêtre

struct Sidebar: View {
    @EnvironmentObject var m: Model
    var body: some View {
        List(selection: Binding(get: { m.scope }, set: { if let v = $0 { m.scope = v } })) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
                Text("Recomps").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.frost)
            }.padding(.bottom, 4).selectionDisabled()
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
                    Button("Effacer les filtres") { m.console = ""; m.genre = ""; m.system = "" }.buttonStyle(.link).tint(Theme.cyan)
                }
            }
            Section("Dossiers des jeux") {
                ForEach(Sys.allCases) { s in
                    Button { choose(s) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: s.symbol).foregroundStyle(Theme.cyan).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.label).foregroundStyle(Theme.frost)
                                Text(short(m.folder(s))).font(.system(size: 10.5)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.head)
                            }
                        }
                    }
                    .buttonStyle(.plain).help("\(m.folder(s).path)\nCliquer pour choisir un autre dossier")
                    .contextMenu {
                        Button("Choisir…") { choose(s) }
                        Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([m.folder(s)]) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.panel)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                if let e = m.error { Text(e).foregroundStyle(Theme.warn) }
                if let u = m.updated { Text("Catalogue du \(day(String(u.prefix(10))))") }
                Text("Données : recomplauncher.com")
            }.font(.system(size: 10.5)).foregroundStyle(Theme.muted).padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func short(_ u: URL) -> String {
        let c = u.pathComponents
        return c.count > 3 ? "…/" + c.suffix(3).joined(separator: "/") : u.path
    }

    func choose(_ s: Sys) {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Choisir"; p.message = "Dossier des jeux \(s.label) : les téléchargements y vont, et les jeux déjà là y sont cherchés"
        p.directoryURL = m.folder(s)
        if p.runModal() == .OK, let u = p.url { m.setFolder(s, u) }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: Model
    @State private var selection: String?
    @AppStorage("grid") private var grid = true
    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 230, ideal: 250)
        } detail: {
            let list = m.filtered
            ScrollView {
                if grid {
                    UpdateBanner()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: 18)], alignment: .leading, spacing: 22) {
                        ForEach(list) { a in Card(a: a, selected: selection == a.id).onTapGesture { selection = a.id } }
                    }.padding(22)
                } else {
                    UpdateBanner()
                    LazyVStack(spacing: 2) {
                        ForEach(list) { a in ListRow(a: a, selected: selection == a.id).onTapGesture { selection = a.id } }
                    }.padding(14)
                }
            }
            .overlay {
                if list.isEmpty && !m.loading {
                    Text(m.apps.isEmpty ? "Chargement du catalogue…" : "Aucun jeu ne correspond.").foregroundStyle(Theme.muted)
                }
            }
            .background {   // un clic hors des jaquettes (dans la grille) ferme la fiche
                Theme.midnight.contentShape(Rectangle()).onTapGesture { selection = nil }
            }
            .onExitCommand { selection = nil }
            .navigationTitle(m.scope.rawValue)
            .navigationSubtitle("\(list.count) jeu\(list.count > 1 ? "x" : "")")
            .inspector(isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })) {
                Group {
                    if let id = selection, let a = m.apps.first(where: { $0.id == id }) { Detail(a: a).id(a.id) }
                    else { Theme.panel }
                }
                .inspectorColumnWidth(min: 360, ideal: 420, max: 560)
            }
            .toolbar {
                ToolbarItemGroup {
                    UpdateAllButton()
                    Picker("Affichage", selection: $grid) {
                        Image(systemName: "square.grid.2x2").tag(true)
                        Image(systemName: "list.bullet").tag(false)
                    }.pickerStyle(.segmented).help("Grille ou liste")
                    Button { Task { await m.refreshAll() } } label: {
                        if m.loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                    }.help("Actualiser le catalogue, les dossiers et les notes de version (⌘R)")
                }
            }
        }
        .searchable(text: $m.search, placement: .toolbar, prompt: "Jeu, auteur, tag…")
        .toolbarBackground(Theme.midnight, for: .windowToolbar)
        .overlay(alignment: .bottom) {
            if let msg = m.message {
                Text(msg).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.frost)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.panel2, in: Capsule()).overlay(Capsule().stroke(Theme.cyan.opacity(0.5)))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6).padding(16)
                    .onTapGesture { m.message = nil }
                    .task(id: msg) { try? await Task.sleep(for: .seconds(6)); if m.message == msg { m.message = nil } }
            }
        }
    }
}

@main
struct RecompsApp: App {
    @StateObject private var m = Model()
    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20, directory: supportDir.appendingPathComponent("images"))
        SelfUpdate.start(repo: "VGioM/Recomps")
    }
    var body: some Scene {
        WindowGroup("Recomps") {
            ContentView().environmentObject(m).frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(.dark).tint(Theme.cyan)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in m.rescan() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(SelfUpdate.menuTitle) { SelfUpdate.checkNow() }
            }
            CommandGroup(after: .toolbar) {
                Button("Actualiser") { Task { await m.refreshAll() } }.keyboardShortcut("r")
                Divider()
            }
        }
    }
}

// MARK: Tout mettre à jour

struct UpdateAllButton: View {
    @EnvironmentObject var m: Model
    var body: some View {
        if let u = m.updating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Mise à jour \(min(u.done + 1, u.total))/\(u.total)").font(.system(size: 12).monospacedDigit())
                Button("Arrêter") { m.stopAll() }.buttonStyle(GhostButton())
            }
        } else {
            let n = m.outdated.count
            if n > 0 {
                Button { m.updateAll() } label: {
                    HStack(spacing: 5) { Image(systemName: "arrow.down.circle.fill"); Text("Tout mettre à jour (\(n))").fixedSize() }
                }
                    .buttonStyle(BrandButton()).help("Télécharge la dernière version de chaque jeu marqué « Mise à jour », l'un après l'autre")
            }
        }
    }
}

/// En tête de « Mises à jour » : ce qui va être mis à jour, et le bouton.
struct UpdateBanner: View {
    @EnvironmentObject var m: Model
    var body: some View {
        if m.scope == .updates, !m.outdated.isEmpty || m.updating != nil {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.brand)
                VStack(alignment: .leading, spacing: 3) {
                    let o = m.outdated
                    Text(m.updating != nil ? "Mise à jour en cours…" : "\(o.count) mise\(o.count > 1 ? "s" : "") à jour disponible\(o.count > 1 ? "s" : "")")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.frost)
                    Text(o.map { "\($0.0.name) (\($0.1.label))" }.joined(separator: " · "))
                        .font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer()
                UpdateAllButton()
            }
            .padding(16)
            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cyan.opacity(0.35)))
            .padding(.horizontal, 22).padding(.top, 18)
        }
    }
}

// MARK: Notes de version

/// Markdown de GitHub → texte lisible : titres en gras, puces, sans images ni HTML.
func notesText(_ md: String) -> AttributedString {
    var lines: [String] = []
    for raw in md.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
        var l = raw.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if l.hasPrefix("![") || l.hasPrefix("[![") { continue }
        while l.hasPrefix(">") { l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces) }   // citations GitHub
        if l.range(of: #"^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]$"#, options: .regularExpression) != nil { continue }
        if let r = l.range(of: #"^#{1,6}\s*"#, options: .regularExpression) {
            let t = l[r.upperBound...].replacingOccurrences(of: "**", with: "")
            l = t.isEmpty ? "" : "**\(t)**"
        } else if let r = l.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
            l = "•  " + l[r.upperBound...]
        }
        if l.isEmpty, lines.last?.isEmpty ?? true { continue }
        lines.append(l)
    }
    while lines.last?.isEmpty == true { lines.removeLast() }
    let text = lines.joined(separator: "\n")
    return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}

struct Changelog: View {
    @EnvironmentObject var m: Model
    let a: Recomp
    @State private var showAll = false
    var body: some View {
        let repo = a.repo ?? ""
        Section2("NOTES DE VERSION") {
            if let rels = m.notes[repo] {
                let (lv, ld) = m.localVersion(a)
                // Nouveau pour toi : les releases avant celle que tu as (par version, sinon par date).
                let mineIdx = rels.firstIndex { r in lv.map { norm($0) == norm(r.tag_name) || norm($0) == norm(r.name) } ?? false }
                let isNew: (Int, Release) -> Bool = { i, r in
                    guard lv != nil || ld != nil else { return false }
                    if let mi = mineIdx { return i < mi }
                    if let ld, let p = r.published_at { return p > ld }
                    return false
                }
                let shown = showAll ? Array(rels.enumerated()) : Array(rels.enumerated().prefix(3))
                if rels.isEmpty { Text("Aucune release publiée.").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                ForEach(shown, id: \.element.id) { i, r in
                    ReleaseCard(r: r, new: isNew(i, r), mine: mineIdx == i, expanded: i == 0)
                }
                if rels.count > 3 {
                    Button(showAll ? "Moins" : "Toutes les versions (\(rels.count))") { withAnimation { showAll.toggle() } }
                        .buttonStyle(.link).tint(Theme.cyan).font(.system(size: 12))
                }
            } else if let e = m.notesError[repo] {
                Text(e).font(.system(size: 12)).foregroundStyle(Theme.warn)
            } else {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Chargement…").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            }
        }
        .task(id: a.id) { await m.loadNotes(a) }
    }
}

struct ReleaseCard: View {
    let r: Release; let new: Bool; let mine: Bool
    @State var expanded: Bool
    init(r: Release, new: Bool, mine: Bool, expanded: Bool) { self.r = r; self.new = new; self.mine = mine; _expanded = State(initialValue: expanded) }
    var body: some View {
        let body = r.body.map(notesText) ?? AttributedString("")
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(r.tag_name).font(.system(size: 12.5, weight: .bold).monospacedDigit()).foregroundStyle(Theme.frost)
                if let n = r.name, !n.isEmpty, n != r.tag_name { Text(n).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1) }
                Spacer(minLength: 4)
                if new { Tag("nouveau", Theme.cyan) }
                if mine { Tag("ta version", Theme.ok) }
                if r.prerelease { Tag("préversion", Theme.warn) }
                if let p = r.published_at { Text(p.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "fr_FR")))).font(.system(size: 11)).foregroundStyle(Theme.muted) }
            }
            if !body.characters.isEmpty {
                Text(body).font(.system(size: 12)).foregroundStyle(Theme.frost.opacity(0.88)).textSelection(.enabled)
                    .lineLimit(expanded ? nil : 4).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(expanded ? "Réduire" : "Lire la suite") { withAnimation { expanded.toggle() } }.buttonStyle(.link).tint(Theme.cyan)
                    Spacer()
                    if let u = r.html_url.flatMap(URL.init(string:)) { Button(u.host?.contains("gitlab") == true ? "Sur GitLab" : "Sur GitHub") { NSWorkspace.shared.open(u) }.buttonStyle(.link).tint(Theme.muted) }
                }.font(.system(size: 11.5))
            }
        }
        .padding(12)
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(new ? Theme.cyan.opacity(0.45) : Theme.edge))
    }
}

struct Tag: View {
    let t: String; let c: Color
    init(_ t: String, _ c: Color) { self.t = t; self.c = c }
    var body: some View {
        Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(c)
            .padding(.horizontal, 6).padding(.vertical, 2).background(c.opacity(0.12), in: Capsule())
    }
}

// MARK: Téléchargement rapide (grille et liste)

/// Un bouton pour télécharger sans ouvrir la fiche : le système qui a une mise à jour, sinon Mac, sinon le premier proposé.
/// Les autres systèmes sont dans le petit menu à côté. Rien quand tout est déjà à jour.
struct QuickDownload: View {
    @EnvironmentObject var m: Model
    let a: Recomp; let compact: Bool
    var body: some View {
        let syss = a.sysList
        if !a.isSoon, !syss.isEmpty {
            if let d = syss.compactMap({ m.downloads[m.key(a, $0)] }).first {
                ProgressView(value: d.progress).progressViewStyle(.circular).controlSize(.small).tint(Theme.cyan)
                    .frame(width: 24, height: 24).help("Téléchargement : \(Int(d.progress * 100)) %")
            } else if let pref = syss.first(where: { m.status(a, $0) == .outdated })
                        ?? (syss.contains(.macos) && m.status(a, .macos) != .upToDate ? .macos : nil)
                        ?? syss.first(where: { m.status(a, $0) != .upToDate }) {
                let upd = m.status(a, pref) == .outdated
                let red = a.files?[pref.rawValue]?.scan == "red"
                HStack(spacing: 2) {
                    Button { m.download(a, pref) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: upd ? "arrow.triangle.2.circlepath" : "arrow.down").font(.system(size: 10.5, weight: .bold))
                            if !compact { Text(upd ? "Mettre à jour" : pref.label).lineLimit(1) }
                        }
                    }
                    .buttonStyle(QuickButton(compact: compact)).disabled(red)
                    .help(red ? "L'analyse du site a signalé ce fichier : télécharge-le depuis la fiche" : "\(upd ? "Mettre à jour" : "Télécharger") pour \(pref.label)")
                    let others = syss.filter { $0 != pref }
                    if !others.isEmpty {
                        Menu {
                            ForEach(others) { s in
                                Button("\(m.status(a, s) == .outdated ? "Mettre à jour" : "Télécharger") pour \(s.label)") { m.download(a, s) }
                                    .disabled(a.files?[s.rawValue]?.scan == "red")
                            }
                        } label: { Image(systemName: "chevron.down") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(Theme.muted)
                        .help("Autres systèmes")
                    }
                }
            }
        }
    }
}

struct QuickButton: ButtonStyle {
    let compact: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.midnight)
            .padding(.horizontal, compact ? 7 : 10).frame(height: 22)
            .background(Theme.brand, in: Capsule())
            .opacity(!enabled ? 0.35 : c.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}
