import AjanTakipCore
import SwiftUI

/// Sol panel: projelere göre gruplu, açık Claude oturumları. Tıklayınca oturumun terminaline gider.
struct SessionSidebar: View {
    let model: WorkshopModel

    private var zones: [ZoneInfo] { (model.snapshot?.zones ?? []).filter { !$0.robots.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 30) // pencere düğmeleri
            Button { model.closeRoom() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                    Text("Atölye").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if waitingCount > 0 {
                        Text("\(waitingCount)").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(SidebarTheme.color("waiting")))
                    }
                }
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(model.openRoom == nil ? SidebarTheme.selected : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(zones, id: \.id) { z in zoneSection(z) }
                    if zones.isEmpty {
                        Text("Açık Claude oturumu yok").font(.caption).foregroundStyle(SidebarTheme.muted)
                            .padding(.horizontal, 18)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .foregroundStyle(SidebarTheme.text)
        .background(SidebarTheme.background)
    }

    private var waitingCount: Int {
        zones.reduce(0) { $0 + $1.robots.filter { $0.state == "waiting" }.count }
    }

    private func zoneSection(_ z: ZoneInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { model.openZone(z.id) } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: z.color)).frame(width: 8, height: 8)
                    Text(z.name.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(SidebarTheme.muted).lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.bottom, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(z.name) terminallerini aç")
            ForEach(z.robots, id: \.id) { r in robotRow(r, zone: z) }
        }
    }

    private func robotRow(_ r: RobotInfo, zone: ZoneInfo) -> some View {
        let selected = model.openRoom == zone.id && r.terminal != nil
            && model.room(zone.id).panes.indices.contains(model.room(zone.id).focusedPane)
            && model.room(zone.id).panes[model.room(zone.id).focusedPane].current == .terminal(r.terminal!)
        return Button { model.open(sessionID: r.id) } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(SidebarTheme.color(r.state)).frame(width: 8, height: 8).padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(r.label).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        if !r.profile.isEmpty {
                            Text(r.profile).font(.system(size: 10)).foregroundStyle(SidebarTheme.muted).lineLimit(1)
                        }
                        if r.terminal == nil {
                            Image(systemName: "arrow.up.right.square").font(.system(size: 9))
                                .foregroundStyle(SidebarTheme.muted).help("Atölye dışında açılmış oturum")
                        }
                    }
                    Text(subtitle(r)).font(.system(size: 11)).foregroundStyle(SidebarTheme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? SidebarTheme.selected : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func subtitle(_ r: RobotInfo) -> String {
        switch r.state {
        case "waiting": return "seni bekliyor" + (r.waitingFor.map { " · \($0)" } ?? "")
        case "done": return "bitti"
        case "busy":
            let h = r.helpers.isEmpty ? "" : " · \(r.helpers.count) yardımcı"
            return (r.tool ?? "çalışıyor") + h
        default: return r.history.first.map { "boşta · \($0)" } ?? "boşta"
        }
    }
}

enum SidebarTheme {
    static let background = Color(red: 0.965, green: 0.945, blue: 0.91)
    static let selected = Color(red: 0.89, green: 0.855, blue: 0.80)
    static let text = Color(red: 0.17, green: 0.16, blue: 0.15)
    static let muted = Color(red: 0.50, green: 0.47, blue: 0.42)

    static func color(_ state: String) -> Color {
        switch state {
        case "busy": Color(red: 0.16, green: 0.62, blue: 0.85)
        case "waiting": Color(red: 1, green: 0.55, blue: 0.18)
        case "done": Color(red: 0.23, green: 0.65, blue: 0.48)
        default: Color(red: 0.66, green: 0.63, blue: 0.58)
        }
    }
}

extension Color {
    /// Workshop.color'ın ürettiği "#rrggbb".
    init(hex s: String) {
        if s.hasPrefix("#"), let n = UInt32(s.dropFirst(), radix: 16) {
            self.init(red: Double(n >> 16 & 255) / 255, green: Double(n >> 8 & 255) / 255, blue: Double(n & 255) / 255)
        } else {
            self.init(white: 0.6)
        }
    }
}
