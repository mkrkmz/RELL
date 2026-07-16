//
//  CEFREstimator.swift
//  Reader for Language Learner
//
//  LLM-backed CEFR level estimation for saved words. Two entry points:
//  a fire-and-forget estimate when a word is saved without a level, and a
//  user-triggered bulk pass over every unrated word. Estimates only ever
//  fill `cefrLevel == nil` — a user-assigned level is never overwritten —
//  and failures write nothing (a wrong badge is worse than no badge).
//

import Foundation
import os

@MainActor
@Observable
final class CEFREstimator {

    private let savedWordsStore: SavedWordsStore
    /// Single-slot gate: estimation is background nicety traffic and must
    /// never compete with the inspector/HUD for a local server's one GPU context.
    @ObservationIgnored private let gate = AsyncLimiter(limit: 1)

    // Bulk-run state for the toolbar popover.
    private(set) var isRunningBulk = false
    private(set) var bulkCompleted = 0
    private(set) var bulkTotal = 0
    @ObservationIgnored private var bulkTask: Task<Void, Never>?

    init(savedWordsStore: SavedWordsStore) {
        self.savedWordsStore = savedWordsStore

        // Save call sites (inspector, context menus, HUD) stay untouched —
        // the store announces new words and estimation hooks in here.
        NotificationCenter.default.addObserver(
            forName: .savedWordAdded, object: nil, queue: .main
        ) { [weak self] note in
            guard let id = note.object as? UUID else { return }
            Task { @MainActor [weak self] in
                self?.estimateIfNeeded(wordID: id)
            }
        }
    }

    // MARK: - Save-time estimation

    /// Estimates in the background when the word is still unrated. No-op for
    /// rated words, so a save → manual-assign race can't clobber the user.
    func estimateIfNeeded(wordID: UUID) {
        guard let word = savedWordsStore.word(withID: wordID), word.cefrLevel == nil else { return }
        let term = word.term
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            if let level = await self.estimate(term: term) {
                self.savedWordsStore.setAutoCEFRLevel(level, forWordID: wordID)
            }
        }
    }

    // MARK: - Bulk estimation

    var unratedCount: Int {
        savedWordsStore.words.count(where: { $0.cefrLevel == nil })
    }

    func estimateMissing() {
        guard !isRunningBulk else { return }
        let targets = savedWordsStore.words.filter { $0.cefrLevel == nil }.map { ($0.id, $0.term) }
        guard !targets.isEmpty else { return }

        isRunningBulk = true
        bulkCompleted = 0
        bulkTotal = targets.count

        bulkTask = Task(priority: .utility) { [weak self] in
            for (id, term) in targets {
                guard let self, !Task.isCancelled else { break }
                if let level = await self.estimate(term: term) {
                    // Re-check nil — the user may have assigned a level mid-run.
                    if self.savedWordsStore.word(withID: id)?.cefrLevel == nil {
                        self.savedWordsStore.setAutoCEFRLevel(level, forWordID: id)
                    }
                }
                self.bulkCompleted += 1
            }
            self?.isRunningBulk = false
            self?.bulkTask = nil
        }
    }

    func cancelBulk() {
        bulkTask?.cancel()
        bulkTask = nil
        isRunningBulk = false
    }

    // MARK: - Single estimate

    /// One micro-request → one strict-parsed token. Any failure or format
    /// drift returns nil; nothing is stored.
    private func estimate(term: String) async -> CEFRLevel? {
        await gate.acquire()
        defer { gate.release() }
        guard !Task.isCancelled else { return nil }

        let target = Language.storedTarget
        let system = """
        You classify vocabulary difficulty for language learners on the CEFR scale.
        Answer with exactly one token: A1, A2, B1, B2, C1, or C2.
        No other text.
        """
        let user = "CEFR level of \"\(term)\" for a learner of \(target.rawValue):"

        do {
            let provider = LLMConfiguration().makeProvider()
            let raw = try await provider.chat(
                system: system,
                user: user,
                temperature: 0.0,
                maxTokens: 8,
                topP: 0.9
            )
            guard let level = Self.parseLevel(raw) else {
                AppLogger.llm.info("CEFR estimate for \(term, privacy: .private) unparseable: \(raw, privacy: .private)")
                return nil
            }
            return level
        } catch {
            AppLogger.llm.info("CEFR estimate failed for \(term, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Strict single-token parse — tolerates whitespace and trailing
    /// punctuation, rejects anything else (no substring fishing).
    static func parseLevel(_ raw: String) -> CEFRLevel? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .uppercased()
        return CEFRLevel(rawValue: cleaned)
    }
}
