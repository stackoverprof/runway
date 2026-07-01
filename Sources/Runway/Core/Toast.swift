// Rebuild and relaunch trigger: Native macOS notification integration.
import SwiftUI
import AppKit
import UserNotifications

/// Native macOS notification center.
@MainActor @Observable final class RunwayNotificationManager {
    static let shared = RunwayNotificationManager()

    private init() {
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Show a native macOS notification ONLY if the app is not currently active (unfocused).
    func show(_ title: String, sound: Bool = false) {
        if sound, UserDefaults.standard.bool(forKey: SettingsKey.soundEnabled) { Self.playSelectedSound() }
        
        // Only trigger the OS notification banner when the app is unfocused (background).
        guard !NSApp.isActive else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.interruptionLevel = .timeSensitive
        if !sound {
            content.sound = nil
        }
        
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

