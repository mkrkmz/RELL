//
//  FSRSSchedulerTests.swift
//  Reader for Language LearnerTests
//
//  Golden vectors and invariants for the FSRS-4.5 implementation
//  (Roadmap v9 Sprint 3, L1). Pure math — no store, no persistence.
//

import XCTest
@testable import Reader_for_Language_Learner

final class FSRSSchedulerTests: XCTestCase {

    private let w = FSRSScheduler.defaultWeights

    // MARK: - Forgetting curve

    /// The model's defining property: after exactly `stability` days, recall
    /// probability has decayed to the 0.9 desired retention.
    func testRetrievabilityAtStabilityEqualsDesiredRetention() {
        let recall = FSRSScheduler.retrievability(elapsedDays: 10, stability: 10)
        XCTAssertEqual(recall, 0.9, accuracy: 0.0001)
    }

    func testRetrievabilityIsOneAtZeroElapsed() {
        XCTAssertEqual(FSRSScheduler.retrievability(elapsedDays: 0, stability: 5), 1.0, accuracy: 0.0001)
    }

    func testRetrievabilityDecaysMonotonically() {
        let early = FSRSScheduler.retrievability(elapsedDays: 1, stability: 10)
        let later = FSRSScheduler.retrievability(elapsedDays: 30, stability: 10)
        XCTAssertGreaterThan(early, later)
        XCTAssertLessThan(later, 0.9)
    }

    /// At 90% desired retention the scheduled interval equals stability — the
    /// two are the same quantity by construction.
    func testIntervalMatchesStabilityAtDefaultRetention() {
        XCTAssertEqual(FSRSScheduler.interval(stability: 12.5), 12.5, accuracy: 0.001)
    }

    func testHigherRetentionShortensTheInterval() {
        let relaxed = FSRSScheduler.interval(stability: 10, desiredRetention: 0.8)
        let strict  = FSRSScheduler.interval(stability: 10, desiredRetention: 0.95)
        XCTAssertGreaterThan(relaxed, strict)
    }

    // MARK: - Initial state (golden vectors)

    func testInitialStabilityIsTheGradeWeight() {
        XCTAssertEqual(FSRSScheduler.initialState(grade: .again).stability, w[0], accuracy: 0.0001)
        XCTAssertEqual(FSRSScheduler.initialState(grade: .hard).stability,  w[1], accuracy: 0.0001)
        XCTAssertEqual(FSRSScheduler.initialState(grade: .good).stability,  w[2], accuracy: 0.0001)
        XCTAssertEqual(FSRSScheduler.initialState(grade: .easy).stability,  w[3], accuracy: 0.0001)
    }

    func testInitialDifficultyIsLinearInGrade() {
        // D0(good) is w[4] itself; each grade step moves it by w[5].
        XCTAssertEqual(FSRSScheduler.initialState(grade: .good).difficulty, w[4], accuracy: 0.0001)
        XCTAssertEqual(FSRSScheduler.initialState(grade: .easy).difficulty, w[4] - w[5], accuracy: 0.0001)
        XCTAssertEqual(FSRSScheduler.initialState(grade: .again).difficulty, w[4] + 2 * w[5], accuracy: 0.0001)
    }

    func testInitialDifficultyStaysInRange() {
        for grade in [FSRSGrade.again, .hard, .good, .easy] {
            let d = FSRSScheduler.initialState(grade: grade).difficulty
            XCTAssertGreaterThanOrEqual(d, 1)
            XCTAssertLessThanOrEqual(d, 10)
        }
    }

    // MARK: - State transitions

    func testSuccessfulReviewGrowsStability() {
        let state = FSRSState(stability: 10, difficulty: 5)
        let next = FSRSScheduler.nextState(state, grade: .good, elapsedDays: 10)
        XCTAssertGreaterThan(next.stability, state.stability, "a successful recall must extend the interval")
    }

    func testBetterGradesGrowStabilityMore() {
        let state = FSRSState(stability: 10, difficulty: 5)
        let hard = FSRSScheduler.nextState(state, grade: .hard, elapsedDays: 10).stability
        let good = FSRSScheduler.nextState(state, grade: .good, elapsedDays: 10).stability
        let easy = FSRSScheduler.nextState(state, grade: .easy, elapsedDays: 10).stability
        XCTAssertLessThan(hard, good)
        XCTAssertLessThan(good, easy)
    }

    func testLapseNeverIncreasesStability() {
        let state = FSRSState(stability: 30, difficulty: 5)
        let next = FSRSScheduler.nextState(state, grade: .again, elapsedDays: 30)
        XCTAssertLessThanOrEqual(next.stability, state.stability)
        XCTAssertGreaterThan(next.stability, 0)
    }

    func testLapseRaisesDifficultyAndEasyLowersIt() {
        let state = FSRSState(stability: 10, difficulty: 5)
        let lapsed = FSRSScheduler.nextState(state, grade: .again, elapsedDays: 10)
        let easy   = FSRSScheduler.nextState(state, grade: .easy, elapsedDays: 10)
        XCTAssertGreaterThan(lapsed.difficulty, state.difficulty)
        XCTAssertLessThan(easy.difficulty, state.difficulty)
    }

    func testDifficultyStaysClampedUnderRepeatedLapses() {
        var state = FSRSState(stability: 10, difficulty: 9.5)
        for _ in 0..<20 {
            state = FSRSScheduler.nextState(state, grade: .again, elapsedDays: 5)
        }
        XCTAssertLessThanOrEqual(state.difficulty, 10)
        XCTAssertGreaterThanOrEqual(state.difficulty, 1)
    }

    /// Reviewing later (lower recall probability at review time) earns more
    /// stability than reviewing early — FSRS's spacing effect.
    func testDelayedSuccessfulReviewEarnsMoreStability() {
        let state = FSRSState(stability: 10, difficulty: 5)
        let early = FSRSScheduler.nextState(state, grade: .good, elapsedDays: 1).stability
        let onTime = FSRSScheduler.nextState(state, grade: .good, elapsedDays: 10).stability
        XCTAssertGreaterThan(onTime, early)
    }

    func testEasierWordsGainStabilityFasterThanHardOnes() {
        let easyWord = FSRSState(stability: 10, difficulty: 2)
        let hardWord = FSRSState(stability: 10, difficulty: 9)
        let easyGain = FSRSScheduler.nextState(easyWord, grade: .good, elapsedDays: 10).stability
        let hardGain = FSRSScheduler.nextState(hardWord, grade: .good, elapsedDays: 10).stability
        XCTAssertGreaterThan(easyGain, hardGain)
    }

    // MARK: - Migration seeding

    func testSeedMapsEaseInverselyOntoDifficulty() {
        let neutral = FSRSScheduler.seedState(easeFactor: 2.5, previousIntervalDays: nil,
                                              isMastered: false, hasBeenReviewed: true)
        let easiest = FSRSScheduler.seedState(easeFactor: 3.5, previousIntervalDays: nil,
                                              isMastered: false, hasBeenReviewed: true)
        let hardest = FSRSScheduler.seedState(easeFactor: 1.3, previousIntervalDays: nil,
                                              isMastered: false, hasBeenReviewed: true)
        XCTAssertEqual(easiest.difficulty, 1, accuracy: 0.0001, "max ease is the easiest word")
        XCTAssertEqual(hardest.difficulty, 10, accuracy: 0.0001, "min ease is the hardest word")
        XCTAssertEqual(neutral.difficulty, 5.0909, accuracy: 0.001)
    }

    func testSeedTakesStabilityFromThePreviousInterval() {
        let seeded = FSRSScheduler.seedState(easeFactor: 2.5, previousIntervalDays: 30,
                                             isMastered: true, hasBeenReviewed: true)
        XCTAssertEqual(seeded.stability, 30, accuracy: 0.0001, "an existing schedule carries over")
    }

    func testSeedFallsBackByMasteryWhenNoIntervalIsKnown() {
        let mastered = FSRSScheduler.seedState(easeFactor: 2.5, previousIntervalDays: nil,
                                               isMastered: true, hasBeenReviewed: true)
        let learning = FSRSScheduler.seedState(easeFactor: 2.5, previousIntervalDays: nil,
                                               isMastered: false, hasBeenReviewed: true)
        let fresh    = FSRSScheduler.seedState(easeFactor: 2.5, previousIntervalDays: nil,
                                               isMastered: false, hasBeenReviewed: false)
        XCTAssertEqual(mastered.stability, FSRSScheduler.masteredStabilityThreshold, accuracy: 0.0001)
        XCTAssertEqual(learning.stability, 3, accuracy: 0.0001)
        XCTAssertEqual(fresh.stability, w[2], accuracy: 0.0001)
        XCTAssertLessThan(learning.stability, mastered.stability)
    }

    func testSeedClampsAbsurdIntervals() {
        let seeded = FSRSScheduler.seedState(easeFactor: 2.5, previousIntervalDays: 10_000,
                                             isMastered: true, hasBeenReviewed: true)
        XCTAssertLessThanOrEqual(seeded.stability, 365)
    }
}
