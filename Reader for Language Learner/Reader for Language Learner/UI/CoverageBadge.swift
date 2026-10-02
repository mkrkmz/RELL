//
//  CoverageBadge.swift
//  Reader for Language Learner
//
//  How much of a book's vocabulary the reader already knows, as a small
//  tinted capsule — on library covers, in the library list and in the
//  home screen's recent list (v14 S3).
//

import SwiftUI

struct CoverageBadge: View {
    let profile: LexicalProfile
    /// Filled (white text on the tint) over a cover; tinted text on a row.
    var filled = false

    var body: some View {
        let tint = DS.Color.coverageTint(for: profile.difficulty)
        Text("\(Int(profile.knownShare * 100))%")
            .font(DS.Typography.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(filled ? SwiftUI.Color.white : tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(filled ? tint.opacity(0.85) : tint.opacity(0.12), in: Capsule())
            .help(Text("You know \(Int(profile.knownShare * 100))% of this book's words"))
            .accessibilityLabel(Text("You know \(Int(profile.knownShare * 100))% of this book's words"))
    }
}
