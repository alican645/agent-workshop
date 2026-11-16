import AjanTakipCore
import SwiftUI
import UniformTypeIdentifiers

/// Bir projenin odası: üst çubuk + iç içe bölünmüş bölmeler (cmux gibi). Sekmeler sürüklenip
/// bir bölmenin kenarına (bölünür) ya da ortasına/sekme çubuğuna (sekme olur) bırakılabilir.
struct RoomView: View {
    let model: WorkshopModel
    let root: String

    private var room: Room { model.room(root) }
    private var name: String { (root as NSString).lastPathComponent }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let node = room.root {
                NodeView(model: model, root: root, node: node)
            } else {
                emptyRoom
            }
        }
        .background(Theme.room)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.closeRoom() } label: { Label("atölye", systemImage: "chevron.left") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.barMuted)
                .help("Atölyeye dön (⌘0)")
            Text(name).font(.headline).foregroundStyle(Theme.barText).lineLimit(1)
            Menu {
                Button("Claude sekmesi  ⌘⇧T") { model.add(.claude, in: root) }
                Button("Terminal sekmesi  ⌘T") { model.add(.shell, in: root) }
                Divider()
                Button("Sağa böl  ⌘D") { model.split(.shell, in: root, edge: .right) }
                Button("Aşağı böl  ⌘⇧D") { model.split(.shell, in: root, edge: .bottom) }
                Divider()
                Button("Markdown dosyası…") { model.addMarkdown(in: root) }
            } label: { Image(systemName: "plus").foregroundStyle(Theme.barText) }
                .menuStyle(.borderlessButton)
                .tint(Theme.barText)
                .fixedSize()
                .help("Yeni sekme, bölme ya da markdown")
            Spacer()
            Text("sekmeyi sürükle: bölmenin kenarına bırak → böl · ortasına → sekme yap")
                .font(.caption).foregroundStyle(Theme.barMuted).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Theme.bar)
    }

    private var emptyRoom: some View {
        VStack(spacing: 14) {
            Text("\(name) odası boş").font(.title3).foregroundStyle(Theme.text)
            HStack {
                Button("Claude başlat") { model.add(.claude, in: root) }.keyboardShortcut(.defaultAction)
                Button("Terminal aç") { model.add(.shell, in: root) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Ağacın bir düğümü: bölme ya da iki çocuklu bölünme.
private struct NodeView: View {
    let model: WorkshopModel
    let root: String
    let node: LayoutNode

    var body: some View {
        switch node {
        case let .pane(p):
            AnyView(PaneView(model: model, root: root, pane: p, focused: model.room(root).focusedPaneID == p.id).id(p.id))
        case let .split(id, axis, ratio, a, b):
            AnyView(SplitView(axis: axis, ratio: ratio, onCommit: { r in model.update(root) { $0.setRatio(id, r) } },
                              first: NodeView(model: model, root: root, node: a),
                              second: NodeView(model: model, root: root, node: b))
                .id(id))
        }
    }
}

/// İki çocuk ve aralarında sürüklenebilir bir ayraç.
private struct SplitView<A: View, B: View>: View {
    let axis: SplitAxis
    let ratio: Double
    let onCommit: (Double) -> Void
    let first: A
    let second: B
    @State private var live: Double?

    private static var gap: CGFloat { 5 }

    var body: some View {
        GeometryReader { g in
            let horizontal = axis == .horizontal
            let total = max(1, horizontal ? g.size.width : g.size.height)
            let a = max(0, total * (live ?? ratio) - Self.gap / 2)
            let b = max(0, total - a - Self.gap)
            let layout = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                first.frame(width: horizontal ? a : nil, height: horizontal ? nil : a)
                Rectangle().fill(Theme.divider)
                    .frame(width: horizontal ? Self.gap : nil, height: horizontal ? nil : Self.gap)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(coordinateSpace: .named("split"))
                        .onChanged { v in
                            let p = horizontal ? v.location.x : v.location.y
                            live = min(0.9, max(0.1, Double(p / total)))
                        }
                        .onEnded { _ in
                            if let live { onCommit(live) }
                            live = nil
                        })
                second.frame(width: horizontal ? b : nil, height: horizontal ? nil : b)
            }
            .coordinateSpace(name: "split")
        }
    }
}

private struct PaneView: View {
    let model: WorkshopModel
    let root: String
    let pane: Pane
    let focused: Bool
    @State private var dropEdge: DropEdge?
    @State private var tabBarTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            GeometryReader { g in
                ZStack {
                    if let tab = pane.current { content(tab) }
                    if let dropEdge { DropHighlight(edge: dropEdge, size: g.size) }
                }
                .onDrop(of: [TabDrag.type], delegate: PaneDrop(model: model, root: root, paneID: pane.id,
                                                              size: g.size, edge: $dropEdge))
            }
        }
        .overlay(Rectangle().stroke(focused ? Theme.focus.opacity(0.7) : .clear, lineWidth: 1))
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Array(pane.tabs.enumerated()), id: \.element) { j, tab in
                TabButton(title: title(tab), running: running(tab), selected: j == pane.selected,
                          select: { model.update(root) { $0.select(j, inPane: pane.id) } },
                          close: { model.close(tab, in: root) })
                    .onDrag { TabDrag.begin(tab, model: model) }
                    .onDrop(of: [TabDrag.type], isTargeted: nil) { _ in
                        model.dropTab(in: root, to: pane.id, edge: .center, index: j)
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(tabBarTargeted ? Theme.focus.opacity(0.25) : (focused ? Theme.tabBarFocused : Theme.tabBar))
        .onDrop(of: [TabDrag.type], isTargeted: $tabBarTargeted) { _ in
            model.dropTab(in: root, to: pane.id, edge: .center, index: nil)
        }
        .onTapGesture { model.update(root) { $0.focusPane(pane.id) } }
    }

    @ViewBuilder private func content(_ tab: RoomTab) -> some View {
        switch tab {
        case let .terminal(id):
            TerminalPane(host: model.host, id: id, focused: focused)
                .overlay(alignment: .bottom) {
                    if let t = model.host.terminals[id], !t.running {
                        HStack {
                            Text("işlem bitti" + (t.exitCode.map { " (kod \($0))" } ?? ""))
                            Button("Kapat") { model.close(tab, in: root) }
                        }
                        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding()
                    }
                }
        case let .markdown(path):
            MarkdownPane(path: path)
        }
    }

    private func title(_ tab: RoomTab) -> String {
        switch tab {
        case let .terminal(id): model.host.title(id)
        case let .markdown(path): (path as NSString).lastPathComponent
        }
    }

    private func running(_ tab: RoomTab) -> Bool {
        if case let .terminal(id) = tab { return model.host.terminals[id]?.running ?? false }
        return true
    }
}

/// Sürüklenen sekme: veri uygulama içinde kalır, sekmenin kendisi modelde tutulur.
@MainActor
enum TabDrag {
    static let type = UTType(exportedAs: "com.ajantakip.atolye.tab")

    static func begin(_ tab: RoomTab, model: WorkshopModel) -> NSItemProvider {
        model.draggingTab = tab
        let p = NSItemProvider()
        p.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { done in
            done(Data(), nil)
            return nil
        }
        return p
    }
}

/// Bölmenin içinde imlecin konumuna göre kenar/orta seçer: kenarlara %25'ten yakınsa o kenar.
private struct PaneDrop: DropDelegate {
    let model: WorkshopModel
    let root: String
    let paneID: String
    let size: CGSize
    @Binding var edge: DropEdge?

    static func edge(at p: CGPoint, in size: CGSize) -> DropEdge {
        let x = p.x / max(size.width, 1), y = p.y / max(size.height, 1)
        let d: [(CGFloat, DropEdge)] = [(x, .left), (1 - x, .right), (y, .top), (1 - y, .bottom)]
        let nearest = d.min { $0.0 < $1.0 }!
        return nearest.0 < 0.25 ? nearest.1 : .center
    }

    func validateDrop(info: DropInfo) -> Bool { MainActor.assumeIsolated { model.draggingTab != nil } }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        edge = Self.edge(at: info.location, in: size)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { edge = nil }

    func performDrop(info: DropInfo) -> Bool {
        let e = Self.edge(at: info.location, in: size)
        edge = nil
        return MainActor.assumeIsolated { model.dropTab(in: root, to: paneID, edge: e, index: nil) }
    }
}

/// Bırakılacak yeri gösteren yarı saydam alan.
private struct DropHighlight: View {
    let edge: DropEdge
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        let rect: CGRect = switch edge {
        case .center: CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: 8, dy: 8)
        case .left: CGRect(x: 0, y: 0, width: w / 2, height: h)
        case .right: CGRect(x: w / 2, y: 0, width: w / 2, height: h)
        case .top: CGRect(x: 0, y: 0, width: w, height: h / 2)
        case .bottom: CGRect(x: 0, y: h / 2, width: w, height: h / 2)
        }
        RoundedRectangle(cornerRadius: 6)
            .fill(Theme.focus.opacity(0.22))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.focus, lineWidth: 2))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

private struct TabButton: View {
    let title: String
    let running: Bool
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(running ? Theme.ok : Theme.muted).frame(width: 6, height: 6)
            Text(title).lineLimit(1).font(.system(size: 12))
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .opacity(hover || selected ? 1 : 0)
        }
        .padding(.horizontal, 10).frame(height: 24).frame(maxWidth: 220)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.tabSelected : .clear))
        .foregroundStyle(selected ? Theme.text : Theme.muted)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: select)
    }
}

enum Theme {
    static let room = Color(red: 0.165, green: 0.149, blue: 0.133)
    static let bar = Color(red: 0.953, green: 0.914, blue: 0.855)
    static let tabBar = Color(red: 0.22, green: 0.20, blue: 0.18)
    static let tabBarFocused = Color(red: 0.27, green: 0.24, blue: 0.21)
    static let tabSelected = Color(red: 0.165, green: 0.149, blue: 0.133)
    static let divider = Color(red: 0.12, green: 0.11, blue: 0.10)
    static let focus = Color(red: 1, green: 0.62, blue: 0.27)
    static let barText = Color(red: 0.17, green: 0.16, blue: 0.15)
    static let barMuted = Color(red: 0.42, green: 0.39, blue: 0.35)
    static let text = Color(red: 0.937, green: 0.902, blue: 0.847)
    static let muted = Color(red: 0.62, green: 0.58, blue: 0.52)
    static let ok = Color(red: 0.23, green: 0.65, blue: 0.48)
}
