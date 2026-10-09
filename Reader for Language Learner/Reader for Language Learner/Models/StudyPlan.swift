//
//  StudyPlan.swift
//  Reader for Language Learner
//
//  What a session in the study room (Roadmap v15 Sprint 2) is made of, and
//  what it adds up to at the end. Pure: the queue and the summary are
//  computed from the saved words and a date, so both are unit-tested.
//
//  Approved decisions: a session is 20 words by default (the choice is
//  remembered), at most 5 new words join it, reviews come first with the
//  new ones spread among them.
//

import Foundation

/// Where a session's words come from.
enum StudySource: Hashable {
    case all
    /// Words saved from one book — this file, other copies and Kindle,
    /// matched by title unless switched off for the book (v16 S1).
    case book(BookIdentity.Document)
    /// A deck (tag).
    case deck(String)
    /// Words you've marked "Again" at least `StudyPlan.strugglingThreshold` times.
    case struggling
}

struct StudyPlan: Equatable {
    /// Words per session; 0 means every word waiting.
    var size: Int = 20
    var source: StudySource = .all
    /// New (never reviewed) words a session may take.
    var newLimit: Int = 5

    static let sizeChoices = [10, 20, 0]
    static let newLimitChoices = [0, 5, 10]
    /// "Again" this many times or more makes a word one you keep forgetting.
    static let strugglingThreshold = 2
    /// A word whose next review is this many days away or more has settled.
    static let settledDays = 7.0

    // MARK: Queue

    /// The words for a session, in order: reviews oldest-due first, new
    /// words spread evenly among them. Struggling words come regardless of
    /// whether they're due, most-forgotten first.
    func queue(from words: [SavedWord], at now: Date = Date()) -> [SavedWord] {
        let pool = Self.words(in: source, from: words)
        let cap = size > 0 ? size : Int.max

        if source == .struggling {
            return Array(pool.sorted { $0.incorrectCount > $1.incorrectCount }.prefix(cap))
        }

        let reviews = pool
            .filter { $0.hasBeenReviewed && $0.isDue(at: now) }
            .sorted { ($0.nextReviewAt ?? .distantPast) < ($1.nextReviewAt ?? .distantPast) }
        let fresh = pool
            .filter { !$0.hasBeenReviewed }
            .sorted { $0.savedAt < $1.savedAt }

        let newTake = min(newLimit, fresh.count, cap)
        let reviewTake = min(reviews.count, cap - newTake)
        return Self.interleave(Array(reviews.prefix(reviewTake)), Array(fresh.prefix(newTake)))
    }

    /// Words of `source` that aren't due — what "Practice anyway" runs when
    /// nothing is waiting. Practice doesn't touch the schedule.
    func practiceQueue(from words: [SavedWord], at now: Date = Date()) -> [SavedWord] {
        let pool = Self.words(in: source, from: words).filter { $0.hasBeenReviewed && !$0.isDue(at: now) }
        let cap = size > 0 ? size : Int.max
        // The ones closest to coming due first: they gain most from practice.
        return Array(pool.sorted { ($0.nextReviewAt ?? .distantFuture) < ($1.nextReviewAt ?? .distantFuture) }.prefix(cap))
    }

    static func words(in source: StudySource, from words: [SavedWord]) -> [SavedWord] {
        switch source {
        case .all:            return words
        case .book(let document):
            return BookWords(document: document, words: words, encounters: [],
                             matchingTitles: BookWords.matchesTitles(forDocumentAt: document.path)).saved
        case .deck(let tag):  return words.filter { $0.hasTag(tag) }
        case .struggling:     return words.filter { $0.incorrectCount >= strugglingThreshold }
        }
    }

    /// `extra` spread evenly through `base`: 2 new among 6 reviews land
    /// after the 2nd and the 4th.
    static func interleave(_ base: [SavedWord], _ extra: [SavedWord]) -> [SavedWord] {
        guard !extra.isEmpty else { return base }
        guard !base.isEmpty else { return extra }
        var result: [SavedWord] = []
        let step = Double(base.count) / Double(extra.count + 1)
        var next = 0
        for (index, word) in base.enumerated() {
            result.append(word)
            while next < extra.count, Double(index + 1) >= step * Double(next + 1) {
                result.append(extra[next])
                next += 1
            }
        }
        result.append(contentsOf: extra[next...])
        return result
    }

    // MARK: Counts for the setup screen

    static func dueReviewCount(in words: [SavedWord], at now: Date = Date()) -> Int {
        words.count { $0.hasBeenReviewed && $0.isDue(at: now) }
    }

    static func newCount(in words: [SavedWord]) -> Int {
        words.count { !$0.hasBeenReviewed }
    }

    /// Reviewed words not due now that will be by the end of tomorrow.
    static func comingDueTomorrow(in words: [SavedWord], at now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) else { return 0 }
        return words.count { word in
            guard word.hasBeenReviewed, let next = word.nextReviewAt else { return false }
            return next > now && next < endOfTomorrow
        }
    }

    // MARK: Interval labels

    /// "10 min", "4 days", "2 months" — how far away `date` is.
    static func intervalLabel(from now: Date, to date: Date) -> String {
        let seconds = max(60, date.timeIntervalSince(now))
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 1
        if seconds < 3_600 {
            formatter.allowedUnits = [.minute]
        } else if seconds < 86_400 {
            formatter.allowedUnits = [.hour]
        } else if seconds < 60 * 86_400 {
            formatter.allowedUnits = [.day]
            // Whole days: 3 days 20 hours reads as 4 days.
            return formatter.string(from: (seconds / 86_400).rounded() * 86_400) ?? ""
        } else {
            formatter.allowedUnits = [.month, .year]
        }
        return formatter.string(from: seconds) ?? ""
    }
}

// MARK: - Summary

/// What a session added up to (the summary screen).
struct StudySummary: Equatable {
    struct Line: Equatable, Identifiable {
        let id: UUID
        let term: String
        let nextReviewAt: Date?
    }

    /// Words answered without an "Again".
    let remembered: Int
    /// Words marked "Again" at least once.
    let struggled: [Line]
    /// Words whose next review is now a week or more away.
    let settled: [Line]
    let duration: TimeInterval

    init(answers: [QuizSession.Answer], startedAt: Date?, now: Date = Date()) {
        var order: [UUID] = []
        var byWord: [UUID: [QuizSession.Answer]] = [:]
        for answer in answers {
            if byWord[answer.wordID] == nil { order.append(answer.wordID) }
            byWord[answer.wordID, default: []].append(answer)
        }
        var remembered = 0
        var struggled: [Line] = []
        var settled: [Line] = []
        for id in order {
            guard let list = byWord[id], let last = list.last else { continue }
            let line = Line(id: id, term: last.term, nextReviewAt: last.nextReviewAt)
            if list.contains(where: { $0.rating == .again }) {
                struggled.append(line)
            } else {
                remembered += 1
            }
            if let next = last.nextReviewAt, next.timeIntervalSince(now) >= StudyPlan.settledDays * 86_400 {
                settled.append(line)
            }
        }
        self.remembered = remembered
        self.struggled = struggled
        self.settled = settled
        self.duration = startedAt.map { now.timeIntervalSince($0) } ?? 0
    }
}
