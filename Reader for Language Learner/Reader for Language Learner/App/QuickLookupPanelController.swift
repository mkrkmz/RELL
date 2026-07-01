//
//  QuickLookupPanelController.swift
//  Reader for Language Learner
//
//  Owns the Spotlight-style HUD panel for quick lookups. A non-activating
//  NSPanel keeps the frontmost app active while still taking keyboard input;
//  it hides on Esc and when it loses key status.
//

import AppKit
import SwiftUI

/// Borderless panels refuse key status by default — accept it so the
/// search field can take typing without activating the app.
private final class KeyableHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

@MainActor
final class QuickLookupPanelController: NSObject, NSWindowDelegate {
    static let shared = QuickLookupPanelController()

    private var panel: KeyableHUDPanel?

    private override init() {
        super.init()
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Setup

    private func ensurePanel() -> KeyableHUDPanel {
        if let panel { return panel }

        let panel = KeyableHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let host = NSHostingView(
            rootView: QuickLookupPanelView(
                style: .hud,
                onDismiss: { [weak self] in
                    Task { @MainActor in self?.hide() }
                },
                onSizeChange: { [weak self] size in
                    Task { @MainActor in self?.resizeToFit(size) }
                }
            )
        )
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        self.panel = panel
        return panel
    }

    /// Grows/shrinks the panel with its SwiftUI content, keeping the top
    /// edge anchored so results expand downward like Spotlight.
    private func resizeToFit(_ size: CGSize) {
        guard let panel, panel.frame.size != size else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    /// Spotlight placement: horizontally centered, upper third of the screen
    /// the mouse is on.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        panel.layoutIfNeeded()
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + frame.height * 0.68 - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            self.hide()
        }
    }
}
