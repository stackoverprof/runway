// Rebuild and relaunch trigger: Native macOS notification integration.
import SwiftUI
import AppKit
import UserNotifications

/// Native macOS notification center (replaces in-app toasts).
@MainActor @Observable final class ToastCenter {
    static let shared = ToastCenter()

    private init() {
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Show a native macOS notification. Optionally play the system alert sound.
    func show(_ title: String, icon: String = "bell.fill", tint: Color = .white, sound: Bool = false) {
        if sound, UserDefaults.standard.bool(forKey: SettingsKey.soundEnabled) { Self.playSelectedSound() }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.interruptionLevel = .timeSensitive
        if !sound {
            content.sound = nil
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
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

