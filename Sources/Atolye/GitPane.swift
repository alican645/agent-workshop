import AtolyeCore
import SwiftUI

/// Salt okunur git görünümü: solda değişen dosyalar ve son commit'ler, sağda seçilenin diff'i.
/// Hiçbir yazma komutu çalıştırmaz; liste 3 sn'de bir tazelenir.
struct GitPane: View {
    let root: String
    @State private var status: GitStatus?
    @State private var log: [GitCommit] = []
    @State private var loaded = false
    @State private var selection: GitRunner.Target?
    @State private var diff: [DiffLine] = []
    @State private var loadingDiff = false

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if loaded && status == nil {
                Text(L("Bu proje bir git deposu değil.")).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    sidebar.frame(minWidth: 220, idealWidth: 300, maxWidth: 460)
                    diffView.frame(minWidth: 260, maxWidth: .infinity)
                }
            }
        }
        .background(Theme.room)
        .task { await reload() }
        .onReceive(timer) { _ in Task { await reload() } }
        .onChange(of: selection) { Task { await loadDiff() } }
    }

    // MARK: Sol liste

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if let s = status {
                    header(s)
                    section(L("HAZIRLANMIŞ"), s.staged) { .staged($0) }
                    section(L("DEĞİŞMİŞ"), s.unstaged) { .unstaged($0) }
                    section(L("YENİ"), s.untracked) { .untracked($0) }
                    if s.changedCount == 0 { note(L("Çalışma alanı temiz")) }
                }
                title(L("SON COMMIT'LER"))
                ForEach(log, id: \.hash) { c in commitRow(c) }
            }
            .padding(.vertical, 8)
        }
        .background(Theme.tabBar)
    }

    private func header(_ s: GitStatus) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("⎇ " + (s.branch ?? "?")).font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.text)
            HStack(spacing: 8) {
                if let u = s.upstream { Text(u) } else { Text(L("uzak dal yok")) }
                if s.ahead > 0 { Text(L("↑{0} itilmemiş", "\(s.ahead)")).foregroundStyle(Theme.ok) }
                if s.behind > 0 { Text(L("↓{0} gelen", "\(s.behind)")).foregroundStyle(GitColors.hunk) }
            }
            .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    @ViewBuilder
    private func section(_ name: String, _ files: [GitFileChange], target: @escaping (String) -> GitRunner.Target) -> some View {
        if !files.isEmpty {
            title("\(name) · \(files.count)")
            ForEach(files, id: \.self) { f in
                let t = target(f.path)
                row(selected: selection == t) {
                    HStack(spacing: 7) {
                        Text(f.code).font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(GitColors.code(f.code)).frame(width: 12)
                        Text((f.path as NSString).lastPathComponent).foregroundStyle(Theme.text).lineLimit(1)
                        Text((f.path as NSString).deletingLastPathComponent).foregroundStyle(Theme.muted)
                            .lineLimit(1).truncationMode(.head)
                    }
                    .font(.system(size: 12))
                    .help(f.origPath.map { "\($0) → \(f.path)" } ?? f.path)
                } action: { selection = t }
            }
        }
    }

    private func commitRow(_ c: GitCommit) -> some View {
        row(selected: selection == .commit(c.hash)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(c.subject).font(.system(size: 12)).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 6) {
                    Text(c.short).font(.system(size: 10, design: .monospaced))
                    Text(c.author)
                    Text(c.date, format: .relative(presentation: .named))
                }
                .font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
            }
        } action: { selection = .commit(c.hash) }
    }

    private func row(selected: Bool, @ViewBuilder _ content: () -> some View, action: @escaping () -> Void) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(selected ? Theme.tabSelected : .clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private func title(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Theme.muted)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 3)
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.horizontal, 12).padding(.vertical, 4)
    }

    // MARK: Diff

    private var diffView: some View {
        Group {
            if selection == nil {
                Text(L("Soldan bir dosya ya da commit seç")).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diff.isEmpty && !loadingDiff {
                Text(L("Gösterilecek fark yok")).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.enumerated()), id: \.offset) { _, l in
                            Text(l.text.isEmpty ? " " : l.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(GitColors.text(l.kind))
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(GitColors.background(l.kind))
                        }
                    }
                    .padding(.vertical, 6)
                    .textSelection(.enabled)
                }
            }
        }
        .background(Theme.room)
    }

    // MARK: Yükleme (arka planda)

    private func reload() async {
        let r = root
        let (s, l) = await Task.detached(priority: .utility) { (GitRunner.status(r), GitRunner.log(r, limit: 50)) }.value
        let changed = s != status
        status = s
        log = l
        loaded = true
        if let sel = selection, !stillExists(sel) { selection = nil } else if changed { await loadDiff() }
    }

    private func stillExists(_ t: GitRunner.Target) -> Bool {
        guard let s = status else { return false }
        switch t {
        case let .staged(p): return s.staged.contains { $0.path == p }
        case let .unstaged(p): return s.unstaged.contains { $0.path == p }
        case let .untracked(p): return s.untracked.contains { $0.path == p }
        case let .commit(h): return log.contains { $0.hash == h }
        }
    }

    private func loadDiff() async {
        guard let t = selection else { diff = []; return }
        loadingDiff = true
        let r = root
        let lines = await Task.detached(priority: .userInitiated) { GitRunner.diff(t, in: r) }.value
        if selection == t { diff = lines }
        loadingDiff = false
    }
}

enum GitColors {
    static let add = Color(red: 0.55, green: 0.85, blue: 0.62)
    static let del = Color(red: 0.97, green: 0.55, blue: 0.52)
    static let hunk = Color(red: 0.55, green: 0.70, blue: 1.0)

    static func text(_ k: DiffLine.Kind) -> Color {
        switch k {
        case .add: add
        case .del: del
        case .hunk: hunk
        case .meta: Theme.muted
        case .context: Theme.text
        }
    }

    static func background(_ k: DiffLine.Kind) -> Color {
        switch k {
        case .add: Color(red: 0.2, green: 0.45, blue: 0.28).opacity(0.28)
        case .del: Color(red: 0.55, green: 0.2, blue: 0.2).opacity(0.28)
        case .hunk: Color(red: 0.25, green: 0.33, blue: 0.5).opacity(0.25)
        default: .clear
        }
    }

    static func code(_ c: String) -> Color {
        switch c {
        case "A", "?": add
        case "D": del
        case "U": Theme.focus
        case "R", "C": hunk
        default: Color(red: 0.95, green: 0.78, blue: 0.4)
        }
    }
}
