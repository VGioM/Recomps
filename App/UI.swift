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
            Text(a.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.frost).lineLimit(1)
            Text(subtitle(m, a)).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
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
        } message: { Text("Vérifie le dépôt GitHub du projet avant de l'ouvrir.") }
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
                    FlowChips(items: [m.origins[a.origin ?? ""], genreFR[a.genre ?? ""], a.author.map { "par " + $0 }, a.license].compactMap { $0 })
                    if !a.isSoon {
                        HStack(spacing: 14) {
                            Stat(k: "Version", v: a.version.map { norm($0) ?? $0 } ?? "?")
                            Stat(k: "Sortie", v: day(a.released))
                            if let sz = a.size, !sz.isEmpty { Stat(k: "Taille", v: sz) }
                            if let d = a.downloads { Stat(k: "Téléch.", v: d.formatted(.number.notation(.compactName))) }
                        }
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
                        if let r = a.repo, let u = URL(string: "https://github.com/\(r)") {
                            Button("GitHub") { NSWorkspace.shared.open(u) }.buttonStyle(GhostButton())
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: 18)], alignment: .leading, spacing: 22) {
                        ForEach(list) { a in Card(a: a, selected: selection == a.id).onTapGesture { selection = a.id } }
                    }.padding(22)
                } else {
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
            .background(Theme.midnight)
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
                    Picker("Affichage", selection: $grid) {
                        Image(systemName: "square.grid.2x2").tag(true)
                        Image(systemName: "list.bullet").tag(false)
                    }.pickerStyle(.segmented).help("Grille ou liste")
                    Button { Task { await m.refresh() } } label: {
                        if m.loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                    }.help("Actualiser le catalogue et les dossiers")
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
    }
    var body: some Scene {
        WindowGroup("Recomps") {
            ContentView().environmentObject(m).frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(.dark).tint(Theme.cyan)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in m.rescan() }
        }
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
