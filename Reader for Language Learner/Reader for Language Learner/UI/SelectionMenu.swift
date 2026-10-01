//
//  SelectionMenu.swift
//  Reader for Language Learner
//
//  The actions a text selection offers, in one order shared by the
//  selection bar's Tools menu and both readers' right-click menus (v14 S1).
//  Before, the PDF and EPUB menus listed different items in different
//  orders and the bar had its own set; now the list is built here once.
//

import AppKit

enum SelectionMenu {
    /// One line of the right-click menu.
    enum Entry: Equatable {
        case save, analyze, analyzeWith
        case simplify, retell
        case highlight, addNote, speak, copy
        case separator
    }

    /// The right-click menu's lines. `addNote` exists only in the PDF
    /// reader; the EPUB menu leaves Copy to WebKit's own items below.
    static func entries(includesNote: Bool, includesCopy: Bool) -> [Entry] {
        var entries: [Entry] = [.save, .analyze, .analyzeWith, .separator, .simplify, .retell, .separator, .highlight]
        if includesNote { entries.append(.addNote) }
        entries.append(.speak)
        if includesCopy { entries += [.separator, .copy] }
        return entries
    }

    /// What each line does. Optional actions drop their line.
    struct Actions {
        var save: () -> Void
        var analyze: () -> Void
        var analyzeWith: (ModuleType) -> Void
        var highlight: (HighlightColor) -> Void
        var speak: () -> Void
        var addNote: (() -> Void)? = nil
        var copy: (() -> Void)? = nil
    }

    /// Simplify and Retell work on a passage; for a word they show, disabled,
    /// with the reason underneath.
    static var passageOnlyReason: String {
        String(localized: "Select a sentence or paragraph")
    }

    /// The right-click menu items for `selection`.
    static func items(for selection: String, actions: Actions) -> [NSMenuItem] {
        let preview = selection.count > 40 ? String(selection.prefix(40)) + "…" : selection
        let isPassage = GradedRewrite.isEligible(selection)

        return entries(includesNote: actions.addNote != nil, includesCopy: actions.copy != nil).map { entry in
            switch entry {
            case .save:
                return ClosureMenuItem.make(String(localized: "Save \(preview)"), actions.save)
            case .analyze:
                return ClosureMenuItem.make(String(localized: "Analyze"), actions.analyze)
            case .analyzeWith:
                let item = NSMenuItem(title: String(localized: "Analyze With"), action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for module in ModuleType.menuOrder {
                    let moduleItem = ClosureMenuItem.make(module.title) { actions.analyzeWith(module) }
                    moduleItem.image = NSImage(systemSymbolName: module.iconName, accessibilityDescription: module.title)
                    submenu.addItem(moduleItem)
                }
                item.submenu = submenu
                return item
            case .simplify:
                return passageItem(String(localized: "Simplify"), enabled: isPassage) {
                    NotificationCenter.default.post(name: .simplifySelectionCommand, object: selection)
                }
            case .retell:
                return passageItem(String(localized: "Retell"), enabled: isPassage) {
                    NotificationCenter.default.post(name: .retellSelectionCommand, object: selection)
                }
            case .highlight:
                let item = NSMenuItem(title: String(localized: "Highlight"), action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for color in HighlightColor.allCases {
                    let colorItem = ClosureMenuItem.make(color.label) { actions.highlight(color) }
                    colorItem.image = swatchImage(for: color.nsColor)
                    submenu.addItem(colorItem)
                }
                item.submenu = submenu
                return item
            case .addNote:
                return ClosureMenuItem.make(String(localized: "Add Note"), actions.addNote ?? {})
            case .speak:
                return ClosureMenuItem.make(String(localized: "Speak"), actions.speak)
            case .copy:
                let item = ClosureMenuItem.make(String(localized: "Copy"), actions.copy ?? {})
                item.keyEquivalent = "c"
                item.keyEquivalentModifierMask = .command
                return item
            case .separator:
                return .separator()
            }
        }
    }

    private static func passageItem(_ title: String, enabled: Bool, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem.make(title, enabled: enabled, handler)
        if !enabled { item.subtitle = passageOnlyReason }
        return item
    }

    /// Small filled-circle swatch for the highlight colors.
    static func swatchImage(for color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}

/// Builds menu items that run a closure — the menus are built per
/// right-click, so there is no long-lived target to hang selectors on.
/// The item keeps its `MenuAction` alive through `representedObject`
/// (`target` is weak).
enum ClosureMenuItem {
    static func make(_ title: String, enabled: Bool = true, _ handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler: handler, isEnabled: enabled)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        item.isEnabled = enabled
        return item
    }
}

final class MenuAction: NSObject, NSMenuItemValidation {
    private let handler: () -> Void
    /// Answers validation too, so a disabled item stays disabled in a menu
    /// that enables its items itself (WebKit's).
    private let isEnabled: Bool

    init(handler: @escaping () -> Void, isEnabled: Bool) {
        self.handler = handler
        self.isEnabled = isEnabled
    }

    @objc func fire() { handler() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { isEnabled }
}
