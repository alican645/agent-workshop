import AjanTakipCore
import SwiftUI

/// Bir projenin odası: üst çubuk + yan yana bölmeler, her bölmede sekmeler.
struct RoomView: View {
    let model: WorkshopModel
    let root: String

    private var room: Room { model.room(root) }
    private var name: String { (root as NSString).lastPathComponent }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if room.panes.isEmpty {
                emptyRoom
            } else {
                HSplitView {
                    ForEach(Array(room.panes.enumerated()), id: \.offset) { i, pane in
                        PaneView(model: model, root: root, index: i, pane: pane, focused: room.focusedPane == i)
                            .frame(minWidth: 240, idealWidth: 1200 * pane.width, maxWidth: .infinity)
                    }
                }
            }
        }
        .background(Theme.room)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.closeRoom() } label: { Label("atölye", systemImage: "chevron.left") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .help("Atölyeye dön (⌘0)")
            Text(name).font(.headline).foregroundStyle(Theme.text)
            Menu {
                Button("Claude  ⌘⇧T") { model.add(.claude, in: root) }
                Button("Terminal  ⌘T") { model.add(.shell, in: root) }
                Button("Markdown dosyası…") { model.addMarkdown(in: root) }
            } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Yeni Claude, terminal ya da markdown")
            Spacer()
            ForEach(model.waiting.filter { $0.zone != root }.prefix(3)) { w in
                Button { model.open(sessionID: w.id) } label: {
                    Text("⚠ \(w.zoneName) · \(w.label) seni bekliyor").font(.caption.weight(.semibold))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.waiting))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 78) // pencere düğmeleri
        .padding(.trailing, 14)
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

private struct PaneView: View {
    let model: WorkshopModel
    let root: String
    let index: Int
    let pane: Pane
    let focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Array(pane.tabs.enumerated()), id: \.offset) { j, tab in
                    TabButton(title: title(tab), running: running(tab), selected: j == pane.selected,
                              select: { model.update(root) { $0.panes[index].selected = j; $0.focusedPane = index } },
                              close: { model.close(tab, in: root) })
                }
                Spacer()
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(focused ? Theme.tabBarFocused : Theme.tabBar)
            if let tab = pane.current {
                content(tab)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        if !focused { model.update(root) { $0.focusedPane = index } }
                    })
            }
        }
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
    static let text = Color(red: 0.937, green: 0.902, blue: 0.847)
    static let muted = Color(red: 0.62, green: 0.58, blue: 0.52)
    static let waiting = Color(red: 1, green: 0.55, blue: 0.18)
    static let ok = Color(red: 0.23, green: 0.65, blue: 0.48)
}
