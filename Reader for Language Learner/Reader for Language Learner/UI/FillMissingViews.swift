//
//  FillMissingViews.swift
//  Reader for Language Learner
//
//  "Fill Missing" (Roadmap v15 Sprint 1): the strip above the word list and
//  the sheet that picks the fields, shows the run and sums it up. The work
//  is `WordEnricher`'s; closing the sheet leaves a run going, with its
//  progress in the strip.
//

import SwiftUI

// MARK: - Strip

/// Above the word list: how many words have no meaning, or how far a run
/// has got. Hidden when there's nothing to fill, and after you close it
/// until a new word adds to the count.
struct FillMissingStrip: View {
    var enricher: WordEnricher
    var onOpen: () -> Void

    @AppStorage(StorageKey.fillStripHiddenAtCount) private var hiddenAtCount = -1

    var body: some View {
        if let run = enricher.run, !run.isFinished {
            running(run)
        } else {
            let missing = enricher.missingCount(.meaning)
            if missing > 0 && missing > hiddenAtCount {
                idle(missing: missing)
            }
        }
    }

    private func idle(missing: Int) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(missing) words have no meaning")
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                Text("From the dictionary and the on-device model")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Button("Fill Missing", action: onOpen)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            Button("Hide", systemImage: "xmark") { hiddenAtCount = missing }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(DS.Typography.icon(9, weight: .semibold))
                .foregroundStyle(DS.Color.textTertiary)
                .help("Hide until more words are missing a meaning")
                .accessibilityLabel("Hide until more words are missing a meaning")
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.accentSubtle, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.xs)
    }

    private func running(_ run: WordEnricher.Run) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.sm) {
                Text("Filling · \(run.completed) / \(run.total)")
                    .font(DS.Typography.caption.weight(.semibold))
                    .monospacedDigit()
                Text(run.currentTerm)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                Spacer(minLength: 0)
                Button("Stop") { enricher.stop() }
                    .controlSize(.small)
            }
            .lineLimit(1)
            ProgressView(value: Double(run.completed), total: Double(max(run.total, 1)))
                .progressViewStyle(.linear)
                .controlSize(.mini)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .dsCard(padding: nil, radius: DS.Radius.sm)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.xs)
    }
}

// MARK: - Sheet

struct FillMissingSheet: View {
    var store: SavedWordsStore
    var enricher: WordEnricher
    /// The selected words, or nil for all of them.
    var wordIDs: Set<UUID>? = nil
    /// "Show Words Still Missing a Meaning".
    var onShowMissing: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage(StorageKey.fillUsesProvider) private var usesProvider = true
    @State private var fields: Set<FillField> = FillField.defaultSelection

    private var scopeCount: Int { wordIDs?.count ?? store.words.count }
    private var fieldsToFill: Int { enricher.emptyFieldCount(fields, in: wordIDs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Fill Missing")
                    .font(DS.Typography.headline)
                Text(subtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .padding([.top, .horizontal], DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.sm)

            Group {
                if let run = enricher.run {
                    if run.isFinished { finished(run) } else { progress(run) }
                } else {
                    setup
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.md)

            Divider()
            footer
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
        }
        .frame(width: 440)
    }

    private var subtitle: String {
        guard let run = enricher.run else {
            let words = enricher.wordsMissingAny(Set(FillField.allCases), in: wordIDs)
            return String(localized: "\(words) of \(scopeCount) words have an empty field.")
        }
        if !run.isFinished { return String(localized: "Each field is saved as soon as it's found.") }
        return run.wasStopped ? String(localized: "Stopped. What was filled stays.") : String(localized: "Done.")
    }

    // MARK: Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(spacing: 0) {
                ForEach(Array(FillField.allCases.enumerated()), id: \.element) { index, field in
                    if index > 0 { Divider() }
                    fieldRow(field)
                }
            }
            .dsCard(padding: nil, radius: DS.Radius.sm)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("TRIED IN ORDER").dsOverlineLabel()
                SourceChain(includesProvider: usesProvider)
            }

            Toggle(isOn: $usesProvider) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Also use your AI provider")
                    Text("Only when the first two find nothing. A cloud provider receives the words.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private func fieldRow(_ field: FillField) -> some View {
        let missing = enricher.missingCount(field, in: wordIDs)
        return Toggle(isOn: Binding(
            get: { fields.contains(field) },
            set: { on in if on { fields.insert(field) } else { fields.remove(field) } }
        )) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(field.localizedTitle)
                    Text(field == .examples ? String(localized: "The model writes them; most words already have their book sentence") : field.sourceHint)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                Spacer(minLength: DS.Spacing.sm)
                Text("\(missing) empty")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
        .disabled(missing == 0)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: Running and finished

    private func progress(_ run: WordEnricher.Run) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack {
                    Text(run.currentTerm).font(DS.Typography.callout.weight(.semibold))
                    Spacer()
                    Text("\(run.completed) / \(run.total)")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .monospacedDigit()
                }
                ProgressView(value: Double(run.completed), total: Double(max(run.total, 1)))
            }
            FillTally(run: run)
            Text("You can close this window. Filling goes on in the background, with its progress above the word list.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func finished(_ run: WordEnricher.Run) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            FillTally(run: run)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("\(run.filledCount) fields filled.")
                    .font(DS.Typography.callout.weight(.semibold))
                let stillEmpty = FillField.allCases
                    .filter { run.fields.contains($0) }
                    .map { ($0, enricher.missingCount($0, in: wordIDs)) }
                    .filter { $0.1 > 0 }
                ForEach(stillEmpty, id: \.0) { field, count in
                    Text("Still empty: \(field.localizedTitle), \(count) words")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let run = enricher.run {
                if run.isFinished {
                    if let onShowMissing, enricher.missingCount(.meaning, in: wordIDs) > 0 {
                        Button("Show Words Still Missing a Meaning") {
                            enricher.clearFinishedRun()
                            dismiss()
                            onShowMissing()
                        }
                    }
                    Spacer()
                    Button("Done") {
                        enricher.clearFinishedRun()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Stop") { enricher.stop() }
                    Spacer()
                    Button("Continue in Background") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(fieldsToFill == 1 ? String(localized: "Fill 1 Field") : String(localized: "Fill \(fieldsToFill) Fields")) {
                    enricher.start(fields: fields, allowProvider: usesProvider, wordIDs: wordIDs)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(fieldsToFill == 0)
            }
        }
        .controlSize(.regular)
    }
}

// MARK: - Pieces

/// Dictionary → on-device model → provider, as chips.
struct SourceChain: View {
    var includesProvider: Bool
    var providerName: String = LLMConfiguration().providerType.localizedTitle

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            SourceChip(source: .dictionary, title: String(localized: "Apple Dictionary"))
            if AppleOnDevice.isEnabled && AppleOnDevice.isModelAvailable {
                arrow
                SourceChip(source: .onDevice, title: String(localized: "On-device model"))
            }
            if includesProvider {
                arrow
                SourceChip(source: .provider(providerName), title: providerName)
            }
        }
        .lineLimit(1)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(DS.Typography.icon(9))
            .foregroundStyle(DS.Color.textTertiary)
            .accessibilityHidden(true)
    }
}

/// Where a value came from, as a small tinted capsule.
struct SourceChip: View {
    var source: FillSource
    var title: String? = nil

    var body: some View {
        Text(title ?? source.label)
            .font(DS.Typography.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, 1)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }

    private var tint: Color {
        switch source.kind {
        case .dictionary: return .purple
        case .model:      return .teal
        case .provider:   return DS.Color.warning
        }
    }
}

/// Fields down, sources across — how many each source filled.
private struct FillTally: View {
    var run: WordEnricher.Run

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Spacing.md, verticalSpacing: DS.Spacing.xxs) {
            GridRow {
                Text("Field")
                Text("Dictionary").gridColumnAlignment(.trailing)
                Text("Model").gridColumnAlignment(.trailing)
                Text("Provider").gridColumnAlignment(.trailing)
            }
            .font(DS.Typography.caption2)
            .foregroundStyle(DS.Color.textTertiary)
            ForEach(FillField.allCases.filter { run.tally[$0] != nil }) { field in
                GridRow {
                    Text(field.localizedTitle)
                    Text(cell(field, .dictionary))
                    Text(cell(field, .model))
                    Text(cell(field, .provider))
                }
                .font(DS.Typography.caption)
                .monospacedDigit()
            }
        }
    }

    private func cell(_ field: FillField, _ kind: FillSource.Kind) -> String {
        if field == .pronunciation && kind != .dictionary { return "–" }
        if field == .level && kind == .dictionary { return "–" }
        return "\(run.count(field, kind))"
    }
}
