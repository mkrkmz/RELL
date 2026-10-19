//
//  EPUBViewManager+Highlights.swift
//  Reader for Language Learner
//
//  Highlights, saved-word underlines, karaoke and find in page. Split out
//  of EPUBViewManager.swift (v19 S0), unchanged.
//

import Foundation
import os
import SwiftUI
import WebKit

extension EPUBViewManager {

    // MARK: Highlights

    /// Re-renders this chapter's highlight marks and saved-word underlines
    /// from current store contents. Safe to call repeatedly — the JS side
    /// clears old marks before re-wrapping. Saved-word marks are applied
    /// *after* highlights: highlight anchors must resolve against a
    /// pristine, unwrapped DOM (see `rellRenderHighlights`), and running
    /// them second here keeps that guarantee regardless of call order.
    func refreshHighlights() {
        guard let webView, let document,
              document.spinePaths.indices.contains(chapterIndex)
        else { return }

        if let highlightsProvider {
            let chapterPath = document.spinePaths[chapterIndex]
            let entries = highlightsProvider(chapterPath)
            webView.evaluateJavaScript(Self.renderHighlightsScript(for: entries, ink: Self.highlightInk(for: currentTheme)))
        }

        if let savedWordTermsProvider {
            let terms = savedWordTermsProvider()
            // Inflections first: they're known to occur in this chapter, so
            // they get the 500-term budget ahead of vocabulary that may not
            // appear here at all.
            let inflected = inflectedChapterForms()
            let marked = Self.dedupedTerms(inflected + terms)
            webView.evaluateJavaScript(Self.markSavedWordsScript(
                for: marked,
                color: Self.savedWordMarkColor(for: currentTheme),
                glosses: Self.glossesIncludingInflections(glosses, inflected: inflected, language: Language.storedTarget),
                glossOnly: glossOnlyTerms,
                glossColor: Self.glossColor(for: currentTheme)
            ))
        }
    }

    /// Dotted-underline tint for saved-word marks — visually distinct from
    /// a user highlight's filled background, and readable against all six
    /// page themes without one fixed color's contrast breaking on the dark
    /// ones.
    static func savedWordMarkColor(for theme: PageTheme) -> String {
        theme.usesLightInk ? "rgba(150, 179, 255, 0.75)" : "rgba(51, 92, 209, 0.65)"
    }

    /// Surface forms of saved vocabulary occurring in the open chapter —
    /// "ran" and "running" for a saved "run". Empty until the chapter's
    /// off-main pass lands, which re-marks with them included.
    private func inflectedChapterForms() -> [String] {
        guard let keys = savedWordKeysProvider?(), !keys.isEmpty,
              let document, document.spinePaths.indices.contains(chapterIndex)
        else { return [] }
        let book = loadedURL?.lastPathComponent ?? ""
        return inflectedTerms.surfaceForms(
            passageKey: "\(book)#c\(chapterIndex)",
            keys: keys,
            language: Language.storedTarget,
            text: document.plainText(at: chapterIndex),
            onReady: { [weak self] in self?.refreshHighlights() }
        )
    }

    /// Case-insensitive dedupe, first occurrence wins.
    private static func dedupedTerms(_ terms: [String]) -> [String] {
        var seen: Set<String> = []
        return terms.filter { seen.insert($0.lowercased()).inserted }
    }

    static func markSavedWordsScript(
        for terms: [String],
        color: String,
        glosses: [String: String] = [:],
        glossOnly: [String] = [],
        glossColor: String = ""
    ) -> String {
        func json<T: Encodable>(_ value: T, fallback: String) -> String {
            (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? fallback
        }
        let capped = Array(terms.prefix(500))
        // JSON-encoded, never interpolated raw: a gloss comes from a model
        // and may contain quotes.
        return "window.rellMarkSavedWords(\(json(capped, fallback: "[]")), '\(color)', "
            + "\(json(glosses, fallback: "{}")), \(json(glossOnly, fallback: "[]")), "
            + "\(json(glossColor, fallback: "\"\"")));"
    }

    /// Meaning colour: quieter than body text, legible on every page theme.
    static func glossColor(for theme: PageTheme) -> String {
        theme.usesLightInk ? "rgba(170, 195, 255, 0.95)" : "rgba(40, 80, 190, 0.9)"
    }

    /// Glosses are keyed by the saved form; the chapter may use "ran" for a
    /// saved "run". Adds each inflected form under its dictionary word's
    /// gloss. Only the few inflected forms are lemmatized, never the whole
    /// vocabulary — this runs on every re-mark.
    nonisolated static func glossesIncludingInflections(
        _ glosses: [String: String],
        inflected: [String],
        language: Language?
    ) -> [String: String] {
        guard !glosses.isEmpty, !inflected.isEmpty else { return glosses }
        var byKey: [String: String] = [:]
        for (term, gloss) in glosses {
            byKey[LemmaMatcher.matchKey(for: term, language: language)] = gloss
        }
        var result = glosses
        for form in inflected where result[form.lowercased()] == nil {
            if let gloss = byKey[LemmaMatcher.matchKey(for: form, language: language)] {
                result[form.lowercased()] = gloss
            }
        }
        return result
    }

    private static func renderHighlightsScript(for highlights: [EPUBHighlight], ink: String) -> String {
        struct Entry: Encodable {
            let id: String
            let quote: String
            let prefix: String
            let suffix: String
            let startOffset: Int
            let color: String
        }
        let entries = highlights.map {
            Entry(
                id: $0.id.uuidString, quote: $0.quote, prefix: $0.prefix,
                suffix: $0.suffix, startOffset: $0.startOffset, color: $0.color.webBackground
            )
        }
        let json = (try? JSONEncoder().encode(entries)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return "window.rellRenderHighlights(\(json), '\(ink)');"
    }

    /// Opens a chapter and scrolls to a highlight's mark once it renders.
    func openChapter(at index: Int, thenScrollToHighlight id: UUID) {
        pendingHighlightScrollID = id
        if index == chapterIndex {
            refreshHighlights()
            scrollToHighlight(id)
            pendingHighlightScrollID = nil
        } else {
            openChapter(at: index)
        }
    }

    // MARK: Karaoke (spoken-sentence tracking)

    /// Highlights the sentence being read aloud and keeps it in view. Passing
    /// nil clears the highlight. Misses are silent — a sentence the tokenizer
    /// produced but that doesn't appear verbatim in the DOM simply isn't
    /// highlighted, and playback continues undisturbed.
    func highlightSpokenSentence(_ sentence: String?) {
        guard let webView else { return }
        guard let sentence, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            webView.evaluateJavaScript("window.rellKaraoke && window.rellKaraoke('');")
            return
        }
        let encoded = (try? JSONEncoder().encode(sentence))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let background = Self.karaokeBackground(for: currentTheme)
        webView.evaluateJavaScript(
            "window.rellKaraoke && window.rellKaraoke(\(encoded), '\(background)');"
        )
    }

    /// Warm wash that stays legible on all six page themes — lighter on dark
    /// ink, deeper on light ink, so the spoken line reads as lit rather than
    /// blacked out.
    static func karaokeBackground(for theme: PageTheme) -> String {
        theme.usesLightInk ? "rgba(255, 214, 102, 0.32)" : "rgba(255, 205, 90, 0.55)"
    }

    func scrollToHighlight(_ id: UUID) {
        webView?.evaluateJavaScript(
            "document.querySelector('mark[data-rell-highlight-id=\"\(id.uuidString)\"]')" +
            "?.scrollIntoView({block: 'center'});"
        )
    }

    // MARK: Find in page

    /// Highlights the next/previous occurrence in the loaded chapter using
    /// WebKit's native find (Safari-style selection + scroll).
    func findInPage(_ term: String, forward: Bool = true) {
        guard let webView, !term.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(term, configuration: configuration) { _ in }
    }

    /// Opens a chapter and highlights `term` once it has loaded.
    func openChapter(at index: Int, thenFind term: String) {
        pendingFindTerm = term
        if index == chapterIndex {
            findInPage(term)
            pendingFindTerm = nil
        } else {
            openChapter(at: index)
        }
    }
}
