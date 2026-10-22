//
//  SavedWordDetailSheet+History.swift
//  Reader for Language Learner
//
//  Memory, encounters and where the word was saved. Split out of
//  SavedWordDetailSheet.swift (v20 S0), unchanged.
//

import SwiftUI

extension SavedWordDetailSheet {

    // MARK: - Memory

    /// v18 S5: how well you remember it — the chance now in a number and a
    /// word, when it comes back, and the last answers as marks.
    var memoryCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("MEMORY").dsOverlineLabel()
            HStack(spacing: DS.Spacing.lg) {
                if let recall = WordPageModel.recallNow(current) {
                    let strength = RecallStrength(recall)
                    Gauge(value: recall) {
                        EmptyView()
                    } currentValueLabel: {
                        Text(recall, format: .percent.precision(.fractionLength(0)))
                            .font(DS.Typography.statNumber(12))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(strength.color)
                    .accessibilityLabel(Text("Chance you remember it now"))
                    .accessibilityValue(Text("\(Int((recall * 100).rounded()))%, \(strength.title)"))

                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text("\(strength.title): you'd remember it now with a \(Int((recall * 100).rounded()))% chance")
                            .font(DS.Typography.label)
                            .foregroundStyle(DS.Color.textPrimary)
                        nextReviewLine
                    }
                } else {
                    Image(systemName: "sparkle")
                        .font(DS.Typography.icon(20))
                        .foregroundStyle(DS.Color.accent)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text("Not reviewed yet")
                            .font(DS.Typography.label)
                            .foregroundStyle(DS.Color.textPrimary)
                        Text("Its first review will start tracking how well you remember it.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            let history = WordPageModel.recentAnswers(current)
            if !history.isEmpty {
                ReviewHistoryStrip(events: history)
            }
        }
        .dsCard()
    }

    @ViewBuilder
    private var nextReviewLine: some View {
        if let next = current.nextReviewAt {
            if next <= Date() {
                Text("Due for review now")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.warning)
            } else {
                Text("Next review \(WordStatus.relative(next)) (\(next, format: .dateTime.weekday(.wide)))")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        Text("\(current.reviewCount) reviews · \(current.incorrectCount) times Again")
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Color.textTertiary)
    }

    // MARK: - Encounters

    var encountersSection: some View {
        let encounters = encounterStore.encounters(for: word.id)
        let shown = showAllEncounters ? encounters : Array(encounters.prefix(Self.collapsedEncounterCount))
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("MET IN YOUR READING").dsOverlineLabel()
                Spacer()
                if let summary = WordPageModel.encounterSummary(encounters) {
                    Text(summary)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            if encounters.isEmpty {
                Text("Not met again yet. Pages you read from now on are checked for this word, and every sentence it turns up in is collected here.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // v18 S5: grouped by book, each with how often it turned up.
                ForEach(WordPageModel.groupedByBook(shown, all: encounters)) { book in
                    HStack {
                        Text(book.title)
                            .font(DS.Typography.caption.weight(.semibold))
                            .foregroundStyle(DS.Color.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(book.times == 1 ? String(localized: "once") : String(localized: "\(book.times) times"))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                            .monospacedDigit()
                    }
                    .padding(.top, DS.Spacing.xxs)
                    ForEach(book.encounters) { encounter in
                        EncounterRow(
                            encounter: encounter,
                            sentence: WordPageModel.emphasized(encounter.sentence, term: word.term, language: language),
                            isAvailable: DocumentJump.isAvailable(encounter.documentPath),
                            onOpen: { open(encounter) }
                        )
                    }
                }
                if encounters.count > Self.collapsedEncounterCount {
                    Button(showAllEncounters ? "Show fewer" : "Show all \(encounters.count)") {
                        withAnimation(DS.Animation.standard) { showAllEncounters.toggle() }
                    }
                    .buttonStyle(.link)
                    .font(DS.Typography.caption)
                }
            }
        }
    }

    private func open(_ encounter: WordEncounter) {
        let location = DocumentLocation(
            url: URL(fileURLWithPath: encounter.documentPath),
            location: encounter.location,
            isEPUB: encounter.isEPUB
        )
        DocumentJump.prepare(location)
        if !isPane { dismiss() }   // in a window, dismiss would close it
        openWindow(value: location.url)
        DocumentJump.announce(location)
    }

    // MARK: - Saved context

    var savedContext: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("WHERE YOU SAVED IT").dsOverlineLabel()
            Text(WordPageModel.emphasized(word.sentence, term: word.term, language: language))
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
            if let pdf = word.pdfFilename {
                Text(pdf + (word.pageNumber.map { " · \(String(localized: "p. \($0)"))" } ?? ""))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
    }
}
