//
//  SelectionState.swift
//  Reader for Language Learner
//

import Foundation

@MainActor
@Observable
final class SelectionState {
    var documentURL: URL?
    var selectedText: String = ""
    var contextSentence: String?
}
