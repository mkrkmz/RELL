//
//  RELLIntents.swift
//  Reader for Language Learner
//
//  App Intents: RELL actions exposed to Shortcuts and Spotlight.
//  These run inside the app process — SavedWordsStore arrives through
//  AppIntents dependency injection (registered in the App initializer).
//

import AppIntents
import Foundation

// MARK: - Add Word

struct AddWordIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Word to RELL"
    static let description = IntentDescription(
        "Saves a word to your RELL vocabulary for later review."
    )

    @Parameter(title: "Word") var term: String

    @Dependency private var savedWordsStore: SavedWordsStore

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$term) to RELL")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw $term.needsValueError()
        }
        savedWordsStore.add(SavedWord(
            term: trimmed,
            sentence: "",
            pdfFilename: nil,
            pageNumber: nil,
            mode: "word",
            domain: "general",
            llmOutputs: [:],
            language: Language.storedTarget.rawValue
        ))
        return .result(dialog: "Saved “\(trimmed)” to your vocabulary.")
    }
}

// MARK: - Start Review

struct StartReviewIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Vocabulary Review"
    static let description = IntentDescription(
        "Opens the RELL review window to study due words."
    )
    /// The review window needs the app frontmost.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .openReviewWindowCommand, object: nil)
        return .result()
    }
}

// MARK: - Look Up

struct LookUpWordIntent: AppIntent {
    static let title: LocalizedStringResource = "Look Up in RELL"
    static let description = IntentDescription(
        "Opens the Quick Lookup panel with a word and fetches its definition."
    )

    @Parameter(title: "Word") var term: String

    static var parameterSummary: some ParameterSummary {
        Summary("Look up \(\.$term) in RELL")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw $term.needsValueError()
        }
        QuickLookupPanelController.shared.show(lookingUp: trimmed)
        return .result()
    }
}

// MARK: - Shortcuts Provider

struct RELLShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddWordIntent(),
            phrases: ["Add a word to \(.applicationName)"],
            shortTitle: "Add Word",
            systemImageName: "star"
        )
        AppShortcut(
            intent: StartReviewIntent(),
            phrases: ["Start review in \(.applicationName)"],
            shortTitle: "Review",
            systemImageName: "rectangle.on.rectangle.angled"
        )
        AppShortcut(
            intent: LookUpWordIntent(),
            phrases: ["Look up a word in \(.applicationName)"],
            shortTitle: "Look Up",
            systemImageName: "character.book.closed"
        )
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted by StartReviewIntent; any ContentView opens the review window.
    static let openReviewWindowCommand = Notification.Name("openReviewWindowCommand")
}
