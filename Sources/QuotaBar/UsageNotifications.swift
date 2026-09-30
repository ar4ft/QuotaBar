#if os(macOS)
import Foundation
import UserNotifications
import QuotaCore

final class ForegroundNotifications: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

@MainActor
final class UsageNotifications {
    private let center: UNUserNotificationCenter?
    private let delegate = ForegroundNotifications()
    init() {
        // Swift package executables launched outside an app bundle cannot register for notifications.
        center = Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
        center?.delegate = delegate
    }
    func authorization() async -> UNAuthorizationStatus {
        guard let center else { return .notDetermined }
        return await center.notificationSettings().authorizationStatus
    }
    func requestAuthorization() async throws -> Bool {
        guard let center else {
            throw NSError(domain: "QuotaBar", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "Open the packaged QuotaBar.app to enable notifications."])
        }
        return try await center.requestAuthorization(options: [.alert, .sound])
    }
    func send(_ alerts: [UsageAlert], account: Account) async throws {
        guard !alerts.isEmpty, let center else { return }
        let status = await authorization()
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(account.name) · \(account.provider.title)"
        content.body = alerts.prefix(5).map { alert in
            switch alert.kind {
            case .threshold(let threshold):
                return "\(alert.windowTitle): \(Int(alert.usedPercent.rounded()))% used (\(threshold)% alert)."
            case .availableAgain:
                return "\(alert.windowTitle): allowance is available again · \(Int((100 - alert.usedPercent).rounded()))% remaining."
            }
        }.joined(separator: "\n")
        if alerts.count > 5 { content.body += "\nAnd \(alerts.count - 5) more windows." }
        content.sound = .default
        // Only user-visible account labels and quota readings are included, never credentials.
        content.userInfo = ["accountID": account.id.uuidString]
        let request = UNNotificationRequest(identifier: "usage-\(account.id.uuidString)-\(UUID().uuidString)", content: content, trigger: nil)
        try await center.add(request)
    }
    func removeNotifications(for id: UUID) async {
        guard let center else { return }
        let notifications = await center.deliveredNotifications()
        let ids = notifications.filter { $0.request.content.userInfo["accountID"] as? String == id.uuidString }.map { $0.request.identifier }
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
#endif
