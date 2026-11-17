import AjanTakipCore
import AppKit
import SwiftUI

/// Atölye sahnesinin üstündeki yüzen pencereler. Pencerelerin dışındaki boşluk tıklamaları sahneye geçirir.
struct DeskView: View {
    let model: WorkshopModel
    /// Sürüklenen/boyutlanan pencerenin anlık yeri (bırakınca modele yazılır).
    @State private var live: (id: String, rect: FloatRect)?
    @State private var snapPreview: FloatRect?

    var body: some View {
        GeometryReader { g in
            let size = g.size
            ZStack(alignment: .topLeading) {
                Color.clear.allowsHitTesting(false)
                if let p = snapPreview {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.focus.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.focus.opacity(0.7), lineWidth: 2))
                        .frame(width: p.w * size.width, height: p.h * size.height)
                        .offset(x: p.x * size.width, y: p.y * size.height)
                        .allowsHitTesting(false)
                }
                ForEach(model.desk.windows.filter { !$0.minimized }) { w in
                    let r = rect(w)
                    WindowSlot(model: model, window: w, leaving: model.leaving.contains(w.id),
                               tuckOffset: tuckMove(r, root: w.root, canvas: size, origin: g.frame(in: .global).origin)) { flying in
                        FloatingWindow(model: model, window: w, front: model.desk.front?.id == w.id, canvas: size,
                                       rect: r, flying: flying, onLive: { live = ($0 == nil ? nil : (w.id, $0!)) },
                                       onSnapPreview: { snapPreview = $0 })
                    }
                    .frame(width: r.w * size.width, height: r.h * size.height)
                    .offset(x: r.x * size.width, y: r.y * size.height)
                }
                shelf.frame(maxWidth: .infinity, alignment: .trailing).padding(10)
            }
            .coordinateSpace(name: "desk")
        }
    }

    /// Pencerenin merkezini sol paneldeki projesinin başlığına taşıyan kayma (yoksa panelin ortasına).
    private func tuckMove(_ r: FloatRect, root: String, canvas: CGSize, origin: CGPoint) -> CGSize {
        let target = model.sidebarTargets[root].map { CGPoint(x: $0.midX - origin.x, y: $0.midY - origin.y) }
            ?? CGPoint(x: -125, y: canvas.height / 2)
        let cx = (r.x + r.w / 2) * canvas.width, cy = (r.y + r.h / 2) * canvas.height
        return CGSize(width: target.x - cx, height: target.y - cy)
    }

    private func rect(_ w: DeskWindow) -> FloatRect {
        if let live, live.id == w.id { return live.rect }
        return w.maximized ? .full : w.frame
    }

    /// Küçültülmüş pencerelerin rafı (sağ üst).
    private var shelf: some View {
        HStack(spacing: 6) {
            // Yalnız sol panelde yeri olmayan projelerin küçültülmüş pencereleri burada kalır.
            ForEach(model.desk.windows.filter { $0.minimized && model.sidebarTargets[$0.root] == nil }) { w in
                Button { model.changeDesk { $0.raise(w.id) } } label: {
                    HStack(spacing: 6) {
                        Circle().fill(model.zoneColor(w.root).map(Color.init(hex:)) ?? Theme.muted).frame(width: 8, height: 8)
                        Text("\((w.root as NSString).lastPathComponent) · \(model.title(w.tab))").lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.tabBar))
                    .foregroundStyle(Theme.text)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .help("Geri aç")
            }
        }
    }
}

/// Pencerenin sol panele çekilme / oradan çıkma animasyonu. Durum pencerenin kendisinde tutulur;
/// böylece animasyon modeldeki değişikliğin hangi işlemle geldiğine bağlı kalmaz ve her pencere aynı davranır.
private struct WindowSlot<Content: View>: View {
    let model: WorkshopModel
    let window: DeskWindow
    let leaving: Bool
    let tuckOffset: CGSize
    @ViewBuilder let content: (_ flying: Bool) -> Content
    /// true: pencere sol panelde (küçük); false: yerinde.
    @State private var tucked: Bool
    /// İçerik gizli mi (terminal görünümü ölçeklenmediği için uçuşta gizlenir).
    @State private var flying: Bool

    init(model: WorkshopModel, window: DeskWindow, leaving: Bool, tuckOffset: CGSize,
         @ViewBuilder content: @escaping (_ flying: Bool) -> Content) {
        self.model = model
        self.window = window
        self.leaving = leaving
        self.tuckOffset = tuckOffset
        self.content = content
        let arriving = model.arriving.contains(window.id)
        _tucked = State(initialValue: arriving || leaving)
        _flying = State(initialValue: arriving || leaving)
    }

    var body: some View {
        content(flying)
            .scaleEffect(tucked ? 0.04 : 1)
            .opacity(tucked ? 0.1 : 1)
            .offset(tucked ? tuckOffset : .zero)
            .allowsHitTesting(!tucked && !leaving)
            .onAppear {
                guard tucked, !leaving else { return }
                model.arriving.remove(window.id)
                // Bir sonraki karede başlat: panelde çizilmiş hâlinden çıkarak gelsin.
                DispatchQueue.main.async { animate(to: false) }
            }
            .onChange(of: leaving) { _, now in animate(to: now) }
    }

    private func animate(to tuck: Bool) {
        flying = true
        let curve: Animation = tuck ? .easeIn(duration: WorkshopModel.tuckDuration) : .spring(duration: 0.38, bounce: 0.15)
        withAnimation(curve) { tucked = tuck } completion: {
            if !tucked { flying = false }
        }
    }
}

/// Başlık çubuklu, taşınabilir ve boyutlandırılabilir tek pencere.
private struct FloatingWindow: View {
    let model: WorkshopModel
    let window: DeskWindow
    let front: Bool
    let canvas: CGSize
    let rect: FloatRect
    let flying: Bool
    let onLive: (FloatRect?) -> Void
    let onSnapPreview: (FloatRect?) -> Void
    @State private var start: FloatRect?

    static let titleHeight: CGFloat = 28
    static let grip: CGFloat = 6

    private var waiting: Bool { model.isWaiting(window) }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            if flying {
                Theme.room
            } else {
                TabContent(model: model, window: window, focused: front)
            }
        }
        .background(Theme.room)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(front ? Theme.focus.opacity(0.8) : Color.black.opacity(0.5), lineWidth: 1))
        .overlay { if waiting { Pulse { RoundedRectangle(cornerRadius: 9).stroke(Theme.focus, lineWidth: 2.5) } } }
        .shadow(color: .black.opacity(front ? 0.4 : 0.22), radius: front ? 16 : 8, y: 6)
        .overlay { if !window.maximized { resizeGrips } }
        .simultaneousGesture(TapGesture().onEnded { if !front { model.changeDesk { $0.raise(window.id) } } })
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Circle().fill(model.zoneColor(window.root).map(Color.init(hex:)) ?? Theme.muted).frame(width: 9, height: 9)
            Text((window.root as NSString).lastPathComponent).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text).lineLimit(1)
            Text(model.title(window.tab)).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            if waiting {
                Text("seni bekliyor").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.focus))
            }
            Spacer(minLength: 8)
            NewWindowMenu(model: model, root: window.root, tint: Theme.muted)
            chromeButton("minus", help: "Sol paneldeki yerine çek (⌘M)") { model.tuck([window.id]) }
            chromeButton(window.maximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                         help: "Tam boyut") { model.changeDesk { $0.toggleMaximize(window.id) } }
            chromeButton("xmark", help: "Kapat (⌘W)") { model.closeWindow(window.id) }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.titleHeight)
        .background(front ? Theme.tabBarFocused : Theme.tabBar)
        .background { if waiting { Pulse { Theme.focus } } }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.changeDesk { $0.toggleMaximize(window.id) } }
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("desk"))
            .onChanged { v in
                let s = start ?? beginMove(at: v.startLocation)
                start = s
                let r = FloatRect(x: s.x + v.translation.width / canvas.width, y: s.y + v.translation.height / canvas.height,
                                  w: s.w, h: s.h)
                onLive(r)
                onSnapPreview(Desk.snap(pointer: (v.location.x, v.location.y), in: (canvas.width, canvas.height)))
            }
            .onEnded { v in
                let snap = Desk.snap(pointer: (v.location.x, v.location.y), in: (canvas.width, canvas.height))
                if let s = start {
                    let moved = FloatRect(x: s.x + v.translation.width / canvas.width,
                                          y: s.y + v.translation.height / canvas.height, w: s.w, h: s.h)
                    model.changeDesk { d in
                        if snap == .full {
                            d.setFrame(window.id, s)
                            d.toggleMaximize(window.id)
                        } else {
                            d.setFrame(window.id, snap ?? moved)
                            d.raise(window.id)
                        }
                    }
                }
                start = nil
                onLive(nil)
                onSnapPreview(nil)
            })
    }

    /// Tam boyuttaki pencere sürüklenince eski boyutuna döner ve imlecin altına gelir.
    private func beginMove(at p: CGPoint) -> FloatRect {
        guard window.maximized else { return rect }
        let f = window.frame
        return FloatRect(x: p.x / canvas.width - f.w / 2, y: max(0, p.y / canvas.height - 0.01), w: f.w, h: f.h)
    }

    private func chromeButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                .frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Boyutlandırma

    private var resizeGrips: some View {
        let g = Self.grip
        return ZStack {
            grip(dx: -1, dy: 0).frame(width: g).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            grip(dx: 1, dy: 0).frame(width: g).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            grip(dx: 0, dy: -1).frame(height: g).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            grip(dx: 0, dy: 1).frame(height: g).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            grip(dx: -1, dy: -1).frame(width: g * 2, height: g * 2).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            grip(dx: 1, dy: -1).frame(width: g * 2, height: g * 2).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            grip(dx: -1, dy: 1).frame(width: g * 2, height: g * 2).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            grip(dx: 1, dy: 1).frame(width: g * 2, height: g * 2).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    /// `dx`/`dy`: hangi kenar (-1 sol/üst, 1 sağ/alt, 0 yok).
    private func grip(dx: Int, dy: Int) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { Self.cursor(dx: dx, dy: dy).push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("desk"))
                .onChanged { v in
                    let s = start ?? rect
                    start = s
                    onLive(resized(s, dx: dx, dy: dy, by: v.translation))
                }
                .onEnded { v in
                    if let s = start {
                        let r = resized(s, dx: dx, dy: dy, by: v.translation)
                        model.changeDesk { d in
                            d.setFrame(window.id, r)
                            d.raise(window.id)
                        }
                    }
                    start = nil
                    onLive(nil)
                })
    }

    private func resized(_ s: FloatRect, dx: Int, dy: Int, by t: CGSize) -> FloatRect {
        let mx = t.width / canvas.width, my = t.height / canvas.height
        let minW = max(Desk.minSize, 320 / canvas.width), minH = max(Desk.minSize, 160 / canvas.height)
        var r = s
        if dx == 1 { r.w = max(minW, s.w + mx) }
        if dx == -1 { let w = max(minW, s.w - mx); r.x = s.x + s.w - w; r.w = w }
        if dy == 1 { r.h = max(minH, s.h + my) }
        if dy == -1 { let h = max(minH, s.h - my); r.y = s.y + s.h - h; r.h = h }
        return r
    }

    private static func cursor(dx: Int, dy: Int) -> NSCursor {
        switch (dx, dy) {
        case (_, 0): .resizeLeftRight
        case (0, _): .resizeUpDown
        case (-1, -1), (1, 1): .frameResize(position: dx < 0 ? .topLeft : .bottomRight, directions: .all)
        default: .frameResize(position: dx < 0 ? .bottomLeft : .topRight, directions: .all)
        }
    }
}

/// Projede yeni pencere: Claude, terminal, Git, markdown.
struct NewWindowMenu: View {
    let model: WorkshopModel
    let root: String
    let tint: Color

    var body: some View {
        Menu {
            Button("Yeni Claude oturumu  ⌘⇧T") { model.newWindow(.claude, in: root) }
            if model.profiles.profiles.count > 1 {
                Menu("Başka profille Claude") {
                    ForEach(model.profiles.profiles.filter { $0.id != model.profiles.active.id }) { p in
                        Button(p.name + (p.email.map { " · \($0)" } ?? "")) { model.newWindow(.claude, in: root, profile: p.id) }
                    }
                }
            }
            Button("Yeni terminal  ⌘T") { model.newWindow(.shell, in: root) }
            Divider()
            Button("Git") { model.addGit(in: root) }
            Button("Markdown dosyası…") { model.addMarkdown(in: root) }
        } label: {
            Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 20, height: 20)
        .help("\((root as NSString).lastPathComponent) projesinde yeni pencere")
    }
}

/// İçeriği yavaşça yanıp söndürür (dikkat çekmek için).
struct Pulse<Content: View>: View {
    var low = 0.15
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .phaseAnimator([low, 0.9]) { c, p in c.opacity(p) } animation: { _ in .easeInOut(duration: 0.75) }
            .allowsHitTesting(false)
    }
}

/// Pencerenin içeriği: terminal, markdown ya da Git.
private struct TabContent: View {
    let model: WorkshopModel
    let window: DeskWindow
    let focused: Bool

    var body: some View {
        switch window.tab {
        case let .terminal(id):
            TerminalPane(host: model.host, id: id, focused: focused)
                .overlay(alignment: .bottom) {
                    if let t = model.host.terminals[id], !t.running {
                        HStack {
                            Text("işlem bitti" + (t.exitCode.map { " (kod \($0))" } ?? ""))
                            Button("Kapat") { model.closeWindow(window.id) }
                        }
                        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding()
                    }
                }
        case let .markdown(path):
            MarkdownPane(path: path)
        case let .git(r):
            GitPane(root: r)
        }
    }
}

enum Theme {
    static let room = Color(red: 0.165, green: 0.149, blue: 0.133)
    static let bar = Color(red: 0.953, green: 0.914, blue: 0.855)
    static let tabBar = Color(red: 0.22, green: 0.20, blue: 0.18)
    static let tabBarFocused = Color(red: 0.27, green: 0.24, blue: 0.21)
    static let tabSelected = Color(red: 0.165, green: 0.149, blue: 0.133)
    static let focus = Color(red: 1, green: 0.62, blue: 0.27)
    static let barText = Color(red: 0.17, green: 0.16, blue: 0.15)
    static let barMuted = Color(red: 0.42, green: 0.39, blue: 0.35)
    static let text = Color(red: 0.937, green: 0.902, blue: 0.847)
    static let muted = Color(red: 0.62, green: 0.58, blue: 0.52)
    static let ok = Color(red: 0.23, green: 0.65, blue: 0.48)
}
