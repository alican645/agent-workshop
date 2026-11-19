import AtolyeCore
import SwiftUI

/// Çalıştırma kartları penceresi: solda projeler, sağda seçili projenin kartları (`RUN.local.json`).
struct RunCardsWindow: View {
    let model: WorkshopModel
    private var runCards: RunCardsModel { model.runCards }
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            ProjectList(model: model, selected: runCards.root, onSelect: { runCards.select($0) },
                        badge: { $0.cards.count })
                .frame(width: 220)
            Divider()
            if let root = runCards.root {
                RunCardsDetail(model: model, runCards: runCards, root: root, name: zoneName(root))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "gearshape.2").font(.system(size: 30)).foregroundStyle(Theme.focus)
                    Text(L("Soldan bir proje seç")).foregroundStyle(GHTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .background(GHTheme.background)
        .foregroundStyle(GHTheme.text)
        .onAppear {
            if runCards.root == nil { runCards.select(model.snapshot?.zones.first?.id) }
        }
        .onReceive(refresh) { _ in runCards.reload() }
    }

    private func zoneName(_ root: String) -> String {
        model.snapshot?.zones.first { $0.id == root }?.name ?? (root as NSString).lastPathComponent
    }
}

private struct RunCardsDetail: View {
    let model: WorkshopModel
    let runCards: RunCardsModel
    let root: String
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 20, weight: .bold))
                Text(root).font(.caption).foregroundStyle(GHTheme.muted).lineLimit(1).truncationMode(.head)
                Text(L("Komut proje klasöründe çalışır; çıktısı bir terminal penceresinde görünür."))
                    .font(.caption).foregroundStyle(GHTheme.muted).padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
            Divider()
            if let error = runCards.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .padding(.horizontal, 20).padding(.top, 10)
            }
            if runCards.cards.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "gearshape").font(.system(size: 26)).foregroundStyle(GHTheme.muted)
                    Text(L("Henüz kart yok. ./deploy.sh gibi sık çalıştırdığın bir komutu ekle."))
                        .foregroundStyle(GHTheme.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(runCards.cards) { card in
                        CardRow(model: model, runCards: runCards, root: root, card: card)
                            .listRowSeparator(.visible)
                    }
                    .onMove { runCards.move(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            Divider()
            Button { runCards.add() } label: {
                Label(L("Kart ekle"), systemImage: "plus")
            }
            .buttonStyle(.plain).foregroundStyle(Theme.focus)
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }
}

/// Bir kart: ad, komut, "önce sor", durum ve Çalıştır. Alanlar Enter'da ya da odak çıkınca kaydedilir.
private struct CardRow: View {
    let model: WorkshopModel
    let runCards: RunCardsModel
    let root: String
    let card: RunCard
    @State private var name = ""
    @State private var command = ""
    @FocusState private var focus: Field?

    private enum Field { case name, command }

    var body: some View {
        let state = RunCards.state(of: model.runTerminal(card: card.id, root: root))
        HStack(alignment: .center, spacing: 10) {
            Circle().fill(color(state)).frame(width: 9, height: 9).help(text(state))
            VStack(alignment: .leading, spacing: 4) {
                TextField(L("Ad"), text: $name)
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
                    .focused($focus, equals: .name)
                    .onSubmit(save)
                TextField(L("Komut, ör. ./deploy.sh"), text: $command)
                    .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                    .focused($focus, equals: .command)
                    .onSubmit(save)
            }
            Spacer(minLength: 8)
            Toggle(L("Önce sor"), isOn: Binding(get: { card.confirm }, set: { v in
                var c = card; c.confirm = v; runCards.update(c)
            }))
            .toggleStyle(.checkbox).font(.system(size: 12))
            Button(L("Çalıştır")) {
                save()
                model.runCard(root: root, id: card.id)
            }
            .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button { runCards.delete(card) } label: {
                Image(systemName: "trash").foregroundStyle(GHTheme.muted)
            }
            .buttonStyle(.plain).help(L("Sil"))
        }
        .padding(.vertical, 6)
        .onAppear { name = card.name; command = card.command }
        .onChange(of: card) { _, c in
            if focus == nil { name = c.name; command = c.command }
        }
        .onChange(of: focus) { old, _ in if old != nil { save() } }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces), c = command.trimmingCharacters(in: .whitespaces)
        guard n != card.name || c != card.command else { return }
        var new = card
        new.name = n
        new.command = c
        runCards.update(new)
    }

    private func text(_ s: RunState) -> String {
        switch s {
        case .idle: L("boşta")
        case .running: L("çalışıyor")
        case .ok: L("başarılı")
        case .failed: L("hata verdi")
        }
    }

    private func color(_ s: RunState) -> Color {
        switch s {
        case .idle: Color(red: 0.6, green: 0.63, blue: 0.65)
        case .running: Color(red: 0.94, green: 0.54, blue: 0.14)
        case .ok: Theme.ok
        case .failed: Color(red: 0.85, green: 0.33, blue: 0.31)
        }
    }
}
