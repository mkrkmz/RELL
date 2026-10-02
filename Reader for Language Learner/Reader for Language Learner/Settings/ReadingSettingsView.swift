//
//  ReadingSettingsView.swift
//  Reader for Language Learner
//
//  Settings ▸ Reading (v14 S4): what happens on the page — the hover
//  dictionary, sentence translation, pre-analysis, speech, Quick Lookup.
//  Split from the old General tab; the stored keys are unchanged.
//

import SwiftUI

struct ReadingSettingsView: View {

    @AppStorage(Language.nativeLanguageKey) private var nativeRaw = Language.defaultNative.rawValue
    @AppStorage(Language.targetLanguageKey) private var targetRaw = Language.defaultTarget.rawValue

    private var native: Language { Language(rawValue: nativeRaw) ?? .turkish }
    private var target: Language { Language(rawValue: targetRaw) ?? .english }


    var body: some View {
        Form {
            Section {
                Toggle(isOn: $hoverDictionaryEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hover Dictionary")
                        Text("Show a quick definition when you hover over a word.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }

                Picker(selection: $hoverDictionaryLanguageRaw) {
                    ForEach(HoverDictionaryLanguage.allCases) { choice in
                        Text(choice.localizedTitle(target: target, native: native))
                            .tag(choice.rawValue)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Answer In")
                        Text("Stay immersed in the language you're studying, or get the meaning in your own.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .disabled(!hoverDictionaryEnabled)
                Toggle(isOn: $sentenceTranslationEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sentence Translation")
                        Text("Translate the selected sentence below the page.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                Picker("Translate With", selection: $sentenceTranslationEngineRaw) {
                    ForEach(SentenceTranslationEngine.allCases) { engine in
                        Text(engine.localizedTitle).tag(engine.rawValue)
                    }
                }
                .disabled(!sentenceTranslationEnabled)
                Toggle(isOn: $pageAnalysisEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Page Pre-Analysis")
                        Text("Pre-fetch definitions for likely-unfamiliar words on the current page, so lookups are instant.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
            } header: {
                Text("On the Page")
            } footer: {
                Text("The hover dictionary and pre-analysis use your AI provider, or Apple's on-device model where it's on. Apple Translation works offline once the language is downloaded, and falls back to your AI provider for pairs it doesn't support.")
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack {
                        Text("Speaking Rate")
                        Spacer()
                        Text(speechRateLabel)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    Slider(value: $speechRate, in: 0.35...0.65)
                }
            } header: {
                Text("Speech")
            } footer: {
                Text("Used by pronounce buttons and Read Page Aloud (Speech menu).")
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Section {
                Toggle(isOn: $menuBarExtraEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu Bar Icon")
                        Text("Look up words from the menu bar, even when no window is open.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                Toggle(isOn: $hotkeyEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Global Shortcut  ⌃⌥Space")
                        Text("Open the Quick Lookup panel from any app.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .onChange(of: hotkeyEnabled) { _, enabled in
                    if enabled {
                        GlobalHotKeyManager.shared.register()
                    } else {
                        GlobalHotKeyManager.shared.unregister()
                    }
                }
            } header: {
                Text("Quick Lookup")
            }

        }
        .formStyle(.grouped)
    }

    @AppStorage(StorageKey.hoverDictionaryEnabled) private var hoverDictionaryEnabled = true
    @AppStorage(HoverDictionaryLanguage.storageKey)
    private var hoverDictionaryLanguageRaw = HoverDictionaryLanguage.default.rawValue
    @AppStorage(StorageKey.sentenceTranslationEnabled) private var sentenceTranslationEnabled = true
    @AppStorage(SentenceTranslationEngine.storageKey)
    private var sentenceTranslationEngineRaw = SentenceTranslationEngine.default.rawValue
    @AppStorage(StorageKey.pageAnalysisEnabled) private var pageAnalysisEnabled = false
    @AppStorage(StorageKey.speechRate) private var speechRate: Double = 0.5
    @AppStorage(StorageKey.menuBarExtraEnabled) private var menuBarExtraEnabled = true

    private var speechRateLabel: LocalizedStringKey {
        switch speechRate {
        case ..<0.45: return "Slow"
        case 0.45..<0.55: return "Normal"
        default: return "Fast"
        }
    }
    @AppStorage(GlobalHotKeyManager.enabledKey) private var hotkeyEnabled = true
}

#Preview {
    ReadingSettingsView()
}
