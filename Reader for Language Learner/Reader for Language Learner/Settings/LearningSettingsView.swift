//
//  LearningSettingsView.swift
//  Reader for Language Learner
//
//  Settings ▸ Learning (v14 S4): your languages and level, the reading
//  loop's recaps and warm-ups, the daily goal and reminder. Split from the
//  old General tab; the stored keys are unchanged.
//

import SwiftUI

struct LearningSettingsView: View {

    @AppStorage(Language.nativeLanguageKey) private var nativeRaw = Language.defaultNative.rawValue
    @AppStorage(Language.targetLanguageKey) private var targetRaw = Language.defaultTarget.rawValue

    private var native: Language { Language(rawValue: nativeRaw) ?? .turkish }
    private var target: Language { Language(rawValue: targetRaw) ?? .english }

    @AppStorage(StorageKey.domainPreference) private var domainRaw = DomainPreference.general.rawValue
    @AppStorage(StorageKey.learnerLevel) private var learnerLevelRaw = CEFRLevel.defaultLearnerLevel.rawValue
    @AppStorage(StorageKey.readingRecapEnabled) private var readingRecapEnabled = true
    @AppStorage(StorageKey.chapterWarmUpEnabled) private var chapterWarmUpEnabled = true
    @AppStorage(StorageKey.dailyReadingGoalMinutes) private var goalMinutes: Int = 20
    @AppStorage(DailyReminderManager.enabledKey) private var dailyReminderEnabled = false
    @AppStorage(DailyReminderManager.timeKey) private var dailyReminderTime = DailyReminderManager.storedTime()

    var body: some View {
        Form {
            Section {
                languagePairSection
                Picker(selection: $learnerLevelRaw) {
                    ForEach(CEFRLevel.allCases) { level in
                        Text(level.rawValue).tag(level.rawValue)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Level")
                        Text("Recaps and chapter warm-ups are written for this level.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
            } header: {
                Text("Language Pair")
            } footer: {
                Text("RELL translates and explains \(target.nativeName) content into \(native.nativeName).")
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Section("Reading Context") {
                domainRow
            }

            Section {
                Toggle(isOn: $readingRecapEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recap When You Return")
                        Text("After three days away from a book, sum up where you left off.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                Toggle(isOn: $chapterWarmUpEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chapter Warm-Up")
                        Text("Pick out the hard words of each book chapter before you read it.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
            } header: {
                Text("Reading Loop")
            } footer: {
                Text("Recaps and warm-ups use your AI provider, or Apple's on-device model where it's on.")
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Section {
                Picker("Daily Reading Goal", selection: $goalMinutes) {
                    ForEach(DashboardActivityCard.goalChoices, id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }
            } header: {
                Text("Goal")
            } footer: {
                Text("Shown on the home screen's reading card. You can also right-click that card to change it.")
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Section {
                Toggle(isOn: $dailyReminderEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Reminder")
                        Text("Get a nudge to review your words or hit your reading goal.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .onChange(of: dailyReminderEnabled) { _, enabled in
                    if enabled {
                        Task { await DailyReminderManager.shared.requestAuthorizationAndSchedule() }
                    } else {
                        DailyReminderManager.shared.cancel()
                    }
                }
                if dailyReminderEnabled {
                    DatePicker(
                        "Reminder Time",
                        selection: $dailyReminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: dailyReminderTime) { _, _ in
                        DailyReminderManager.shared.schedule()
                    }
                }
            } header: {
                Text("Reminders")
            }

        }
        .formStyle(.grouped)
    }

    // MARK: - Language Pair

    private var languagePairSection: some View {
        HStack(spacing: DS.Spacing.xl) {
            languageCard(
                role: "Learning",
                language: target,
                storageKey: Language.targetLanguageKey,
                exclude: native
            )

            Image(systemName: "arrow.right")
                .font(.title2.weight(.light))
                .foregroundStyle(DS.Color.textTertiary)

            languageCard(
                role: "Native",
                language: native,
                storageKey: Language.nativeLanguageKey,
                exclude: target
            )
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity)
    }

    private func languageCard(
        role: String,
        language: Language,
        storageKey: String,
        exclude: Language
    ) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Text(language.flag)
                // DS-exempt: one-off emoji glyph size, not a text-style role.
                .font(.system(size: 40))

            VStack(spacing: DS.Spacing.xxs) {
                Text(language.nativeName)
                    .font(DS.Typography.subhead.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                Text(role.uppercased())
                    .font(DS.Typography.caption2.weight(.heavy))
                    .foregroundStyle(DS.Color.textTertiary)
                    .tracking(0.5)
            }

            // Inline picker hidden behind a Menu
            Picker("", selection: Binding(
                get: { language.rawValue },
                set: { UserDefaults.standard.set($0, forKey: storageKey) }
            )) {
                ForEach(Language.allCases.filter { $0 != exclude }) { lang in
                    Label("\(lang.flag) \(lang.rawValue)", systemImage: "")
                        .tag(lang.rawValue)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 130)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.md)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - Domain

    private var domainRow: some View {
        LabeledContent("Domain") {
            Picker("", selection: $domainRaw) {
                ForEach(DomainPreference.allCases) { d in
                    Text(d.localizedTitle).tag(d.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 160)
        }
    }
}

#Preview {
    LearningSettingsView()
}
