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

    var onContextSaveWord:  (() -> Void)?
    var onContextAddNote:   (() -> Void)?
    var onContextHighlight: ((HighlightColor) -> Void)?
    var onContextLookUp:    (() -> Void)?
    var onContextAnalyze:   ((ModuleType) -> Void)?
    var onContextCopy:      (() -> Void)?
    var onContextSpeak:     (() -> Void)?

    /// Reports the cursor location (in view coordinates) while hovering with
    /// no mouse button down, plus exit events, for the hover dictionary.
    var onHoverMove: ((NSPoint) -> Void)?
    var onHoverExit: (() -> Void)?

    private var hoverTrackingArea: NSTrackingArea?

    // MARK: - Hover Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onHoverMove?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverExit?()
    }

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
            title:         String(localized: "Save \(preview)"),
            action:        #selector(fireSaveWord),
            keyEquivalent: ""
        )
        saveItem.target    = self
        saveItem.isEnabled = true
        menu.addItem(saveItem)

        let noteItem = NSMenuItem(
            title:         String(localized: "Add Note"),
            action:        #selector(fireAddNote),
            keyEquivalent: ""
        )
        noteItem.target    = self
        noteItem.isEnabled = true
        menu.addItem(noteItem)

        // ── Highlight (color submenu) ──────────────────────────────────
        let highlightItem = NSMenuItem(title: String(localized: "Highlight"), action: nil, keyEquivalent: "")
        let highlightSubmenu = NSMenu()
        highlightSubmenu.autoenablesItems = false
        for color in HighlightColor.allCases {
            let item = NSMenuItem(
                title:         color.label,
                action:        #selector(fireHighlight(_:)),
                keyEquivalent: ""
            )
            item.target           = self
            item.isEnabled        = true
            item.representedObject = color.rawValue
            item.image            = Self.swatchImage(for: color.nsColor)
            highlightSubmenu.addItem(item)
        }
        highlightItem.submenu = highlightSubmenu
        menu.addItem(highlightItem)

        // ── Look Up ────────────────────────────────────────────────────
        let lookUpItem = NSMenuItem(
            title:         String(localized: "Look Up in Inspector"),
            action:        #selector(fireLookUp),
            keyEquivalent: ""
        )
        lookUpItem.target    = self
        lookUpItem.isEnabled = true
        menu.addItem(lookUpItem)

        // ── Analyze With (module submenu) ──────────────────────────────
        let analyzeItem = NSMenuItem(title: String(localized: "Analyze With"), action: nil, keyEquivalent: "")
        let analyzeSubmenu = NSMenu()
        analyzeSubmenu.autoenablesItems = false
        for module in ModuleType.menuOrder {
            let item = NSMenuItem(
                title:         module.title,
                action:        #selector(fireAnalyze(_:)),
                keyEquivalent: ""
            )
            item.target            = self
            item.isEnabled         = true
            item.representedObject = module.rawValue
            item.image             = NSImage(
                systemSymbolName: module.iconName,
                accessibilityDescription: module.title
            )
            analyzeSubmenu.addItem(item)
        }
        analyzeItem.submenu = analyzeSubmenu
        menu.addItem(analyzeItem)

        menu.addItem(.separator())

        // ── Copy ───────────────────────────────────────────────────────
        let copyItem = NSMenuItem(
            title:         String(localized: "Copy"),
            action:        #selector(fireCopy),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = .command
        copyItem.target    = self
        copyItem.isEnabled = true
        menu.addItem(copyItem)

        // ── Speak ──────────────────────────────────────────────────────
        let speakItem = NSMenuItem(
            title:         String(localized: "Speak"),
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
    @objc private func fireAddNote()  { onContextAddNote?()  }
    @objc private func fireLookUp()   { onContextLookUp?()   }
    @objc private func fireCopy()     { onContextCopy?()     }
    @objc private func fireSpeak()    { onContextSpeak?()    }

    @objc private func fireHighlight(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let color = HighlightColor(rawValue: raw) else { return }
        onContextHighlight?(color)
    }

    @objc private func fireAnalyze(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let module = ModuleType(rawValue: raw) else { return }
        onContextAnalyze?(module)
    }

    /// Small filled-circle swatch for the color submenu items.
    private static func swatchImage(for color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
