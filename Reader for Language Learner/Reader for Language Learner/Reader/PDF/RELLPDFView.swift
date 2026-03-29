//
//  RELLPDFView.swift
//  Reader for Language Learner
//
//  PDFView subclass that provides a context-sensitive right-click menu
//  for selected text: Save Word · Look Up · Copy · Speak.
//

import AppKit
import PDFKit

final class RELLPDFView: PDFView {

    // MARK: - Callbacks (set by Coordinator)

    var onContextSaveWord: (() -> Void)?
    var onContextLookUp:   (() -> Void)?
    var onContextCopy:     (() -> Void)?
    var onContextSpeak:    (() -> Void)?

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let raw = currentSelection?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Fall back to default menu when nothing is selected
        guard !raw.isEmpty else { return super.menu(for: event) }

        let preview = raw.count > 40 ? String(raw.prefix(40)) + "…" : raw
        let menu    = NSMenu()
        menu.autoenablesItems = false

        // ── Save Word ──────────────────────────────────────────────────
        let saveItem = NSMenuItem(
            title:         "Save \(preview)",
            action:        #selector(fireSaveWord),
            keyEquivalent: ""
        )
        saveItem.target    = self
        saveItem.isEnabled = true
        menu.addItem(saveItem)

        // ── Look Up ────────────────────────────────────────────────────
        let lookUpItem = NSMenuItem(
            title:         "Look Up in Inspector",
            action:        #selector(fireLookUp),
            keyEquivalent: ""
        )
        lookUpItem.target    = self
        lookUpItem.isEnabled = true
        menu.addItem(lookUpItem)

        menu.addItem(.separator())

        // ── Copy ───────────────────────────────────────────────────────
        let copyItem = NSMenuItem(
            title:         "Copy",
            action:        #selector(fireCopy),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = .command
        copyItem.target    = self
        copyItem.isEnabled = true
        menu.addItem(copyItem)

        // ── Speak ──────────────────────────────────────────────────────
        let speakItem = NSMenuItem(
            title:         "Speak",
            action:        #selector(fireSpeak),
            keyEquivalent: ""
        )
        speakItem.target    = self
        speakItem.isEnabled = true
        menu.addItem(speakItem)

        return menu
    }

    // MARK: - Action Targets

    @objc private func fireSaveWord() { onContextSaveWord?() }
    @objc private func fireLookUp()   { onContextLookUp?()   }
    @objc private func fireCopy()     { onContextCopy?()     }
    @objc private func fireSpeak()    { onContextSpeak?()    }
}
