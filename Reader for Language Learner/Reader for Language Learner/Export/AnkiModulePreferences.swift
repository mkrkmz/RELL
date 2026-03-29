//
//  AnkiModulePreferences.swift
//  Reader for Language Learner
//
//  Single source of truth for Anki export toggles, tags, and source preference.
//  Injected via @Environment so all three export sites share the same object.
//

import Foundation
import SwiftUI

@Observable final class AnkiModulePreferences {

    // MARK: - Persisted preferences

    var tags: String {
        didSet { UserDefaults.standard.set(tags, forKey: "ankiTags") }
    }

    var includeSource: Bool {
        didSet { UserDefaults.standard.set(includeSource, forKey: "ankiIncludeSource") }
    }

    /// Per-module toggles keyed by ModuleType.rawValue.
    /// Mutations go through setIncluded(_:_:) which also persists to UserDefaults.
    private(set) var moduleToggles: [String: Bool]

    // MARK: - Init

    init() {
        self.tags = UserDefaults.standard.string(forKey: "ankiTags") ?? "rell"
        self.includeSource = UserDefaults.standard.object(forKey: "ankiIncludeSource") as? Bool ?? true

        var toggles: [String: Bool] = [:]
        for module in ModuleType.allCases {
            let stored = UserDefaults.standard.object(forKey: "ankiModules_\(module.rawValue)") as? Bool
            toggles[module.rawValue] = stored ?? true
        }
        self.moduleToggles = toggles
    }

    // MARK: - Accessors

    func isIncluded(_ module: ModuleType) -> Bool {
        moduleToggles[module.rawValue] ?? true
    }

    func setIncluded(_ module: ModuleType, _ value: Bool) {
        moduleToggles[module.rawValue] = value
        UserDefaults.standard.set(value, forKey: "ankiModules_\(module.rawValue)")
    }

    /// SwiftUI Binding for use in Toggle / ForEach module rows.
    func binding(for module: ModuleType) -> Binding<Bool> {
        Binding(
            get: { self.isIncluded(module) },
            set: { self.setIncluded(module, $0) }
        )
    }

    // MARK: - Helpers

    /// Modules that are toggled on AND have non-empty output — used by quick-export.
    func selectedModules(from outputs: [ModuleType: String]) -> Set<ModuleType> {
        ModuleType.allCases.filter { module in
            isIncluded(module) &&
            !(outputs[module] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.reduce(into: Set()) { $0.insert($1) }
    }
}
