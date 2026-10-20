//
//  InterfaceLanguageSection.swift
//  Reader for Language Learner
//
//  Settings ▸ Appearance ▸ Interface Language (Roadmap v19 Sprint 5).
//

import SwiftUI

struct InterfaceLanguageSection: View {
    @State private var choice = InterfaceLanguage.stored()
    /// What the interface was when this window opened, to tell when a
    /// restart is needed.
    @State private var launched = InterfaceLanguage.stored()

    var body: some View {
        Section {
            Picker(selection: $choice) {
                ForEach(InterfaceLanguage.allCases) { language in
                    Text(language.isBeta ? "\(language.title) (beta)" : language.title).tag(language)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Interface Language")
                    Text("Applies when RELL opens again. The language you're learning stays as it is.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            .onChange(of: choice) { _, language in language.store() }

            if choice != launched {
                LabeledContent {
                    Button("Restart Now") { InterfaceLanguage.relaunch() }
                } label: {
                    Text("RELL opens in \(choice.title) after a restart.")
                        .foregroundStyle(DS.Color.warning)
                }
            }
            if choice.isBeta {
                LabeledContent {
                    Link("Fix a Translation…", destination: InterfaceLanguage.fixTranslationURL)
                } label: {
                    Text("\(choice.title) hasn't been reviewed by a native speaker yet.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
        } header: {
            Text("Interface Language")
        }
    }
}
