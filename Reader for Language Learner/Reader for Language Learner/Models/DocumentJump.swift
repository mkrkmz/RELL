//
//  DocumentJump.swift
//  Reader for Language Learner
//
//  Opening a document at a given page or chapter from outside its window —
//  the word page's "where you met it" list (Roadmap v13 Sprint 1).
//
//  Two cases, handled together: the document's window may not exist yet, or
//  it may already be open. The target is written as the document's reading
//  position first, so a window that opens now restores straight to it; and a
//  notification tells an already-open window to go there itself.
//

import Foundation

struct DocumentLocation: Equatable {
    let url: URL
    /// 0-based PDF page or EPUB chapter.
    let location: Int
    let isEPUB: Bool
}

extension Notification.Name {
    /// Object: `DocumentLocation`. The window showing that document goes there.
    static let revealDocumentLocation = Notification.Name("revealDocumentLocation")
}

enum DocumentJump {

    /// Call before `openWindow(value: location.url)`.
    static func prepare(_ location: DocumentLocation, defaults: UserDefaults = .standard) {
        if location.isEPUB {
            EPUBViewManager.setStartPosition(chapter: location.location, for: location.url)
        } else {
            ReaderWindowModel.persistPage(
                location.location,
                for: location.url.deletingPathExtension().lastPathComponent,
                defaults: defaults
            )
        }
    }

    /// Call after `openWindow(value:)`: an open window moves; a window that
    /// is still being created ignores this and restores from `prepare`.
    static func announce(_ location: DocumentLocation) {
        NotificationCenter.default.post(name: .revealDocumentLocation, object: location)
    }

    static func isAvailable(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
