//
//  SelectionState.swift
//  Reader for Language Learner
//

import Foundation

@MainActor
@Observable
final class SelectionState {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    var documentURL: URL?
    var selectedText: String = ""
    var contextSentence: String?
}
