//
//  HoverDefinitionPopover.swift
//  Reader for Language Learner
//
//  Content for the hover dictionary NSPopover. Driven by HoverLookupModel,
//  which the PDF coordinator updates as a definition resolves.
//

import SwiftUI

@MainActor
@Observable
final class HoverLookupModel {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    enum Phase: Equatable {
        case loading
        case loaded(String)
        case failed
    }

    var term: String = ""
    var phase: Phase = .loading
    /// Where the answer came from (v18 S4), shown under it.
    var source: HoverSource?
    /// The word is in your notebook (in any form of it).
    var isSaved = false

    /// A new word: its saved state, and the cached answer if there is one.
    /// False when it still has to be looked up.
    func begin(term: String, isSaved: Bool, cached: HoverAnswer?) -> Bool {
        self.term = term
        self.isSaved = isSaved
        if let cached {
            show(cached)
            return true
        }
        phase = .loading
        source = nil
        return false
    }

    func show(_ answer: HoverAnswer) {
        phase = .loaded(answer.text)
        source = answer.source
    }

    func fail() {
        phase = .failed
        source = nil
    }
}

/// The hover balloon (v18 S4, approved mockup): the word, a short answer of
/// at most four lines, and where it came from — on the page's own surface.
struct HoverDefinitionPopover: View {
    let model: HoverLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Text(model.term)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                if model.isSaved {
                    Text("saved")
                        .font(DS.Typography.caption2.weight(.semibold))
                        .foregroundStyle(DS.Color.success)
                        .padding(.horizontal, DS.Spacing.xs)
                        .background(DS.Color.success.opacity(0.14), in: Capsule())
                }
            }

            content

            if let source = model.source {
                Text(source.label)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(DS.Spacing.md)
        .frame(width: 264, alignment: .leading)
        // Shown over the text: opaque and page-themed, not glass (v14 S1).
        .dsReadingOverlayFill()
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: DS.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Looking up…")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        case .loaded(let definition):
            Text(definition)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textSecondary)
                .lineSpacing(3)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        case .failed:
            Text("No definition found. Select the word to ask in the Inspector.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
