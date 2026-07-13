//
//  ToastCenter.swift
//  Reader for Language Learner
//
//  Per-window toast dispatcher. Actions that complete without any visible
//  state change (context-menu Save Word, bookmark toggle, note-row saves)
//  report here; ContentView overlays a single DSToast driven by this state.
//  InspectorView keeps its own local toast — it overlays the inspector pane,
//  not the window.
//

import SwiftUI

@Observable
@MainActor
final class ToastCenter {
    var isPresented = false
    private(set) var message = ""
    private(set) var variant: DSToast.Variant = .success

    func show(_ message: String, variant: DSToast.Variant = .success) {
        self.message = message
        self.variant = variant
        isPresented = true
    }
}
