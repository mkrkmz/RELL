//
//  InterfaceLanguage.swift
//  Reader for Language Learner
//
//  The language RELL's own interface is in (Roadmap v19 Sprint 5, approved
//  mockup) — separate from the language learned and the native language.
//  "System" follows macOS; a choice is RELL's own `AppleLanguages`, read at
//  launch, so it applies once RELL opens again. Spanish and German are
//  marked beta until a native speaker has reviewed them.
//

import AppKit

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case turkish = "tr"
    case spanish = "es"
    case german = "de"

    var id: String { rawValue }

    /// Each language in its own name; "System" in the current one.
    var title: String {
        switch self {
        case .system:  return String(localized: "System")
        case .english: return "English"
        case .turkish: return "Türkçe"
        case .spanish: return "Español"
        case .german:  return "Deutsch"
        }
    }

    /// Translated by RELL's maintainer, not yet reviewed by a native speaker.
    var isBeta: Bool { self == .spanish || self == .german }

    /// RELL's own setting, not the system-wide list it falls back to.
    static func stored(_ defaults: UserDefaults = .standard) -> InterfaceLanguage {
        guard let domain = Bundle.main.bundleIdentifier,
              let list = defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String],
              let first = list.first
        else { return .system }
        return allCases.first { $0 != .system && first.hasPrefix($0.rawValue) } ?? .system
    }

    func store(_ defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }

    /// The language the interface is in right now.
    static var running: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Opens a fresh RELL and quits this one.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Help ▸ Fix a Translation…: a GitHub issue from a template — the
    /// interface language and blanks to fill in, nothing about the user.
    static var fixTranslationURL: URL {
        var components = URLComponents(string: "https://github.com/mkrkmz/RELL/issues/new")!
        let body = """
        Language: \(running)
        Where (window, button or menu):
        Text now:
        Better text:
        """
        components.queryItems = [
            URLQueryItem(name: "title", value: "Translation (\(running)): "),
            URLQueryItem(name: "labels", value: "translation"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url!
    }
}
