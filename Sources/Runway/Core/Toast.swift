// Rebuild and relaunch trigger: Native macOS notification integration.
import SwiftUI
import AppKit
import UserNotifications

/// Native macOS notification center.
///
/// Runway is its own notification delegate for two reasons: a banner is
/// suppressed while the app is in front unless the delegate asks for it, and
/// clicking one has to land on the agent that raised it.
@MainActor @Observable final class RunwayNotificationManager: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = RunwayNotificationManager()

    /// Set by the workspace: jump to the agent a clicked banner names.
    var openAgent: ((UUID, String?) -> Void)?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static let boxKey = "runway.box"
    private static let repositoryKey = "runway.repository"

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
        let info = response.notification.request.content.userInfo
        let box = (info[Self.boxKey] as? String).flatMap(UUID.init(uuidString:))
        let repository = info[Self.repositoryKey] as? String
        if let box {
            NSApp.activate(ignoringOtherApps: true)
            openAgent?(box, repository)
        }
        completionHandler()
    }

    /// Show a native macOS notification. Backgrounded Runway always banners;
    /// an active one only does when the user asked for it in Settings, since
    /// the card in front of them is usually notification enough.
    func show(
        _ title: String,
        sound: Bool = false,
        box: UUID? = nil,
        repository: String? = nil
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
        var info: [String: Any] = [:]
        if let box { info[Self.boxKey] = box.uuidString }
        if let repository { info[Self.repositoryKey] = repository }
        content.userInfo = info
        
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

