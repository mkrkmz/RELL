//
//  SentenceTranslationStrip.swift
//  Reader for Language Learner
//
//  Thin bar below the PDF showing a native-language translation of the
//  currently selected sentence. Loads via QuickLookupService (cache-first).
//

import SwiftUI

struct SentenceTranslationStrip: View {
    let sentence: String
    var service: QuickLookupService
    let onClose: () -> Void

    @State private var phase: Phase = .loading

    enum Phase: Equatable {
        case loading
        case loaded(String)
        case failed
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "character.bubble")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Color.accent)
                .padding(.top, 1)

            content

            Spacer(minLength: DS.Spacing.sm)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Hide translation")
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Color.separator.opacity(0.3), lineWidth: 0.6)
        )
        .task(id: sentence) { await load() }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: DS.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Translating…")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        case .loaded(let translation):
            Text(translation)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .failed:
            Text("Couldn't translate — check your AI server.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
        }
    }

    private func load() async {
        if let cached = service.cachedTranslation(for: sentence) {
            phase = .loaded(cached)
            return
        }
        phase = .loading
        do {
            let translation = try await service.translate(sentence: sentence)
            phase = .loaded(translation)
        } catch {
            phase = .failed
        }
    }
}
