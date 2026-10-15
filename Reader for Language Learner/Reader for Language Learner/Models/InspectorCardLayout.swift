//
//  InspectorCardLayout.swift
//  Reader for Language Learner
//
//  What the Inspector's card shows (Roadmap v18 Sprint 2, approved mockup —
//  the user's idea): the modules sit in the card as quiet buttons next to
//  Save · Listen · Anki, and the reader chooses which are on the card and
//  which wait in its ••• menu. A word card and a sentence card each keep
//  their own list. What doesn't fit the column's width moves to ••• on its
//  own, so a row never wraps. Items are named by a string id, so modules
//  the reader writes themselves (S3) slot in beside the built-in ones.
//  Pure, except for reading and writing the lists in UserDefaults.
//

import Foundation

nonisolated enum CardKind: String, CaseIterable, Sendable {
    case word
    case sentence
}

enum CardItem: Hashable {
    case listen
    case anki
    case copy
    case grammar
    case simplify
    case retell
    case module(ModuleType)

    /// Stable id for storage: "listen", "module.definitionEN"…
    var id: String {
        switch self {
        case .listen:   return "listen"
        case .anki:     return "anki"
        case .copy:     return "copy"
        case .grammar:  return "grammar"
        case .simplify: return "simplify"
        case .retell:   return "retell"
        case .module(let module): return "module.\(module.rawValue)"
        }
    }

    init?(id: String) {
        switch id {
        case "listen":   self = .listen
        case "anki":     self = .anki
        case "copy":     self = .copy
        case "grammar":  self = .grammar
        case "simplify": self = .simplify
        case "retell":   self = .retell
        default:
            guard id.hasPrefix("module."),
                  let module = ModuleType(rawValue: String(id.dropFirst("module.".count))) else { return nil }
            self = .module(module)
        }
    }

    /// The upper row holds what you do with the selection; the lower row
    /// what you learn about it.
    var isAction: Bool {
        switch self {
        case .listen, .anki, .copy: return true
        case .grammar, .simplify, .retell, .module: return false
        }
    }

    var module: ModuleType? {
        if case .module(let module) = self { return module }
        return nil
    }
}

enum InspectorCardLayout {

    /// Everything a card can show, in the order of the ••• menu.
    static func available(_ kind: CardKind) -> [CardItem] {
        switch kind {
        case .word:
            return [.listen, .anki] + ModuleType.menuOrder.filter { $0.isEnabled(mode: .word) }.map(CardItem.module)
        case .sentence:
            return [.listen, .copy]
                + ModuleType.menuOrder.filter { $0.isEnabled(mode: .sentence) }.map(CardItem.module)
                + [.grammar, .simplify, .retell]
        }
    }

    /// On the card until the reader changes it (approved mockup).
    static func defaults(_ kind: CardKind) -> [CardItem] {
        switch kind {
        case .word:
            return [.listen, .anki] + [ModuleType.definitionEN, .meaningTR, .collocations, .examplesEN].map(CardItem.module)
        case .sentence:
            return [.listen, .copy, .module(.definitionEN), .module(.meaningTR), .grammar, .simplify, .retell]
        }
    }

    // MARK: Lists

    /// The stored list, without ids that no longer exist or don't belong to
    /// this card; the defaults when nothing is stored.
    static func pinned(_ kind: CardKind, stored: [String]?) -> [CardItem] {
        guard let stored else { return defaults(kind) }
        let allowed = Set(available(kind))
        var seen = Set<CardItem>()
        return stored.compactMap(CardItem.init(id:)).filter { allowed.contains($0) && seen.insert($0).inserted }
    }

    /// What isn't on the card, in menu order.
    static func unpinned(_ kind: CardKind, pinned: [CardItem]) -> [CardItem] {
        available(kind).filter { !pinned.contains($0) }
    }

    static func pin(_ item: CardItem, in pinned: [CardItem]) -> [CardItem] {
        pinned.contains(item) ? pinned : pinned + [item]
    }

    static func unpin(_ item: CardItem, in pinned: [CardItem]) -> [CardItem] {
        pinned.filter { $0 != item }
    }

    /// One place left (-1) or right (+1) among the items of its own row.
    static func move(_ item: CardItem, by step: Int, in pinned: [CardItem]) -> [CardItem] {
        let row = pinned.filter { $0.isAction == item.isAction }
        guard let index = row.firstIndex(of: item) else { return pinned }
        let target = index + step
        guard row.indices.contains(target) else { return pinned }
        var reordered = row
        reordered.swapAt(index, target)
        var iterator = reordered.makeIterator()
        return pinned.map { $0.isAction == item.isAction ? iterator.next()! : $0 }
    }

    // MARK: Fitting the width

    /// How many of `widths`, in order, fit in `available` with `spacing`
    /// between them — the rest move to •••.
    static func fittingCount(widths: [Double], available: Double, spacing: Double) -> Int {
        var used = 0.0
        for (index, width) in widths.enumerated() {
            let next = used + (index > 0 ? spacing : 0) + width
            if next > available { return index }
            used = next
        }
        return widths.count
    }

    // MARK: Storage

    static func storageKey(_ kind: CardKind) -> String {
        kind == .word ? StorageKey.inspectorWordCard : StorageKey.inspectorSentenceCard
    }

    static func load(_ kind: CardKind, defaults: UserDefaults = .standard) -> [CardItem] {
        pinned(kind, stored: defaults.stringArray(forKey: storageKey(kind)))
    }

    static func save(_ pinned: [CardItem], for kind: CardKind, defaults: UserDefaults = .standard) {
        defaults.set(pinned.map(\.id), forKey: storageKey(kind))
        NotificationCenter.default.post(name: .inspectorCardChanged, object: nil)
    }

    static func reset(_ kind: CardKind, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey(kind))
        NotificationCenter.default.post(name: .inspectorCardChanged, object: nil)
    }
}

extension Notification.Name {
    /// The card's list changed (editor, right-click, 📌) — every open
    /// Inspector redraws its card.
    nonisolated static let inspectorCardChanged = Notification.Name("inspectorCardChanged")
}
