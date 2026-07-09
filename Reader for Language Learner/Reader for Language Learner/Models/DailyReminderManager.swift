//
//  DailyReminderManager.swift
//  Reader for Language Learner
//
//  Local daily-goal reminder: a repeating UNUserNotificationCenter request
//  that nudges the user at a chosen time, and deep-links into the review
//  window (reusing RELLIntents' .openReviewWindowCommand) when tapped.
//

import Foundation
import UserNotifications
import os

/// Not actor-isolated — the notification delegate callbacks fire off the
/// main actor, so this identifier needs to be reachable from there too.
private let dailyReminderRequestIdentifier = "dailyGoalReminder"

@MainActor
final class DailyReminderManager: NSObject {
    static let shared = DailyReminderManager()

    static let enabledKey = "dailyReminderEnabled"
    static let timeKey = "dailyReminderTime"

    private override init() {
        super.init()
    }

    /// App-launch wiring: become the notification delegate and sync the
    /// scheduled request with the current preference.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
        if UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false {
            Task { await requestAuthorizationAndSchedule() }
        }
    }

    @discardableResult
    func requestAuthorizationAndSchedule() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            if granted {
                schedule()
            } else {
                UserDefaults.standard.set(false, forKey: Self.enabledKey)
            }
            return granted
        } catch {
            AppLogger.notifications.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return false
        }
    }

    /// Schedules (or reschedules) the repeating daily reminder at the stored time.
    func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderRequestIdentifier])

        let time = Self.storedTime()
        var components = Calendar.current.dateComponents([.hour, .minute], from: time)
        components.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time for your daily goal")
        content.body = String(localized: "Review a few words or read a page to keep your streak going.")
        content.sound = .default

        let request = UNNotificationRequest(identifier: dailyReminderRequestIdentifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                AppLogger.notifications.error("Failed to schedule reminder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyReminderRequestIdentifier])
    }

    static func storedTime() -> Date {
        // @AppStorage("dailyReminderTime") in GeneralSettingsView writes a
        // Date directly (UserDefaults' native property-list Date type).
        UserDefaults.standard.object(forKey: timeKey) as? Date
            ?? Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date())
            ?? Date()
    }
}

extension DailyReminderManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == dailyReminderRequestIdentifier {
            NotificationCenter.default.post(name: .openReviewWindowCommand, object: nil)
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
