//
//  GeneralSettingsView.swift
//  Reader for Language Learner
//
//  Language-pair picker + domain preference.
//

import SwiftUI

struct GeneralSettingsView: View {

    @AppStorage(Language.nativeLanguageKey) private var nativeRaw = Language.defaultNative.rawValue
    @AppStorage(Language.targetLanguageKey) private var targetRaw = Language.defaultTarget.rawValue

    private var native: Language { Language(rawValue: nativeRaw) ?? .turkish }
    private var target: Language { Language(rawValue: targetRaw) ?? .english }

    @AppStorage("domainPreference") private var domainRaw = DomainPreference.general.rawValue

    var body: some View {
        Form {
            Section {
                languagePairSection
            } header: {
                Text("Language Pair")
            } footer: {
                Text("RELL translates and explains \(target.nativeName) content into \(native.nativeName).")
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Section("Reading Context") {
                domainRow
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 320)
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
                    Text(d.rawValue).tag(d.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 160)
        }
    }
}

#Preview {
    GeneralSettingsView()
}
