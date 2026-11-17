import AjanTakipCore
import AppKit
import SwiftUI

/// Bir projenin TODO.local.md listesini gösteren pencere içeriği.
struct TodoView: View {
    let todos: TodoManager
    let moveWindow: (NSPoint) -> Void
    let windowTopLeft: () -> NSPoint
    let contentSizeChanged: (CGSize) -> Void

    @State private var dragStart: (mouse: NSPoint, window: NSPoint)?
    @State private var newItem = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let root = todos.openRoot {
                let items = todos.files[root]?.items ?? []
                header(root: root, items: items)
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                if items.isEmpty {
                    Text(todos.files[root] == nil ? "\(TodoList.fileName) yok; ilk maddeyi ekleyince oluşur."
                                                  : "Liste boş")
                        .foregroundStyle(.white.opacity(0.55))
                } else if items.count > 14 {
                    ScrollView { list(items) }.frame(height: 340)
                } else {
                    list(items)
                }
                if let err = todos.lastError {
                    Text("⚠︎ \(err)").font(.system(size: 10)).foregroundStyle(.yellow)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let info = todos.lastInfo {
                    Text(info).font(.system(size: 10)).foregroundStyle(.green.opacity(0.85))
                }
                TextField("Yeni madde…", text: $newItem)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
                    .foregroundStyle(.white)
                    .onSubmit {
                        todos.add(newItem)
                        newItem = ""
                    }
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .font(.system(size: 12, design: .rounded))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.6)))
                .environment(\.colorScheme, .dark))
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            DispatchQueue.main.async { contentSizeChanged(size) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(root: String, items: [TodoItem]) -> some View {
        let p = TodoList.progress(items)
        return HStack(spacing: 8) {
            Text((root as NSString).lastPathComponent)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("TODO · \(p.done)/\(p.total)")
                .foregroundStyle(.white.opacity(0.75))
                .monospacedDigit()
            Spacer(minLength: 8)
            Button { todos.openInEditor() } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Dosyayı düzenleyicide aç")
            .disabled(todos.files[root] == nil)
            Button { todos.close() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Kapat")
        }
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private func list(_ items: [TodoItem]) -> some View {
        let targets = todos.targets
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: item.done ? "checkmark.square.fill" : "square")
                        .foregroundStyle(item.done ? .green : .white.opacity(0.7))
                    Text(item.text)
                        .strikethrough(item.done, color: .white.opacity(0.4))
                        .foregroundStyle(.white.opacity(item.done ? 0.45 : 0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !item.done { sendButton(item, targets: targets) }
                }
                .padding(.leading, CGFloat(item.indent) * 14)
                .contentShape(Rectangle())
                .onTapGesture { todos.toggle(item) }
            }
        }
        .frame(width: 296, alignment: .leading)
    }

    /// Maddeyi ajana gönderir: tek oturum varsa doğrudan, birden fazlaysa menüden seçilir.
    @ViewBuilder
    private func sendButton(_ item: TodoItem, targets: [Session]) -> some View {
        let icon = Image(systemName: todos.sending == item.line ? "ellipsis" : "paperplane")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(targets.isEmpty ? 0.2 : 0.55))
            .frame(width: 18, height: 14)
            .contentShape(Rectangle())
        if targets.count > 1 {
            Menu {
                ForEach(targets) { s in
                    Button("\(s.state.symbol) \(s.projectName) — \(s.activity)") { todos.send(item, to: s) }
                }
            } label: { icon }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Ajana gönder")
            .disabled(todos.sending != nil)
        } else {
            Button { if let s = targets.first { todos.send(item, to: s) } } label: { icon }
                .buttonStyle(.plain)
                .help(targets.isEmpty ? "Bu projede cmux içinde açık oturum yok" : "Ajana gönder")
                .disabled(targets.isEmpty || todos.sending != nil)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                if dragStart == nil { dragStart = (mouse, windowTopLeft()) }
                guard let s = dragStart else { return }
                moveWindow(NSPoint(x: s.window.x + mouse.x - s.mouse.x, y: s.window.y + mouse.y - s.mouse.y))
            }
            .onEnded { _ in dragStart = nil }
    }
}
