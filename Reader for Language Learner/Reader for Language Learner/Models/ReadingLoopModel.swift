//
//  ReadingLoopModel.swift
//  Reader for Language Learner
//
//  Per-window runner for the reading loop (Roadmap v13 Sprint 2): the
//  "previously…" recap on return and the chapter warm-up. Text extraction
//  and tagging run off the main actor; the model calls go through
//  `AppleOnDevice.chatWithFallback`.
//

import Foundation
import os
import PDFKit

@MainActor
@Observable
final class ReadingLoopModel {

    enum RecapState: Equatable {
        case hidden
        case loading(title: String)
        case ready(title: String, text: String)
    }

    enum WarmUpState: Equatable {
        case none
        case loading
        case ready([ChapterWarmUp.Word])
    }

    private(set) var recap: RecapState = .hidden
    private(set) var warmUp: WarmUpState = .none
    /// Chapter the warm-up belongs to — stale results for another are dropped.
    private(set) var warmUpChapter: Int?

    @ObservationIgnored private var recapTask: Task<Void, Never>?
    @ObservationIgnored private var warmUpTask: Task<Void, Never>?
    /// A recap decided at open time, waiting for the EPUB to finish loading.
    @ObservationIgnored private var pendingEPUBRecap: (url: URL, title: String)?
    /// Finished warm-ups per book+chapter, so paging back and forth doesn't
    /// ask again.
    @ObservationIgnored private var warmUpCache = LRUCache<String, [ChapterWarmUp.Word]>(capacity: 30)

    // MARK: - Recap

    /// Call when a document opens, with its library entry as it was *before*
    /// this open touched `lastOpenedAt`.
    func documentOpened(url: URL, previous: RecentDocument?, now: Date = Date()) {
        dismissRecap()
        pendingEPUBRecap = nil
        warmUpTask?.cancel()
        warmUp = .none
        warmUpChapter = nil

        guard UserDefaults.standard.object(forKey: StorageKey.readingRecapEnabled) as? Bool ?? true,
              let previous,
              ReadingRecap.isDue(
                lastOpenedAt: previous.lastOpenedAt,
                now: now,
                hasProgress: (previous.lastPageIndex ?? 0) > 0
                    || (url.pathExtension.lowercased() == "epub"
                        && EPUBViewManager.startPosition(for: url).fraction > 0)
              )
        else { return }

        let title = previous.displayTitle
        if url.pathExtension.lowercased() == "epub" {
            pendingEPUBRecap = (url, title)
        } else if let page = previous.lastPageIndex {
            startRecap(title: title) {
                Self.pdfPassage(url: url, upToPage: page)
            }
        }
    }

    /// Call once the EPUB's archive is parsed.
    func epubLoaded(url: URL, document: EPUBDocument) {
        guard let pending = pendingEPUBRecap, pending.url == url else { return }
        pendingEPUBRecap = nil
        let position = EPUBViewManager.startPosition(for: url)
        startRecap(title: pending.title) {
            let chapter = min(max(0, position.chapter), document.chapterCount - 1)
            // Early in a chapter, the end of the last one says more.
            let earlier = chapter > 0 && position.fraction < 0.3 ? document.plainText(at: chapter - 1) : ""
            return ReadingRecap.passage(
                current: document.plainText(at: chapter),
                upTo: position.fraction,
                earlier: earlier
            )
        }
    }

    func dismissRecap() {
        recapTask?.cancel()
        recapTask = nil
        recap = .hidden
    }

    private func startRecap(title: String, passage: @escaping @Sendable () -> String) {
        let language = Language.storedTarget
        let level = CEFRLevel.storedLearnerLevel
        recap = .loading(title: title)
        recapTask = Task { [weak self] in
            let text = await Task.detached(priority: .utility) { passage() }.value
            guard !Task.isCancelled, !text.isEmpty else {
                self?.recap = .hidden
                return
            }
            do {
                let raw = try await AppleOnDevice.chatWithFallback(
                    system: ReadingRecap.systemPrompt(language: language, level: level),
                    user: ReadingRecap.userPrompt(passage: text),
                    temperature: 0.3,
                    maxTokens: ReadingRecap.maxTokens
                )
                guard !Task.isCancelled, let self else { return }
                if let cleaned = ReadingRecap.clean(raw) {
                    self.recap = .ready(title: title, text: cleaned)
                } else {
                    self.recap = .hidden
                }
            } catch {
                // A recap is a courtesy; failing quietly beats an error card
                // in front of the book the reader came back to.
                AppLogger.llm.info("Recap failed: \(error.localizedDescription, privacy: .public)")
                guard !Task.isCancelled else { return }
                self?.recap = .hidden
            }
        }
    }

    /// The last few pages up to the bookmark, read off the main actor.
    nonisolated static func pdfPassage(url: URL, upToPage page: Int) -> String {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return "" }
        let last = min(page, document.pageCount - 1)
        let first = max(0, last - 3)
        let text = (first...last).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
        return ReadingRecap.passage(current: text)
    }

    // MARK: - Warm-up

    /// Call when an EPUB chapter opens. Computes in the background; the
    /// reader sees a chip once there's something to show.
    func chapterOpened(
        _ chapter: Int,
        bookKey: String,
        document: EPUBDocument,
        savedKeys: Set<String>
    ) {
        guard UserDefaults.standard.object(forKey: StorageKey.chapterWarmUpEnabled) as? Bool ?? true else {
            warmUp = .none
            return
        }
        guard chapter != warmUpChapter else { return }
        warmUpTask?.cancel()
        warmUpChapter = chapter

        let cacheKey = "\(bookKey)#\(chapter)"
        if let cached = warmUpCache.get(cacheKey) {
            warmUp = cached.isEmpty ? .none : .ready(cached)
            return
        }

        let target = Language.storedTarget
        let answerIn = HoverDictionaryLanguage.stored == .native ? Language.storedNative : target
        let level = CEFRLevel.storedLearnerLevel
        warmUp = .loading
        warmUpTask = Task { [weak self] in
            let (text, candidates) = await Task.detached(priority: .utility) {
                let text = document.plainText(at: chapter)
                return (text, ChapterWarmUp.candidates(in: text, language: target, excludingKeys: savedKeys))
            }.value
            guard !Task.isCancelled else { return }
            // A short chapter (a title page, a dedication) has nothing to warm up.
            guard candidates.count >= ChapterWarmUp.maxWords else {
                self?.finishWarmUp([], key: cacheKey, chapter: chapter)
                return
            }
            do {
                let raw = try await AppleOnDevice.chatWithFallback(
                    system: ChapterWarmUp.systemPrompt(target: target, answerIn: answerIn, level: level),
                    user: ChapterWarmUp.userPrompt(candidates: candidates),
                    temperature: 0.2,
                    maxTokens: ChapterWarmUp.maxTokens
                )
                guard !Task.isCancelled else { return }
                let picked = ChapterWarmUp.parse(raw, offered: candidates)
                let words = await Task.detached(priority: .utility) {
                    ChapterWarmUp.attachSentences(picked, chapter: text, language: target)
                }.value
                guard !Task.isCancelled else { return }
                self?.finishWarmUp(words, key: cacheKey, chapter: chapter)
            } catch {
                AppLogger.llm.info("Warm-up failed: \(error.localizedDescription, privacy: .public)")
                guard !Task.isCancelled else { return }
                // Not cached: the next visit may find the provider back.
                if self?.warmUpChapter == chapter { self?.warmUp = .none }
            }
        }
    }

    private func finishWarmUp(_ words: [ChapterWarmUp.Word], key: String, chapter: Int) {
        warmUpCache.set(key, words)
        guard warmUpChapter == chapter else { return }
        warmUp = words.isEmpty ? .none : .ready(words)
    }

    func clearWarmUp() {
        warmUpTask?.cancel()
        warmUp = .none
        warmUpChapter = nil
    }
}
