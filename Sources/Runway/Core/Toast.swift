// Rebuild and relaunch trigger: Native macOS notification integration.
import SwiftUI
import AppKit
import UserNotifications

enum AgentAttentionTarget: Equatable {
    case box(UUID, repository: String?)
    case quick(root: String)

    private static let boxKey = "runway.box"
    private static let repositoryKey = "runway.repository"
    private static let quickRootKey = "runway.quickRoot"

    var userInfo: [String: String] {
        switch self {
        case .box(let id, let repository):
            var info = [Self.boxKey: id.uuidString]
            if let repository { info[Self.repositoryKey] = repository }
            return info
        case .quick(let root):
            return [Self.quickRootKey: root]
        }
    }

    init?(userInfo: [AnyHashable: Any]) {
        if let root = userInfo[Self.quickRootKey] as? String, !root.isEmpty {
            self = .quick(root: root)
        } else if let raw = userInfo[Self.boxKey] as? String,
                  let id = UUID(uuidString: raw) {
            self = .box(id, repository: userInfo[Self.repositoryKey] as? String)
        } else {
            return nil
        }
    }
}

/// Native macOS notification center.
///
/// Runway is its own notification delegate for two reasons: a banner is
/// suppressed while the app is in front unless the delegate asks for it, and
/// clicking one has to land on the agent that raised it.
@MainActor @Observable final class RunwayNotificationManager: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = RunwayNotificationManager()

    /// Set by the workspace: jump to the agent a clicked banner names.
    var openAgent: ((AgentAttentionTarget) -> Void)?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// The system drops a banner while its app is frontmost unless the delegate
    /// says otherwise, which is what the Settings switch controls.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// A clicked banner focuses the agent that raised it, switching repository
    /// first when the agent belongs to one that is not on screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let target = AgentAttentionTarget(userInfo: response.notification.request.content.userInfo) {
            NSApp.activate(ignoringOtherApps: true)
            RunwayWindowRegistry.shared.mainWindow()?.makeKeyAndOrderFront(nil)
            openAgent?(target)
        }
        completionHandler()
    }

    /// Show a native macOS notification. Backgrounded Runway always banners;
    /// an active one only does when the user asked for it in Settings, since
    /// the card in front of them is usually notification enough.
    func show(
        _ title: String,
        sound: Bool = false,
        target: AgentAttentionTarget? = nil
    ) {
        if sound, UserDefaults.standard.bool(forKey: SettingsKey.soundEnabled) { Self.playSelectedSound() }

        let bannerWhileActive = UserDefaults.standard.bool(forKey: SettingsKey.bannerWhileActive)
        guard !NSApp.isActive || bannerWhileActive else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.interruptionLevel = .timeSensitive
        if !sound {
            content.sound = nil
        }
        // Carried so a click can focus the agent instead of merely raising the
        // window on whatever happened to be selected.
        content.userInfo = target?.userInfo ?? [:]
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// Play the user's chosen alert sound (used by notifications and the Settings "Test").
    static func playSelectedSound() {
        let name = UserDefaults.standard.string(forKey: SettingsKey.alertSound) ?? "Glass"
        if let sound = NSSound(named: name) ?? NSSound(named: "Glass") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
