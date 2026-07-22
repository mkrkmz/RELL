//
//  SavedWordsStoreTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class SavedWordsStoreTests: XCTestCase {
    private static var retainedStores: [SavedWordsStore] = []

    func testPendingReviewCountsNewWords() {
        let store = makeStore()
        store.add(SavedWord(term: "orbit"))

        XCTAssertEqual(store.pendingReviewCount, 1)
        XCTAssertEqual(store.newCount, 1)
    }

    func testApplyGoodPromotesNewWordToLearning() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)

        let updated = store.applyReview(.good, to: word)

        XCTAssertEqual(updated?.masteryLevel, .learning)
        XCTAssertEqual(updated?.reviewCount, 1)
        XCTAssertNotNil(updated?.lastReviewedAt)
        XCTAssertEqual(updated?.reviewHistory.count, 1)
        XCTAssertNotNil(updated?.nextReviewAt)
    }

    func testApplyAgainKeepsWordDueSoon() {
        let store = makeStore()
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 1)
        store.add(word)

        let updated = store.applyReview(.again, to: word)

        XCTAssertEqual(updated?.incorrectCount, 1)
        XCTAssertEqual(updated?.masteryLevel, .learning)
        XCTAssertNotNil(updated?.nextReviewAt)
    }

    func testApplyAgainLowersEaseFactor() {
        let store = makeStore()
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 1)
        store.add(word)

        let updated = store.applyReview(.again, to: word)

        XCTAssertEqual(updated?.easeFactor, 2.3)
    }

    func testApplyEasyRaisesEaseAndExtendsInterval() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit", masteryLevel: .mastered, reviewCount: 4)
        store.add(word)

        let updated = store.applyReview(.easy, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.easeFactor, 2.65)
        // Base mastered interval is 14 days; ease 2.65/2.5 rounds the scaled
        // interval to 15 days.
        let expected = Calendar.current.date(byAdding: .day, value: 15, to: now)
        XCTAssertEqual(
            updated?.nextReviewAt.map { Calendar.current.startOfDay(for: $0) },
            expected.map { Calendar.current.startOfDay(for: $0) }
        )
    }

    func testDefaultEaseFactorPreservesFixedIntervals() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit", masteryLevel: .mastered, reviewCount: 4)
        store.add(word)

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        let expected = Calendar.current.date(byAdding: .day, value: 7, to: now)
        XCTAssertEqual(
            updated?.nextReviewAt.map { Calendar.current.startOfDay(for: $0) },
            expected.map { Calendar.current.startOfDay(for: $0) }
        )
    }

    // MARK: - Review Events / Accuracy

    func testApplyReviewAppendsRatedEventAlongsideLegacyHistory() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit")
        store.add(word)

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.reviewEvents.count, 1)
        XCTAssertEqual(updated?.reviewEvents.first?.date, now)
        XCTAssertEqual(updated?.reviewEvents.first?.rating, .good)
        XCTAssertEqual(updated?.reviewHistory.count, 1, "legacy reviewHistory must keep being written too")
    }

    func testApplyReviewCapsReviewEventsAtFiveHundredPerWord() {
        let store = makeStore()
        let now = Date()
        let existingEvents = (0..<500).map { offset in
            ReviewEvent(date: now.addingTimeInterval(Double(offset)), rating: .good)
        }
        let word = SavedWord(term: "orbit", reviewEvents: existingEvents)
        store.add(word)

        let reviewedAt = now.addingTimeInterval(1000)
        let updated = store.applyReview(.again, to: word, reviewedAt: reviewedAt)

        XCTAssertEqual(updated?.reviewEvents.count, 500, "must stay capped at 500, dropping the oldest")
        XCTAssertEqual(updated?.reviewEvents.last?.date, reviewedAt)
        XCTAssertEqual(updated?.reviewEvents.first?.date, existingEvents[1].date, "oldest event must be the one dropped")
    }

    func testWeeklyReviewAccuracyBucketsByWeekAndTracksCumulativeRetention() {
        let store = makeStore()
        let calendar = Calendar.current
        let now = Date()
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)
        else { return XCTFail("Could not compute week boundaries") }

        // Last week: 1 correct, 1 incorrect (50%). This week: 1 correct (100%).
        let word = SavedWord(term: "orbit", reviewEvents: [
            ReviewEvent(date: lastWeekStart.addingTimeInterval(60), rating: .good),
            ReviewEvent(date: lastWeekStart.addingTimeInterval(120), rating: .again),
            ReviewEvent(date: thisWeekStart.addingTimeInterval(60), rating: .good)
        ])
        store.add(word)

        let weekly = store.weeklyReviewAccuracy(weeks: 2, endingAt: now)

        XCTAssertEqual(weekly.count, 2)
        XCTAssertEqual(weekly[0].correctCount, 1)
        XCTAssertEqual(weekly[0].incorrectCount, 1)
        XCTAssertEqual(weekly[0].accuracy, 0.5)
        XCTAssertEqual(weekly[0].cumulativeAccuracy, 0.5)

        XCTAssertEqual(weekly[1].correctCount, 1)
        XCTAssertEqual(weekly[1].incorrectCount, 0)
        XCTAssertEqual(weekly[1].accuracy, 1.0)
        // Cumulative through this week: 2 correct out of 3 total.
        XCTAssertEqual(weekly[1].cumulativeAccuracy ?? -1, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testWeeklyReviewAccuracyLeavesGapForWeeksWithNoReviews() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)

        let weekly = store.weeklyReviewAccuracy(weeks: 4)

        XCTAssertTrue(weekly.allSatisfy { $0.accuracy == nil && $0.cumulativeAccuracy == nil })
    }

    func testLifetimeReviewAccuracyIsNilWithNoEventsAndComputedOtherwise() {
        let store = makeStore()
        let untouched = SavedWord(term: "untouched")
        store.add(untouched)
        XCTAssertNil(store.lifetimeReviewAccuracy)

        _ = store.applyReview(.good, to: untouched)
        guard let reviewed = store.words.first else { return XCTFail("expected word") }
        _ = store.applyReview(.again, to: reviewed)

        XCTAssertEqual(store.lifetimeReviewAccuracy, 0.5)
        XCTAssertEqual(store.lifetimeReviewEventCount, 2)
    }

    // MARK: - Language Breakdown

    func testWordCountsByLanguageGroupsAndSortsDescending() {
        let store = makeStore()
        store.add(SavedWord(term: "one", language: Language.english.rawValue))
        store.add(SavedWord(term: "two", language: Language.english.rawValue))
        store.add(SavedWord(term: "three", language: Language.japanese.rawValue))
        store.add(SavedWord(term: "unlabeled"))   // language == nil, must be excluded

        let breakdown = store.wordCountsByLanguage

        XCTAssertEqual(breakdown.count, 2)
        XCTAssertEqual(breakdown.first?.language, .english)
        XCTAssertEqual(breakdown.first?.count, 2)
        XCTAssertEqual(breakdown.last?.language, .japanese)
        XCTAssertEqual(breakdown.last?.count, 1)
    }

    func testSetCEFRLevelAssignsAndClears() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)

        store.setCEFRLevel(.b2, for: word)
        XCTAssertEqual(store.words.first?.cefrLevel, "B2")

        store.setCEFRLevel(nil, for: word)
        XCTAssertNil(store.words.first?.cefrLevel)
    }

    // MARK: - Language

    /// Pre-v1.24 words persisted with no `language` key must be backfilled
    /// from the current target language exactly once, at load time — not
    /// re-derived on every read, so a later target-language change can't
    /// silently relabel words that were already saved.
    func testBackfillMissingLanguageStampsCurrentTargetOnce() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let legacyID = UUID()
        let legacyJSON = """
        [{"id":"\(legacyID.uuidString)","term":"orbit"}]
        """
        try Data(legacyJSON.utf8).write(to: fileURL)

        let previousTarget = UserDefaults.standard.string(forKey: Language.targetLanguageKey)
        UserDefaults.standard.set(Language.german.rawValue, forKey: Language.targetLanguageKey)
        addTeardownBlock {
            UserDefaults.standard.set(previousTarget, forKey: Language.targetLanguageKey)
            try? FileManager.default.removeItem(at: fileURL)
        }

        let store = SavedWordsStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        XCTAssertEqual(store.words.first?.language, Language.german.rawValue)

        // Persisted, not just filled in memory.
        let reloaded = SavedWordsStore(fileURL: fileURL)
        Self.retainedStores.append(reloaded)
        XCTAssertEqual(reloaded.words.first?.language, Language.german.rawValue)
    }

    func testSetLanguageForWordsWithIDs() {
        let store = makeStore()
        let word = SavedWord(term: "orbit", language: Language.english.rawValue)
        store.add(word)

        store.setLanguage(.japanese, forWordsWithIDs: [word.id])
        XCTAssertEqual(store.words.first?.language, Language.japanese.rawValue)
    }

    func testSetCEFRForWordsWithIDsClearsAutoFlag() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)
        store.setAutoCEFRLevel(.b1, forWordID: word.id)
        XCTAssertTrue(store.words.first?.cefrIsAuto ?? false)

        store.setCEFR(.c1, forWordsWithIDs: [word.id])
        XCTAssertEqual(store.words.first?.cefrLevel, "C1")
        XCTAssertFalse(store.words.first?.cefrIsAuto ?? true)
    }

    func testSetMasteryForWordsWithIDs() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)

        store.setMastery(.mastered, forWordsWithIDs: [word.id])
        XCTAssertEqual(store.words.first?.masteryLevel, .mastered)
    }

    func testReviewedTodayCountTracksReviewedWords() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)
        _ = store.applyReview(.good, to: word, reviewedAt: Date())

        XCTAssertEqual(store.reviewedTodayCount, 1)
    }

    func testDocumentScopedCountsTrackSavedAndDueWords() {
        let store = makeStore()
        let now = Date()
        store.add(SavedWord(term: "orbit", pdfFilename: "astro", nextReviewAt: now.addingTimeInterval(-60)))
        store.add(SavedWord(term: "gravity", pdfFilename: "astro", masteryLevel: .mastered))
        store.add(SavedWord(term: "syntax", pdfFilename: "grammar", nextReviewAt: now.addingTimeInterval(-60)))

        XCTAssertEqual(store.savedCount(for: "astro"), 2)
        XCTAssertEqual(store.dueCount(for: "astro", at: now), 1)
        XCTAssertEqual(store.savedCount(for: "missing"), 0)
    }

    func testReviewQueuePrioritizesDueWords() {
        let store = makeStore()
        let now = Date()
        store.add(SavedWord(term: "due", nextReviewAt: now.addingTimeInterval(-60)))
        store.add(SavedWord(term: "future", nextReviewAt: now.addingTimeInterval(600)))
        store.add(SavedWord(term: "mastered", masteryLevel: .mastered, nextReviewAt: now.addingTimeInterval(600)))

        let queue = store.reviewQueue(includeAll: false, at: now)

        XCTAssertEqual(queue.map(\.term), ["due"])
    }

    func testReviewQueueFallsBackToNonMasteredWordsWhenNothingIsDue() {
        let store = makeStore()
        let now = Date()
        store.add(SavedWord(term: "learning", masteryLevel: .learning, nextReviewAt: now.addingTimeInterval(600)))
        store.add(SavedWord(term: "new", nextReviewAt: now.addingTimeInterval(600)))
        store.add(SavedWord(term: "mastered", masteryLevel: .mastered, nextReviewAt: now.addingTimeInterval(600)))

        let queue = store.reviewQueue(includeAll: false, at: now)

        XCTAssertEqual(Set(queue.map(\.term)), Set(["learning", "new"]))
    }

    func testReviewQueueIncludeAllReturnsAllSavedWords() {
        let store = makeStore()
        let now = Date()
        store.add(SavedWord(term: "due", nextReviewAt: now.addingTimeInterval(-60)))
        store.add(SavedWord(term: "mastered", masteryLevel: .mastered, nextReviewAt: now.addingTimeInterval(600)))

        let queue = store.reviewQueue(includeAll: true, at: now)

        XCTAssertEqual(Set(queue.map(\.term)), Set(["due", "mastered"]))
    }

    func testReviewActivityCountsReviewedWordsByDay() {
        let store = makeStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        store.add(SavedWord(term: "today-one", reviewHistory: [today.addingTimeInterval(60)]))
        store.add(SavedWord(term: "today-two", reviewHistory: [today.addingTimeInterval(120)]))
        store.add(SavedWord(term: "yesterday", reviewHistory: [yesterday.addingTimeInterval(60)]))
        store.add(SavedWord(term: "unreviewed"))

        let activity = store.reviewActivity(days: 2, endingAt: today)

        XCTAssertEqual(activity.map(\.count), [1, 2])
    }

    func testReviewActivityCountsMultipleReviewsForSameWord() {
        let store = makeStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let word = SavedWord(term: "orbit")
        store.add(word)

        _ = store.applyReview(.good, to: word, reviewedAt: yesterday.addingTimeInterval(60))
        guard let reviewedYesterday = store.words.first else {
            XCTFail("Expected reviewed word")
            return
        }
        _ = store.applyReview(.good, to: reviewedYesterday, reviewedAt: today.addingTimeInterval(60))

        let activity = store.reviewActivity(days: 2, endingAt: today)

        XCTAssertEqual(activity.map(\.count), [1, 1])
        XCTAssertEqual(store.words.first?.reviewHistory.count, 2)
    }

    func testReviewActivityFallsBackToLegacyLastReviewedAt() {
        let store = makeStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        store.add(SavedWord(term: "legacy", lastReviewedAt: today.addingTimeInterval(60)))

        let activity = store.reviewActivity(days: 1, endingAt: today)

        XCTAssertEqual(activity.first?.count, 1)
    }

    private func makeStore() -> SavedWordsStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = SavedWordsStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return store
    }
}
