import AtolyeCore
import SwiftUI

/// Yapılacaklar penceresi: solda atölyedeki projeler, sağda seçili projenin `TODO.local.md` maddeleri
/// ve dosyanın git'te paylaşılıp paylaşılmayacağı.
struct TodoWindow: View {
    let model: WorkshopModel
    private var todos: Todos { model.todos }
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            ProjectList(model: model)
                .frame(width: 220)
            Divider()
            if let root = todos.root {
                TodoDetail(model: model, todos: todos, name: zoneName(root), root: root)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "checklist").font(.system(size: 30)).foregroundStyle(Theme.focus)
                    Text(L("Soldan bir proje seç")).foregroundStyle(GHTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 680, minHeight: 420)
        .background(GHTheme.background)
        .foregroundStyle(GHTheme.text)
        .onAppear {
            if todos.root == nil { todos.select(model.snapshot?.zones.first?.id) }
        }
        .onReceive(refresh) { _ in todos.reload() }
    }

    private func zoneName(_ root: String) -> String {
        model.snapshot?.zones.first { $0.id == root }?.name ?? (root as NSString).lastPathComponent
    }
}

/// Atölyedeki projeler ve açık madde sayıları.
private struct ProjectList: View {
    let model: WorkshopModel

    var body: some View {
        let zones = model.snapshot?.zones ?? []
        VStack(alignment: .leading, spacing: 2) {
            Text(L("PROJELER")).font(.system(size: 10, weight: .bold)).kerning(1.2).foregroundStyle(GHTheme.muted)
                .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(zones, id: \.id) { z in
                        let open = z.todos.filter { !$0.done }.count
                        let selected = model.todos.root == z.id
                        Button { model.todos.select(z.id) } label: {
                            HStack(spacing: 8) {
                                Circle().fill(Color(hex: z.color)).frame(width: 9, height: 9)
                                Text(z.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 4)
                                if open > 0 {
                                    Text("\(open)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Capsule().fill(selected ? Theme.focus.opacity(0.25) : Color.black.opacity(0.06)))
                                }
                            }
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.black.opacity(0.07) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
            }
            if zones.isEmpty {
                Text(L("Atölyede proje yok")).font(.callout).foregroundStyle(GHTheme.muted).padding(10)
            }
            Spacer(minLength: 0)
        }
        .background(Color.black.opacity(0.025))
    }
}

/// Seçili projenin maddeleri.
private struct TodoDetail: View {
    let model: WorkshopModel
    let todos: Todos
    let name: String
    let root: String
    @State private var newText = ""
    @State private var editing: Int?
    @State private var editText = ""
    @State private var askShare: Bool?
    @FocusState private var addFocused: Bool
    @FocusState private var editFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            gitRow
            Divider().padding(.top, 12)
            if let error = todos.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .padding(.horizontal, 20).padding(.top, 10)
            }
            list
            Divider()
            addRow
        }
        .alert(askShare == true ? L("TODO.local.md git'e eklensin mi?") : L("TODO.local.md git'ten çıkarılsın mı?"),
               isPresented: Binding(get: { askShare != nil }, set: { if !$0 { askShare = nil } })) {
            if askShare == true {
                Button(L("Git'e ekle")) { todos.setShared(true) }
            } else {
                Button(L("Git'ten çıkar"), role: .destructive) { todos.setShared(false) }
            }
            Button(L("Vazgeç"), role: .cancel) {}
        } message: {
            Text(askShare == true
                 ? L("Dosya hazırlanır ve bir sonraki commit'le birlikte push edilir. Bir kez push edildikten sonra git'ten çıkarsan da maddelerin geçmiş commit'lerde ve GitHub'da görünmeye devam eder.")
                 : L("Dosya ve maddelerin bu Mac'te kalır; bundan sonraki commit'lerde olmaz. Daha önce push edilmiş halleri geçmiş commit'lerde ve GitHub'da görünmeye devam eder."))
        }
    }

    private var header: some View {
        let done = todos.items.filter(\.done).count
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 20, weight: .bold))
                Text(root).font(.caption).foregroundStyle(GHTheme.muted).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            if !todos.items.isEmpty {
                Text(L("{0}/{1} bitti", "\(done)", "\(todos.items.count)"))
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(GHTheme.muted)
            }
        }
        .padding(.horizontal, 20).padding(.top, 18)
    }

    private var gitRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(GHTheme.muted).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Git'e ekle")).font(.system(size: 13, weight: .semibold))
                Text(gitNote).font(.caption).foregroundStyle(GHTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if todos.gitBusy { ProgressView().controlSize(.small) }
            Toggle("", isOn: Binding(get: { todos.git == .shared }, set: { askShare = $0 }))
                .toggleStyle(.switch).labelsHidden()
                .disabled(todos.git == nil || todos.git == .notRepo || todos.gitBusy)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(GHTheme.card))
        .padding(.horizontal, 20).padding(.top, 12)
    }

    private var gitNote: String {
        switch todos.git {
        case .notRepo: L("Bu proje bir git deposu değil.")
        case .local: L("Kapalı: TODO.local.md yalnız bu Mac'te; git onu yok sayar.")
        case .shared: L("Açık: TODO.local.md git'te; commit'lerle birlikte push edilir.")
        case nil: "…"
        }
    }

    private var list: some View {
        Group {
            if todos.items.isEmpty {
                Text(L("Henüz madde yok. Aşağıdan ekleyebilirsin."))
                    .foregroundStyle(GHTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(todos.items.enumerated()), id: \.element.line) { i, item in
                        row(item)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove { from, to in
                        if let f = from.first { todos.move(from: f, to: to) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(spacing: 9) {
            Button { todos.toggle(item) } label: {
                Image(systemName: item.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(item.done ? Theme.ok : GHTheme.muted)
            }
            .buttonStyle(.plain)
            if editing == item.line {
                TextField("", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .focused($editFocused)
                    .onSubmit { finishEdit(item) }
                    .onExitCommand { editing = nil }
                    .onChange(of: editFocused) { _, f in if !f, editing == item.line { finishEdit(item) } }
            } else {
                Text(item.text)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? GHTheme.muted : GHTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { startEdit(item) }
            }
            TaskStatus(model: model, root: root, item: item)
            RowActions(item: item, todos: todos)
            Button { model.giveTask(item, items: todos.items, root: root) } label: {
                Label(L("Robota ver"), systemImage: "figure.walk")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.focus.opacity(item.done ? 0.08 : 0.18)))
            }
            .buttonStyle(.plain)
            .disabled(item.done)
            .help(L("Bu projede yeni bir Claude oturumu açılır ve madde ilk mesaj olarak gönderilir"))
        }
        .font(.system(size: 13))
        .padding(.leading, CGFloat(item.indent) * 22)
        .padding(.vertical, 2)
        .contextMenu {
            Button(L("Düzenle")) { startEdit(item) }
            Button(L("Girintiyi artır")) { todos.indent(item, by: 1) }
            Button(L("Girintiyi azalt")) { todos.indent(item, by: -1) }.disabled(item.indent == 0)
            Divider()
            Button(L("Sil"), role: .destructive) { todos.delete(item) }
        }
    }

    private func startEdit(_ item: TodoItem) {
        editText = item.text
        editing = item.line
        editFocused = true
    }

    private func finishEdit(_ item: TodoItem) {
        editing = nil
        let t = editText.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty, t != item.text { todos.edit(item, to: t) }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").foregroundStyle(Theme.focus)
            TextField(L("Yeni madde, Enter ile ekle"), text: $newText)
                .textFieldStyle(.plain)
                .focused($addFocused)
                .onSubmit {
                    let t = newText.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    todos.add(t)
                    newText = ""
                    addFocused = true
                }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 20).padding(.vertical, 12)
        .onAppear { addFocused = true }
    }
}

/// Robota verilmiş maddenin yanında robotun durumu; tıklayınca terminali öne gelir.
private struct TaskStatus: View {
    let model: WorkshopModel
    let root: String
    let item: TodoItem

    var body: some View {
        if let tid = model.todoTasks[WorkshopModel.taskKey(root: root, text: item.text)], model.terminalAlive(tid) {
            let robot = model.robot(onTerminal: tid)
            Button { model.openTerminal(tid) } label: {
                HStack(spacing: 5) {
                    Circle().fill(color(robot?.state)).frame(width: 7, height: 7)
                    Text(text(robot?.state)).font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help(L("Terminalini öne getir"))
        }
    }

    private func text(_ state: String?) -> String {
        switch state {
        case "busy": L("çalışıyor")
        case "waiting": L("seni bekliyor")
        case "done": L("bitti")
        case "idle": L("boşta")
        default: L("başlıyor…")
        }
    }

    private func color(_ state: String?) -> Color {
        switch state {
        case "busy": Color(red: 0.18, green: 0.65, blue: 0.84)
        case "waiting": Color(red: 1, green: 0.55, blue: 0.18)
        case "done": Theme.ok
        default: Color(red: 0.7, green: 0.66, blue: 0.6)
        }
    }
}

/// Satırın üstüne gelince görünen girinti ve silme düğmeleri.
private struct RowActions: View {
    let item: TodoItem
    let todos: Todos
    @State private var hover = false

    var body: some View {
        HStack(spacing: 2) {
            button("decrease.indent", L("Girintiyi azalt")) { todos.indent(item, by: -1) }.disabled(item.indent == 0)
            button("increase.indent", L("Girintiyi artır")) { todos.indent(item, by: 1) }
            button("trash", L("Sil")) { todos.delete(item) }
        }
        .opacity(hover ? 1 : 0.35)
        .onHover { hover = $0 }
    }

    private func button(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(GHTheme.muted).frame(width: 22, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
