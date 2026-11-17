import AtolyeCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Robot havuzu (GitHub panosuyla aynı görünüm): hazır robotları aç-kapa, kendi `.glb` robotlarını ekle,
/// düzenle, sil. Her robot kartında atölyedeki çizimiyle bir resmi var.
struct RobotsWindow: View {
    let model: WorkshopModel

    private var pool: RobotPoolStore { model.robotPool }
    private var previews: RobotPreviews { model.robotPreviews }
    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14)]

    var body: some View {
        let _ = model.robotsVersion // havuz değişince yeniden çiz
        let config = pool.config
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                section("Ana ajanlar", "Her yeni Claude oturumu bunlardan birini alır.") {
                    ForEach(RobotPool.builtins.filter { $0.role == .main }, id: \.id) { builtinCard($0.id, $0.name, config) }
                }
                section("Alt ajanlar", "Oturumların gönderdiği yardımcılar bunlardan birini alır.") {
                    ForEach(RobotPool.builtins.filter { $0.role == .sub }, id: \.id) { builtinCard($0.id, $0.name, config) }
                }
                section("Kendi robotların", "Animasyonlar adlarına göre eşlenir (Idle, Walk/Run, Wave, Sit, Yes…); eksik olanların yerine robot kendisi sallanır, zıplar ya da eğilir.") {
                    ForEach(config.customs) { customCard($0, config) }
                    addCard
                }
            }
            .padding(24)
        }
        .frame(minWidth: 640, minHeight: 560)
        .background(GHTheme.background)
        .foregroundStyle(GHTheme.text)
        .onAppear { previews.request(customs: config.customs) }
        .onChange(of: model.robotsVersion) { previews.request(customs: pool.config.customs) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "figure.wave").font(.system(size: 30)).foregroundStyle(Theme.focus)
            VStack(alignment: .leading, spacing: 3) {
                Text("Robotlar").font(.title2.bold())
                Text("Yeni oturumlar açık robotlardan rastgele birini alır; atölyede o an olmayanlar önce gelir.")
                    .font(.callout).foregroundStyle(GHTheme.muted)
            }
            Spacer()
            Button { addRobot() } label: {
                Label("Robot ekle", systemImage: "plus").padding(.horizontal, 10).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Theme.focus)
        }
    }

    private func section(_ title: String, _ note: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(note).font(.caption).foregroundStyle(GHTheme.muted)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) { content() }
        }
    }

    // MARK: Kartlar

    private func builtinCard(_ id: String, _ name: String, _ c: RobotPoolConfig) -> some View {
        let on = !c.disabled.contains(id)
        let locked = on && !RobotPool.canDisable(id, in: c)
        return RobotCard(image: previews.images[id], dimmed: !on) {
            HStack {
                Text(name).font(.system(size: 14, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding(get: { on }, set: { v in change { try pool.setEnabled(id, v) } }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .disabled(locked)
                    .help(locked ? "Bu roldeki son açık robot; kapatmak için önce başka birini aç." : on ? "Kapat" : "Aç")
            }
        }
    }

    private func customCard(_ r: CustomRobot, _ c: RobotPoolConfig) -> some View {
        let on = !c.disabled.contains(r.id)
        let error = model.robotFailures[r.id] ?? previews.errors[r.id]
        return RobotCard(image: previews.image(for: r), dimmed: !on, failed: error != nil) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NameField(name: r.name) { v in change { try pool.update(r.id, name: v) } }
                    Toggle("", isOn: Binding(get: { on }, set: { v in change { try pool.setEnabled(r.id, v) } }))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        .disabled(on && !RobotPool.canDisable(r.id, in: c))
                }
                Picker("", selection: Binding(get: { r.role }, set: { v in change { try pool.update(r.id, role: v) } })) {
                    Text("Ana").tag(RobotRole.main)
                    Text("Alt").tag(RobotRole.sub)
                    Text("İkisi").tag(RobotRole.both)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                HStack {
                    Button { change { try pool.update(r.id, flipped: !r.flipped) } } label: {
                        Label("Çevir", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    }
                    .help("Model ters duruyorsa yönünü 180° çevir")
                    Spacer()
                    Button(role: .destructive) {
                        change { try pool.remove(r.id) }
                        previews.forget(r.id)
                        model.robotFailures[r.id] = nil
                    } label: { Image(systemName: "trash") }
                    .help("Robotu sil")
                }
                .buttonStyle(.borderless).controlSize(.small)
                if let error {
                    Text("Yüklenemedi: \(error)").font(.caption).foregroundStyle(.red).lineLimit(3)
                }
            }
        }
    }

    private var addCard: some View {
        Button { addRobot() } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 30)).foregroundStyle(Theme.focus)
                Text("Robot ekle").font(.system(size: 13, weight: .semibold))
                Text(".glb dosyası, en fazla 30 MB").font(.caption).foregroundStyle(GHTheme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 230)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(GHTheme.muted.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: İşlemler

    private func change(_ f: () throws -> Void) {
        do { try f() } catch { show(error) }
        model.robotsChanged()
    }

    private func addRobot() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "glb") ?? .data]
        panel.prompt = "Ekle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        change {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= RobotPool.maxBytes else { throw RobotPoolError.tooLarge }
            let data = try Data(contentsOf: url)
            try pool.add(data: data, name: url.deletingPathExtension().lastPathComponent, role: .both)
        }
    }

    private func show(_ error: Error) {
        let a = NSAlert()
        a.messageText = switch error as? RobotPoolError {
        case .notGLB: "Bu dosya .glb değil."
        case .tooLarge: "Dosya 30 MB'tan büyük."
        case .lastInRole: "Her rolde en az bir açık robot kalmalı."
        case nil: error.localizedDescription
        }
        a.runModal()
    }
}

/// Resimli robot kartı.
private struct RobotCard<Content: View>: View {
    let image: NSImage?
    var dimmed = false
    var failed = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(GHTheme.background.opacity(0.9))
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().padding(6)
                        .saturation(dimmed ? 0 : 1).opacity(dimmed ? 0.45 : 1)
                } else if failed {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 26)).foregroundStyle(.orange)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 150)
            content
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(GHTheme.card))
    }
}

/// Ad alanı: her tuşta değil, Enter'a basınca ya da odak çıkınca kaydeder; boş ad kabul edilmez.
private struct NameField: View {
    let name: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Ad", text: $text)
            .textFieldStyle(.plain).font(.system(size: 14, weight: .semibold))
            .focused($focused)
            .onAppear { text = name }
            .onChange(of: name) { if !focused { text = name } }
            .onSubmit(save)
            .onChange(of: focused) { if !focused { save() } }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { text = name } else if t != name { commit(t) }
    }
}
