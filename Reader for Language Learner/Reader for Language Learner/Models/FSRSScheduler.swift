//
//  FSRSScheduler.swift
//  Reader for Language Learner
//
//  A pure, dependency-free implementation of FSRS-4.5 (Free Spaced Repetition
//  Scheduler) — the modern successor to SM-2 and the algorithm behind current
//  Anki. Replaces the hand-rolled SM-2-lite intervals with a memory model:
//  every word carries a *stability* (how many days until recall probability
//  falls to the desired retention) and a *difficulty* (1…10), and each review
//  updates both from the elapsed time and the grade.
//
//  Everything here is a pure function over value types so the scheduling math
//  is unit-testable in isolation from persistence and UI.
//

import Foundation

/// FSRS's four-button grading scale.
enum FSRSGrade: Int {
    case again = 1
    case hard  = 2
    case good  = 3
    case easy  = 4
}

/// A word's memory state. `nil` on words that have never been scheduled by
/// FSRS — `SavedWordsStore` seeds those from their legacy SM-2 fields.
struct FSRSState: Equatable, Codable {
    /// Days until recall probability decays to the desired retention.
    var stability: Double
    /// 1 (easiest) … 10 (hardest).
    var difficulty: Double
}

enum FSRSScheduler {

    // MARK: - Model constants

    /// Published FSRS-4.5 default weights. Tuned on a large public review
    /// corpus; per-user optimization is a possible later refinement.
    static let defaultWeights: [Double] = [
        0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.0310,
        1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.5870, 0.2272, 2.8755
    ]

    /// Forgetting-curve shape constants from FSRS-4.5.
    static let decay = -0.5
    static let factor = 19.0 / 81.0

    /// Target probability of recall when a card comes due. 0.9 is FSRS's
    /// default and a good balance of workload against retention.
    static let defaultDesiredRetention = 0.9

    /// Stability (in days) at or above which a word reads as "mastered" in the
    /// UI — roughly three weeks of durable recall.
    static let masteredStabilityThreshold = 21.0

    // MARK: - Core model

    /// Probability of recall after `elapsedDays` given `stability`.
    static func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        let days = max(0, elapsedDays)
        return pow(1 + factor * days / stability, decay)
    }

    /// Days until recall decays to `desiredRetention`, i.e. the next interval.
    static func interval(
        stability: Double,
        desiredRetention: Double = defaultDesiredRetention
    ) -> Double {
        guard stability > 0, desiredRetention > 0, desiredRetention < 1 else { return 1 }
        return (stability / factor) * (pow(desiredRetention, 1 / decay) - 1)
    }

    /// Memory state for a word's very first graded review.
    ///
    /// FSRS-4.5's initial difficulty is linear in the grade — `w[4]` is the
    /// difficulty of a first "good", nudged by `w[5]` per grade step. (The
    /// exponential form belongs to FSRS-5 and its different weight set.)
    static func initialState(grade: FSRSGrade, weights: [Double] = defaultWeights) -> FSRSState {
        let w = weights
        let stability = max(0.1, w[grade.rawValue - 1])
        let difficulty = clampDifficulty(w[4] - Double(grade.rawValue - 3) * w[5])
        return FSRSState(stability: stability, difficulty: difficulty)
    }

    /// Difficulty of a first "easy" answer — the anchor difficulty reverts to.
    private static func easyInitialDifficulty(_ w: [Double]) -> Double {
        w[4] - w[5]
    }

    /// Memory state after grading a word that already has one.
    /// - Parameter elapsedDays: days since the previous review (0 for same-day).
    static func nextState(
        _ state: FSRSState,
        grade: FSRSGrade,
        elapsedDays: Double,
        weights: [Double] = defaultWeights
    ) -> FSRSState {
        let w = weights
        let recall = retrievability(elapsedDays: elapsedDays, stability: state.stability)

        // Difficulty: shift by grade, then mean-revert toward the "easy" init.
        let shifted = state.difficulty - w[6] * Double(grade.rawValue - 3)
        let difficulty = clampDifficulty(
            w[7] * easyInitialDifficulty(w) + (1 - w[7]) * shifted
        )

        let stability: Double
        if grade == .again {
            // Lapse: stability collapses toward a fresh, difficulty-scaled value.
            let lapsed = w[11]
                * pow(state.difficulty, -w[12])
                * (pow(state.stability + 1, w[13]) - 1)
                * exp(w[14] * (1 - recall))
            // A lapse must never *increase* stability.
            stability = max(0.1, min(lapsed, state.stability))
        } else {
            let hardPenalty = grade == .hard ? w[15] : 1
            let easyBonus   = grade == .easy ? w[16] : 1
            let growth = exp(w[8])
                * (11 - state.difficulty)
                * pow(state.stability, -w[9])
                * (exp(w[10] * (1 - recall)) - 1)
                * hardPenalty
                * easyBonus
            stability = max(0.1, state.stability * (1 + growth))
        }

        return FSRSState(stability: stability, difficulty: difficulty)
    }

    // MARK: - Migration

    /// Seeds an FSRS state for a word scheduled by the old SM-2-lite engine, so
    /// an existing library keeps its momentum instead of resetting to new.
    ///
    /// - `easeFactor` (1.3…3.5, 2.5 neutral) maps inversely onto difficulty:
    ///   an easy word becomes a low-difficulty one.
    /// - Stability is seeded from the interval the old engine had settled on
    ///   (its own estimate of how long the word sticks), falling back to a
    ///   mastery-level default for words that were never scheduled.
    static func seedState(
        easeFactor: Double,
        previousIntervalDays: Double?,
        isMastered: Bool,
        hasBeenReviewed: Bool
    ) -> FSRSState {
        let clampedEase = min(max(easeFactor, 1.3), 3.5)
        // 1.3 → 10 (hardest), 3.5 → 1 (easiest).
        let difficulty = clampDifficulty(10 - (clampedEase - 1.3) / (3.5 - 1.3) * 9)

        let stability: Double
        if let previousIntervalDays, previousIntervalDays >= 0.5 {
            stability = min(previousIntervalDays, 365)
        } else if isMastered {
            stability = masteredStabilityThreshold
        } else if hasBeenReviewed {
            stability = 3
        } else {
            stability = max(0.1, defaultWeights[2])   // fresh "good" stability
        }

        return FSRSState(stability: stability, difficulty: difficulty)
    }

    // MARK: - Helpers

    private static func clampDifficulty(_ value: Double) -> Double {
        min(max(value, 1), 10)
    }
}
