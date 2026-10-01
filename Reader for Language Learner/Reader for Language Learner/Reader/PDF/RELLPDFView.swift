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

        // Same lines, same order as the EPUB reader and the selection bar.
        let menu = NSMenu()
        menu.autoenablesItems = false
        let actions = SelectionMenu.Actions(
            save: { [weak self] in self?.onContextSaveWord?() },
            analyze: { [weak self] in self?.onContextLookUp?() },
            analyzeWith: { [weak self] module in self?.onContextAnalyze?(module) },
            highlight: { [weak self] color in self?.onContextHighlight?(color) },
            speak: { [weak self] in self?.onContextSpeak?() },
            addNote: { [weak self] in self?.onContextAddNote?() },
            copy: { [weak self] in self?.onContextCopy?() }
        )
        for item in SelectionMenu.items(for: raw, actions: actions) { menu.addItem(item) }
        return menu
    }
}
