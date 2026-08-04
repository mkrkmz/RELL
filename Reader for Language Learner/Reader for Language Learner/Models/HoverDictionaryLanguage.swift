//
//  HoverDictionaryLanguage.swift
//  Reader for Language Learner
//
//  Which language the hover dictionary answers in.
//
//  Learners split on this: some want the definition in the language they're
//  studying (staying immersed, learning to think in it), others want the
//  meaning in their own language (faster, less friction mid-page). Both
//  answers were already available — the explanation module answers in the
//  target language, the meaning module in the native one — so this preference
//  just picks which one the hover popover asks for.
//

import Foundation

enum HoverDictionaryLanguage: String, CaseIterable, Identifiable {
    /// Definition written in the language being studied (immersive).
    case target
    /// Meaning in the reader's own language (fastest to grasp).
    case native

    var id: String { rawValue }

    static let storageKey = "hoverDictionaryLanguage"
    static let `default`: HoverDictionaryLanguage = .target

    static var stored: HoverDictionaryLanguage {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(HoverDictionaryLanguage.init(rawValue:)) ?? .default
    }

    /// Menu title, naming the actual language so the choice is concrete —
    /// "English (studying)" / "Türkçe (native)" rather than abstract labels.
    func localizedTitle(target: Language, native: Language) -> String {
        switch self {
        case .target: return String(localized: "\(target.nativeName) — studying")
        case .native: return String(localized: "\(native.nativeName) — native")
        }
    }
}
