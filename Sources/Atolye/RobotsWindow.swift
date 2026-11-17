import AjanTakipCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Robot havuzu: hazır robotları aç-kapa, kendi `.glb` robotlarını ekle, düzenle, sil.
struct RobotsWindow: View {
    let model: WorkshopModel

    private var pool: RobotPoolStore { model.robotPool }

    var body: some View {
        let _ = model.robotsVersion // havuz değişince yeniden çiz
        let config = pool.config
        Form {
            Section {
                Text("Her yeni Claude oturumu ve alt ajan, kendi rolündeki açık robotlardan rastgele birini alır. Atölyede o an kullanılmayan robotlar önce seçilir.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Ana ajanlar") { builtinRows(.main, config) }
            Section("Alt ajanlar") { builtinRows(.sub, config) }
            Section {
                if config.customs.isEmpty {
                    Text("Henüz kendi robotun yok. Bir .glb dosyası ekleyebilirsin (en fazla 30 MB).")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(config.customs) { r in customRow(r, config) }
            } header: {
                HStack {
                    Text("Kendi robotların")
                    Spacer()
                    Button("Robot ekle…", systemImage: "plus") { addRobot() }
                }
            } footer: {
                Text("Animasyonlar adlarına göre eşlenir (Idle, Walk/Run, Wave, Sit, Yes…). Eksik olanların yerine robot kendisi sallanır, zıplar ya da eğilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 480)
    }

    @ViewBuilder
    private func builtinRows(_ role: RobotRole, _ c: RobotPoolConfig) -> some View {
        ForEach(RobotPool.builtins.filter { $0.role == role }, id: \.id) { b in
            let on = !c.disabled.contains(b.id)
            let locked = on && !RobotPool.canDisable(b.id, in: c)
            Toggle(isOn: Binding(get: { on }, set: { v in change { try pool.setEnabled(b.id, v) } })) {
                Text(b.name)
            }
            .disabled(locked)
            .help(locked ? "Bu roldeki son açık robot" : "")
        }
    }

    @ViewBuilder
    private func customRow(_ r: CustomRobot, _ c: RobotPoolConfig) -> some View {
        let on = !c.disabled.contains(r.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Ad", text: Binding(get: { r.name }, set: { v in change { try pool.update(r.id, name: v) } }))
                    .textFieldStyle(.roundedBorder)
                Toggle("Açık", isOn: Binding(get: { on }, set: { v in change { try pool.setEnabled(r.id, v) } }))
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(on && !RobotPool.canDisable(r.id, in: c))
            }
            HStack {
                Picker("Rol", selection: Binding(get: { r.role }, set: { v in change { try pool.update(r.id, role: v) } })) {
                    Text("Ana").tag(RobotRole.main)
                    Text("Alt").tag(RobotRole.sub)
                    Text("İkisi").tag(RobotRole.both)
                }
                .pickerStyle(.segmented).frame(maxWidth: 220)
                Toggle("Yönünü çevir", isOn: Binding(get: { r.flipped }, set: { v in change { try pool.update(r.id, flipped: v) } }))
                Spacer()
                Button("Sil", role: .destructive) { change { try pool.remove(r.id) } }
            }
            if let err = model.robotFailures[r.id] {
                Text("Yüklenemedi: \(err)").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

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
