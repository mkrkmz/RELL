//
//  WhatsNew.swift
//  Reader for Language Learner
//
//  The short "What's new" page shown once after an update (v14 S3), and
//  from Help ▸ What's New in RELL. Written by hand for each release from
//  its CHANGELOG section: a few lines a reader cares about, not the list.
//

import Foundation

nonisolated struct WhatsNew: Equatable, Sendable, Identifiable {
    var id: String { version }

    struct Item: Equatable, Sendable {
        let icon: String
        let title: String
        let detail: String
    }

    /// "major.minor" — patch releases show the page of their minor.
    let version: String
    let items: [Item]

    /// Newest first.
    static var releases: [WhatsNew] {
        [
            WhatsNew(version: "1.45", items: [
                Item(icon: "book.closed",
                     title: String(localized: "A book shows its own words"),
                     detail: String(localized: "The sidebar lists the words saved from the open book — other copies and Kindle included — and the ones you met again in it.")),
                Item(icon: "character.book.closed",
                     title: String(localized: "Every word in the word notebook"),
                     detail: String(localized: "Its own window (⌥⌘K) with books, decks and states, a sortable table and each word's page beside the list.")),
                Item(icon: "square.on.square",
                     title: String(localized: "One word, not two"),
                     detail: String(localized: "Words saved under two forms, like gleam and gleaming, are found and merged on request, history and all.")),
                Item(icon: "books.vertical",
                     title: String(localized: "Kindle words, as they come"),
                     detail: String(localized: "The home screen says when your Kindle has new words; Fill Missing goes on after a restart.")),
                Item(icon: "square.stack.3d.up",
                     title: String(localized: "A deck per book in Anki"),
                     detail: String(localized: "Export each book into its own deck under RELL.")),
            ]),
            WhatsNew(version: "1.44", items: [
                Item(icon: "text.badge.plus",
                     title: String(localized: "Every saved word gets a full card"),
                     detail: String(localized: "Fill Missing adds meanings, definitions and pronunciation from Apple's dictionary and the on-device model.")),
                Item(icon: "rectangle.stack",
                     title: String(localized: "A study room of its own"),
                     detail: String(localized: "Study in a large or full-screen window: choose how many words, see when each comes back, end with a summary.")),
                Item(icon: "shuffle",
                     title: String(localized: "Exercises that follow the word"),
                     detail: String(localized: "New words are introduced first; By Stage picks recognising, typing or listening for each card.")),
                Item(icon: "exclamationmark.arrow.circlepath",
                     title: String(localized: "Help with the words you keep forgetting"),
                     detail: String(localized: "They're marked, get a memory hook and can be studied on their own.")),
                Item(icon: "books.vertical",
                     title: String(localized: "Bring your Kindle words"),
                     detail: String(localized: "Import what you looked up on your Kindle, with the sentences and books.")),
            ]),
            WhatsNew(version: "1.43", items: [
                Item(icon: "text.cursor",
                     title: String(localized: "The selection bar says what it does"),
                     detail: String(localized: "Save and Analyze are labelled; Simplify, Retell and Highlight are in Tools.")),
                Item(icon: "book.pages",
                     title: String(localized: "One \"This chapter\" button above the page"),
                     detail: String(localized: "What you know, the warm-up words and your reviews, together.")),
                Item(icon: "sidebar.right",
                     title: String(localized: "The Inspector shows the word first"),
                     detail: String(localized: "Save and listen on the word's card; a sentence gets its own tools.")),
                Item(icon: "house",
                     title: String(localized: "Tools on the home screen"),
                     detail: String(localized: "Import an article, write a story or open Review in one click.")),
                Item(icon: "circle.lefthalf.filled",
                     title: String(localized: "Easy to read on every page theme"),
                     detail: String(localized: "Bars over the text match the page instead of showing it through.")),
            ]),
        ]
    }

    /// "1.43.2" → "1.43".
    static func minorVersion(of version: String) -> String {
        version.split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// The page for this app version, if one was written.
    static func page(forAppVersion version: String) -> WhatsNew? {
        let minor = minorVersion(of: version)
        return releases.first { $0.version == minor }
    }

    /// Show once per version, to people updating — a first launch gets the
    /// onboarding instead.
    static func shouldShow(appVersion: String, lastSeen: String?, hasCompletedOnboarding: Bool) -> Bool {
        guard hasCompletedOnboarding, let page = page(forAppVersion: appVersion) else { return false }
        return lastSeen != page.version
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
