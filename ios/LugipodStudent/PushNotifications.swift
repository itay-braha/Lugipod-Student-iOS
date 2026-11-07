import UIKit
import UserNotifications

/// APNs registration, the token upload, and what a tap on a notification opens.
@MainActor
final class PushNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotifications()

    var router: AppRouter? {
        didSet {
            if let router, let pendingPath {
                self.pendingPath = nil
                router.open(path: pendingPath)
            }
        }
    }
    private var pendingPath: String?
    private var token: String?

    private var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// Asks once (right after the first sign-in, when the value is obvious) and registers.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    func didRegister(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await uploadIfPossible() }
    }

    /// A token belongs to whoever signed in last; tokens also rotate, so this runs on every launch.
    func uploadIfPossible() async {
        guard AuthStore.shared.state == .signedIn, let token else { return }
        _ = try? await API.request("POST", "/api/native/push", json: ["token": token, "environment": environment])
    }

    func willSignOut() async {
        if let token { _ = try? await API.request("DELETE", "/api/native/push", json: ["token": token]) }
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func setBadge(_ n: Int) {
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(n) }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let path = response.notification.request.content.userInfo["path"] as? String ?? "/alerts"
        await MainActor.run {
            if let router { router.open(path: path) } else { pendingPath = path }
        }
    }
}
