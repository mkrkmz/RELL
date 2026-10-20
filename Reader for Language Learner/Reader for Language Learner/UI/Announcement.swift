//
//  Announcement.swift
//  Reader for Language Learner
//
//  What VoiceOver says when something changes on screen without moving the
//  focus (Roadmap v19 Sprint 5): a new card, an answer checked.
//

import SwiftUI

enum Announcement {
    static func post(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
