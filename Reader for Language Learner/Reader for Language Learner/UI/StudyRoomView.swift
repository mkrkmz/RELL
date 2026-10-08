//
//  StudyRoomView.swift
//  Reader for Language Learner
//
//  The study room window (Roadmap v15 Sprint 2, approved decision 2): word
//  study in its own large window that goes full screen, in place of the
//  small "Vocabulary Review" window (same window id, so every way in still
//  works). It remembers full screen: leave it in full screen and it opens
//  that way next time.
//

import AppKit
import SwiftUI

struct StudyRoomView: View {
    var store: SavedWordsStore
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        QuizView(store: store, style: .room, onClose: { dismissWindow(id: StudyRoom.windowID) })
            .background(DS.Color.surface)
            .background(StudyRoomWindowConfigurator())
    }
}

enum StudyRoom {
    static let windowID = "review"

    /// Opens the room in full screen — the sidebar's "Study Full Screen".
    @MainActor
    static func openFullScreen(using openWindow: OpenWindowAction) {
        UserDefaults.standard.set(true, forKey: StorageKey.studyRoomFullScreen)
        openWindow(id: windowID)
        // Already open: the window takes the request itself.
        NotificationCenter.default.post(name: .studyRoomFullScreenRequest, object: nil)
    }
}

extension Notification.Name {
    nonisolated static let studyRoomFullScreenRequest = Notification.Name("studyRoomFullScreenRequest")
}

/// Finds the room's NSWindow: lets it go full screen, records whether it is,
/// and enters full screen when asked or when it was left that way.
private struct StudyRoomWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowProbe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class WindowProbe: NSView {
        private var observers: [NSObjectProtocol] = []
        private var isClosing = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Leaving the window (it closed) drops the observers.
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            window.collectionBehavior.insert(.fullScreenPrimary)
            isClosing = false

            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.record(true) }
            })
            observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.record(false) }
            })
            // Closing a full-screen window leaves full screen on the way out;
            // that exit isn't a choice to remember.
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isClosing = true }
            })
            observers.append(center.addObserver(forName: .studyRoomFullScreenRequest, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterFullScreen() }
            })
            if UserDefaults.standard.bool(forKey: StorageKey.studyRoomFullScreen) {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.enterFullScreen() }
                }
            }
        }

        private func record(_ fullScreen: Bool) {
            guard !isClosing else { return }
            UserDefaults.standard.set(fullScreen, forKey: StorageKey.studyRoomFullScreen)
        }

        private func enterFullScreen() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
        }
    }
}
