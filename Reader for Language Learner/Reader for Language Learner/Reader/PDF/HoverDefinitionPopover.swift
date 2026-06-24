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
    enum Phase: Equatable {
        case loading
        case loaded(String)
        case failed
    }

    var term: String = ""
    var phase: Phase = .loading
}

struct HoverDefinitionPopover: View {
    let model: HoverLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(model.term)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)

            content
        }
        .padding(DS.Spacing.md)
        .frame(width: 264, alignment: .leading)
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
                .fixedSize(horizontal: false, vertical: true)
        case .failed:
            Text("Couldn't load a definition. Check your AI server.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
        }
    }
}
