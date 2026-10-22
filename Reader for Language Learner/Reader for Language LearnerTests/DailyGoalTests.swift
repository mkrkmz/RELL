//
//  DailyGoalTests.swift
//  Reader for Language LearnerTests
//
//  v19 Sprint 5 — the daily goal (reading and reviews), the streak that
//  follows it without resetting anyone's old one, the log a day is kept
//  in, the reminder's days, the interface language and the translations.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class DailyGoalTests: XCTestCase {
    private let targets = DailyGoal.Targets(readingMinutes: 20, reviews: 20)
    private var calendar: Calendar { Calendar.current }

    private func day(_ offset: Int, from base: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: base))!
    }

    // MARK: The two parts

    func testADayIsWholeWithBothParts() {
        let done = DailyGoal.Day(readingSeconds: 20 * 60, reviews: 20, dueLeft: 5)
        XCTAssertEqual(DailyGoal.status(done, targets), .full)
        let readingOnly = DailyGoal.Day(readingSeconds: 25 * 60, reviews: 3, dueLeft: 12)
        XCTAssertEqual(DailyGoal.status(readingOnly, targets), .half)
        let nothing = DailyGoal.Day(readingSeconds: 60, reviews: 0, dueLeft: 12)
        XCTAssertEqual(DailyGoal.status(nothing, targets), .none)
    }

    func testFewerCardsDueThanTheTargetAreDoneOnceNoneAreLeft() {
        let allDone = DailyGoal.Day(readingSeconds: 20 * 60, reviews: 6, dueLeft: 0)
        XCTAssertTrue(DailyGoal.reviewsDone(allDone, targets))
        XCTAssertEqual(DailyGoal.status(allDone, targets), .full)
        let someLeft = DailyGoal.Day(readingSeconds: 0, reviews: 6, dueLeft: 3)
        XCTAssertEqual(DailyGoal.reviewsLeft(someLeft, targets), 3, "never more than are due")
        let manyLeft = DailyGoal.Day(readingSeconds: 0, reviews: 6, dueLeft: 40)
        XCTAssertEqual(DailyGoal.reviewsLeft(manyLeft, targets), 14)
    }

    func testNothingDueAndNothingDoneIsNotHalfADay() {
        let idle = DailyGoal.Day(readingSeconds: 0, reviews: 0, dueLeft: 0)
        XCTAssertEqual(DailyGoal.status(idle, targets), .none)
    }

    func testWithTheReviewsPartOffReadingIsEnough() {
        let off = DailyGoal.Targets(readingMinutes: 15, reviews: 0)
        XCTAssertEqual(DailyGoal.status(DailyGoal.Day(readingSeconds: 15 * 60, reviews: 0, dueLeft: 30), off), .full)
        XCTAssertEqual(DailyGoal.status(DailyGoal.Day(readingSeconds: 60, reviews: 30, dueLeft: 0), off), .none)
    }

    func testMinutesLeftRoundUp() {
        XCTAssertEqual(DailyGoal.readingLeft(DailyGoal.Day(readingSeconds: 14 * 60 + 10, reviews: 0, dueLeft: nil), targets), 6)
        XCTAssertEqual(DailyGoal.readingLeft(DailyGoal.Day(readingSeconds: 21 * 60, reviews: 0, dueLeft: nil), targets), 0)
    }

    // MARK: The streak

    func testTheStreakCountsGoalDaysAndKeepsTheOldOnes() {
        let today = day(0)
        let start = day(-3)
        // Before the goal began: some reading on each of the four days before it.
        let legacy: Set<Date> = [day(-4), day(-5), day(-6), day(-7)]
        let full: Set<Date> = [day(-1), day(-2), day(-3)]
        XCTAssertEqual(DailyGoal.streak(today: today, todayStatus: .half, start: start, full: full, legacy: legacy), 7,
                       "today is still under way; yesterday back to the old days")
        XCTAssertEqual(DailyGoal.streak(today: today, todayStatus: .full, start: start, full: full, legacy: legacy), 8)
    }

    func testAHalfDayAfterTheStartBreaksTheStreak() {
        let start = day(-5)
        let full: Set<Date> = [day(-1), day(-3), day(-4)]   // day -2 only half
        XCTAssertEqual(DailyGoal.streak(today: day(0), todayStatus: .none, start: start, full: full, legacy: []), 1)
    }

    func testReadingAloneNoLongerCountsAfterTheStart() {
        let start = day(-2)
        let legacy: Set<Date> = [day(-1), day(-2), day(-3)]  // read every day, but the goal wasn't met
        XCTAssertEqual(DailyGoal.streak(today: day(0), todayStatus: .none, start: start, full: [], legacy: legacy), 0)
    }

    // MARK: The log

    func testTheLogNeverLowersADay() throws {
        let defaults = scratchDefaults()
        let today = day(0)
        DailyGoalLog.note(.half, for: today, defaults: defaults)
        DailyGoalLog.note(.full, for: today, defaults: defaults)
        DailyGoalLog.note(.none, for: today, defaults: defaults)
        XCTAssertEqual(DailyGoalLog.statuses(defaults: defaults)[DailyGoalLog.key(today)], .full)
        XCTAssertEqual(DailyGoalLog.fullDays(defaults: defaults), [today])
        XCTAssertEqual(DailyGoalLog.date(DailyGoalLog.key(today)), today)
    }

    func testTheStartIsSetOnceAndKept() throws {
        let defaults = scratchDefaults()
        let first = DailyGoalLog.start(defaults: defaults, now: day(0))
        let later = DailyGoalLog.start(defaults: defaults, now: day(9))
        XCTAssertEqual(first, day(0))
        XCTAssertEqual(later, day(0))
    }

    // MARK: The reminder

    func testEachDayHasItsOwnReminder() {
        let now = day(0).addingTimeInterval(8 * 3600)
        let identifiers = DailyReminderManager.allIdentifiers(from: now)
        XCTAssertTrue(identifiers.contains("dailyGoalReminder"), "the old repeating one is cleared too")
        XCTAssertTrue(identifiers.contains(DailyReminderManager.identifier(for: day(0))))
        XCTAssertTrue(identifiers.contains(DailyReminderManager.identifier(for: day(DailyReminderManager.daysAhead))))
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    // MARK: The interface language

    func testTheInterfaceLanguageIsRELLsOwnSetting() throws {
        let defaults = scratchDefaults()
        InterfaceLanguage.german.store(defaults)
        // The persistent domain, not `array(forKey:)`: a test run's own
        // -AppleLanguages argument would answer that first.
        XCTAssertEqual(defaults.persistentDomain(forName: "rell-tests.DailyGoalTests")?["AppleLanguages"] as? [String], ["de"])
        InterfaceLanguage.system.store(defaults)
        XCTAssertNil(defaults.persistentDomain(forName: "rell-tests.DailyGoalTests")?["AppleLanguages"])
        XCTAssertTrue(InterfaceLanguage.spanish.isBeta)
        XCTAssertTrue(InterfaceLanguage.german.isBeta)
        XCTAssertFalse(InterfaceLanguage.turkish.isBeta)
    }

    func testFixATranslationSendsNothingAboutYou() throws {
        let url = InterfaceLanguage.fixTranslationURL
        XCTAssertEqual(url.host, "github.com")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Set(query.map(\.name)), ["title", "labels", "body"])
        let body = try XCTUnwrap(query.first { $0.name == "body" }?.value)
        XCTAssertFalse(body.contains(NSUserName()), "no user name")
    }

    // MARK: The translations

    /// Every string the app shows has a Spanish and a German version with
    /// the same placeholders. Read from the catalog itself: entries no
    /// longer used (stale) stay out of it.
    func testSpanishAndGermanCoverEveryStringInUse() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Reader for Language Learner/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        let strings = try XCTUnwrap(json?["strings"] as? [String: [String: Any]])
        var checked = 0
        for (key, entry) in strings {
            guard entry["extractionState"] as? String != "stale",
                  entry["shouldTranslate"] as? Bool != false,
                  let localizations = entry["localizations"] as? [String: Any],
                  localizations["tr"] != nil
            else { continue }
            for language in ["es", "de"] {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = try XCTUnwrap(unit?["value"] as? String, "\(language) lacks “\(key)”")
                XCTAssertEqual(Self.placeholders(value), Self.placeholders(key), "\(language): \(key) → \(value)")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 1_500)
    }

    /// The Spanish and German strings ship in the app.
    func testSpanishAndGermanShipInTheBundle() throws {
        let bundle = Bundle(for: SavedWordsStore.self)
        for language in ["es", "de"] {
            let path = try XCTUnwrap(bundle.path(forResource: language, ofType: "lproj"), "\(language).lproj is missing")
            let strings = NSDictionary(contentsOfFile: path + "/Localizable.strings")
            XCTAssertGreaterThan(strings?.count ?? 0, 1_500)
        }
    }

    /// The arguments a format takes, in argument order.
    private static func placeholders(_ text: String) -> [String] {
        let regex = /%(?:(\d+)\$)?(lld|ld|d|@|f|\.\d+f)/
        var positional: [Int: String] = [:]
        var next = 0
        for match in text.replacingOccurrences(of: "%%", with: "").matches(of: regex) {
            let type = String(match.2).hasSuffix("f") ? "f" : String(match.2) == "ld" ? "lld" : String(match.2)
            if let index = match.1.flatMap({ Int($0) }) {
                positional[index] = type
            } else {
                next += 1
                positional[next] = type
            }
        }
        return positional.keys.sorted().map { positional[$0]! }
    }
}
