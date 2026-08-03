//
//  UndoableStore.swift
//  Reader for Language Learner
//
//  Shared undo/redo plumbing for the annotation stores (highlights, notes,
//  bookmarks). A store adopts `UndoableStore`, holds an `UndoManager` handed
//  down from the focused window, and registers an inverse operation on each
//  mutation. Because every inverse is itself a mutation that registers ITS
//  inverse, a single registration gives both undo and redo.
//

import Foundation

@MainActor
protocol UndoableStore: AnyObject {
    /// The window's undo manager, injected from the SwiftUI environment. Undo
    /// registration is a no-op while nil (e.g. a store used outside any window,
    /// or in a unit test that hasn't provided one).
    var undoManager: UndoManager? { get }
}

extension UndoableStore {
    /// Registers `inverse` as the undo of the mutation just performed and
    /// labels the action for the Edit menu. `inverse` runs on the main actor
    /// when the user chooses Undo/Redo.
    func registerUndo(_ actionName: String, _ inverse: @escaping @MainActor (Self) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { inverse(target) }
        }
        undoManager.setActionName(actionName)
    }
}
