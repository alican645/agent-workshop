import AtolyeCore
import AppKit
import UserNotifications

/// Atölye arka plandayken bekleyen / işini bitiren ajanlar için macOS bildirimi.
/// Yalnız paketlenmiş uygulamada çalışır (`swift run` ile bildirim merkezi kullanılamaz).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Bildirime tıklanınca: oturum kimliği.
    var onOpen: ((String) -> Void)?

    static var available: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

    func start() {
        guard Self.available else { return }
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    func post(_ a: RobotAlert) {
        guard Self.available else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(a.zoneName) · \(a.label)"
        switch a.kind {
        case .waiting: content.body = "Seni bekliyor" + (a.detail.map { ": \($0)" } ?? "")
        case .done: content.body = "İşini bitirdi 👍"
        }
        content.threadIdentifier = a.zoneName
        content.userInfo = ["session": a.robotID]
        // Ses Atölye'nin kendi uyarısından geliyor; ikinci kez çalmasın.
        content.sound = nil
        // Aynı robotun eski bildirimi yenisiyle değişsin.
        let req = UNNotificationRequest(identifier: "robot-\(a.robotID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Hesap limiti uyarısı (Atölye öndeyken de görünür).
    func postLimit(id: String, title: String, body: String) {
        guard Self.available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "limit-\(id)", content: content, trigger: nil))
    }

    /// Ajan artık beklemiyorsa ya da Atölye öne gelince eski bildirimler kalkar.
    func clear(sessions ids: [String]) {
        guard Self.available, !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids.map { "robot-\($0)" })
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["session"] as? String
        await MainActor.run {
            NSApp.activate()
            if let id { onOpen?(id) }
        }
    }

    /// Uygulama öndeyken bildirim gösterme (sahne ve pencereler zaten gösteriyor).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier.hasPrefix("limit-") ? [.banner, .sound] : []
    }
}
