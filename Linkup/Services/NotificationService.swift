import Foundation
import UIKit
import UserNotifications

final class NotificationService {
    static let deviceTokenDidUpdate = Notification.Name("LinkupDeviceTokenDidUpdate")
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let shareWarningID = "linkup.share.warning"
    private let shareExpiredID = "linkup.share.expired"

    func requestAuthorizationAndRegister() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func scheduleShareNotifications(session: ShareSession, expiringEnabled: Bool) {
        cancelShareNotifications()
        guard expiringEnabled else { return }

        let warningDate = session.expiresAt.addingTimeInterval(-30 * 60)
        let warningInterval = warningDate.timeIntervalSinceNow
        if warningInterval > 1 {
            let content = UNMutableNotificationContent()
            content.title = "30 minutes left"
            content.body = "Your location is still live at \(session.eventName)."
            content.sound = .default
            content.userInfo = [
                "type": "share_expiring",
                "shareSessionID": session.id.uuidString,
                "eventName": session.eventName
            ]
            schedule(content, after: warningInterval, identifier: shareWarningID)
        }

        let expiredInterval = session.expiresAt.timeIntervalSinceNow
        if expiredInterval > 1 {
            let content = UNMutableNotificationContent()
            content.title = "Location no longer live"
            content.body = "Your location sharing at \(session.eventName) has ended."
            content.sound = .default
            content.userInfo = [
                "type": "share_expired",
                "shareSessionID": session.id.uuidString,
                "eventName": session.eventName
            ]
            schedule(content, after: expiredInterval, identifier: shareExpiredID)
        }
    }

    func cancelShareNotifications() {
        center.removePendingNotificationRequests(withIdentifiers: [shareWarningID, shareExpiredID])
    }

    func deliverLocationStopped(eventName: String?) {
        cancelShareNotifications()
        let content = UNMutableNotificationContent()
        content.title = "Location no longer live"
        if let eventName, !eventName.isEmpty {
            content.body = "Your location sharing at \(eventName) has ended."
        } else {
            content.body = "Your location sharing has ended."
        }
        content.sound = .default
        content.userInfo = ["type": "share_stopped"]
        schedule(content, after: 1, identifier: "linkup.share.stopped.\(UUID().uuidString)")
    }

    func deliverMessageNotification(from connection: ConnectionProfile, body: String, eventName: String?) {
        let content = UNMutableNotificationContent()
        if let eventName, !eventName.isEmpty {
            content.title = "\(connection.name) is here at \(eventName)"
        } else {
            content.title = "\(connection.name) sent a message"
        }
        content.body = String(body.prefix(140))
        content.sound = .default
        content.userInfo = [
            "type": "message",
            "connectionID": connection.id,
            "connectionName": connection.name,
            "message": body
        ]
        schedule(content, after: 1, identifier: "linkup.message.\(connection.id).\(UUID().uuidString)")
    }

    private func schedule(_ content: UNNotificationContent, after interval: TimeInterval, identifier: String) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    static func tokenString(from deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }
}

final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = NotificationService.tokenString(from: deviceToken)
        NotificationCenter.default.post(name: NotificationService.deviceTokenDidUpdate, object: token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
