//
//  DailyReminderManager.swift
//  Reader for Language Learner
//
//  Local daily-goal reminder: one UNUserNotificationCenter request a day for
//  the coming week (v19 S5), skipped on a day whose goal is done, that
//  deep-links into the review window (reusing RELLIntents'
//  .openReviewWindowCommand) when tapped.
//

import Foundation
import UserNotifications
import os

/// Not actor-isolated — the notification delegate callbacks fire off the
/// main actor, so this identifier needs to be reachable from there too.
private nonisolated let dailyReminderRequestIdentifier = "dailyGoalReminder"
/// A reminder that asks about one due word, answerable from the banner
/// (v13 Sprint 5).
private nonisolated let reviewWordCategory = "RELL_REVIEW_WORD"
private nonisolated let knewItAction = "RELL_KNEW_IT"
private nonisolated let notYetAction = "RELL_NOT_YET"
private nonisolated let wordIDKey = "wordID"

@MainActor
final class DailyReminderManager: NSObject {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    static let shared = DailyReminderManager()

    static let enabledKey = "dailyReminderEnabled"
    static let timeKey = StorageKey.dailyReminderTime

    /// Where a word answered from the banner is reviewed. Weak: the store
    /// belongs to the app.
    private weak var savedWordsStore: SavedWordsStore?

    private override init() {
        super.init()
    }

    /// App-launch wiring: become the notification delegate and sync the
    /// scheduled request with the current preference.
    func configure(savedWordsStore: SavedWordsStore? = nil) {
        self.savedWordsStore = savedWordsStore
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: reviewWordCategory,
                actions: [
                    UNNotificationAction(identifier: knewItAction, title: String(localized: "I Knew It")),
                    UNNotificationAction(identifier: notYetAction, title: String(localized: "Not Yet")),
                ],
                intentIdentifiers: []
            ),
        ])
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

    /// Today's goal as the tracker last saw it (v19 S5): a day already done
    /// gets no reminder, and today's says what's left.
    private var goalDoneToday = false
    private var goalRemaining: String?

    func goalChanged(done: Bool, remaining: String?) {
        goalDoneToday = done
        goalRemaining = remaining
        if UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false {
            schedule()
        }
    }

    /// Schedules the reminders for the next seven days at the stored time —
    /// one request a day, so today's can be left out once the goal is done
    /// (v19 S5; before, one repeating request).
    func schedule(now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.allIdentifiers(from: now))

        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: Self.storedTime())
        let dueWord = savedWordsStore?.dueWords().first
        let doneToday = goalDoneToday, remaining = goalRemaining

        for offset in 0..<Self.daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let fire = calendar.date(bySettingHour: time.hour ?? 19, minute: time.minute ?? 0, second: 0, of: day),
                  fire > now
            else { continue }
            if offset == 0, doneToday { continue }

            let content = UNMutableNotificationContent()
            if let word = dueWord {
                // A word to answer right from the banner. It's the word due when
                // this was scheduled; answering reschedules with the next one.
                content.title = String(localized: "Do you remember “\(word.term)”?")
                content.body = offset == 0 && remaining != nil
                    ? remaining!
                    : String(localized: "Answer here, or open RELL to review the rest.")
                content.categoryIdentifier = reviewWordCategory
                content.userInfo = [wordIDKey: word.id.uuidString]
            } else {
                content.title = String(localized: "Time for your daily goal")
                content.body = offset == 0 && remaining != nil
                    ? remaining!
                    : String(localized: "Review a few words or read a page to keep your streak going.")
            }
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: Self.identifier(for: day), content: content, trigger: trigger)
            // The async form, not the completion block: the block runs on a
            // background queue, and one formed here would inherit main-actor
            // isolation — under Swift 6 a runtime check that traps.
            Task {
                do {
                    try await center.add(request)
                } catch {
                    AppLogger.notifications.error("Failed to schedule reminder: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    static let daysAhead = 7

    /// "dailyGoalReminder-2026-10-20" — the day the reminder is for.
    static func identifier(for day: Date) -> String {
        dailyReminderRequestIdentifier + "-" + DailyGoalLog.key(day)
    }

    /// Today's and the coming days' identifiers, and the old repeating one.
    static func allIdentifiers(from now: Date) -> [String] {
        let calendar = Calendar.current
        let days = (-1...daysAhead).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now)) }
        return [dailyReminderRequestIdentifier] + days.map(identifier(for:))
    }

    /// A banner answer: recall, so it goes to the schedule like a flashcard's.
    /// Then the next reminder is rebuilt around the next due word.
    func answer(wordID: UUID, knew: Bool) {
        if let store = savedWordsStore, let word = store.word(withID: wordID) {
            _ = store.applyReview(knew ? .good : .again, to: word)
        }
        if UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false {
            schedule()
        }
    }

    func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.allIdentifiers(from: Date()))
    }

    static func storedTime() -> Date {
        // @AppStorage(StorageKey.dailyReminderTime) in GeneralSettingsView writes a
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
        guard response.notification.request.identifier.hasPrefix(dailyReminderRequestIdentifier) else {
            completionHandler()
            return
        }
        let action = response.actionIdentifier
        let wordID = (response.notification.request.content.userInfo[wordIDKey] as? String)
            .flatMap(UUID.init(uuidString:))
        if action == knewItAction || action == notYetAction, let wordID {
            let knew = action == knewItAction
            Task { @MainActor in
                DailyReminderManager.shared.answer(wordID: wordID, knew: knew)
            }
        } else {
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
