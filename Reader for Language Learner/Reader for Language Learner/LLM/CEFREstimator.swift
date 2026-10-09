//
//  CEFREstimator.swift
//  Reader for Language Learner
//
//  LLM-backed CEFR level estimation for saved words. Two entry points:
//  a fire-and-forget estimate when a word is saved without a level, and
//  `estimate(term:)` for "Fill Missing" (`WordEnricher`, v15 S1), which
//  took over the bulk pass over every unrated word. Estimates only ever
//  fill `cefrLevel == nil` — a user-assigned level is never overwritten —
//  and failures write nothing (a wrong badge is worse than no badge).
//

import Foundation
import os

@MainActor
@Observable
final class CEFREstimator {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}


    private let savedWordsStore: SavedWordsStore
    /// Single-slot gate: estimation is background nicety traffic and must
    /// never compete with the inspector/HUD for a local server's one GPU context.
    @ObservationIgnored private let gate = AsyncLimiter(limit: 1)

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

    // MARK: - Single estimate

    /// One micro-request → one strict-parsed token. Any failure or format
    /// drift returns nil; nothing is stored.
    func estimate(term: String) async -> CEFRLevel? {
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
            let provider = AppleOnDevice.provider(for: nil)
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
