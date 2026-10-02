//
//  SettingsView.swift
//  Reader for Language Learner
//
//  Root of the macOS Settings scene (⌘,).
//  Six tabs (v14 S4): Reading · Learning · AI · Prompts · Appearance · Data
//

import SwiftUI

/// Tab identifiers — persisted so in-app shortcuts (e.g. the LLM status
/// popover) can deep-link to a specific pane before opening Settings.
enum SettingsTab: String, CaseIterable {
    /// Reading. Keeps the raw value "general" — the old General tab's —
    /// so a stored selection still opens the tab most of it moved to.
    case general
    case learning, llm, prompts, appearance, data
}

struct SettingsView: View {
    @AppStorage(StorageKey.settingsSelectedTab) private var selectedTabRaw = SettingsTab.general.rawValue

    private var selectedTab: Binding<SettingsTab> {
        Binding(
            get: { SettingsTab(rawValue: selectedTabRaw) ?? .general },
            set: { selectedTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selectedTab) {
            ReadingSettingsView()
                .tabItem { Label("Reading", systemImage: "book") }
                .tag(SettingsTab.general)

            LearningSettingsView()
                // "Study", not "Learning": that key is the word status
                // ("Öğreniliyor" in Turkish).
                .tabItem { Label("Study", systemImage: "graduationcap") }
                .tag(SettingsTab.learning)

            LLMSettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(SettingsTab.llm)

            PromptSettingsView()
                .tabItem { Label("Prompts", systemImage: "text.bubble") }
                .tag(SettingsTab.prompts)

            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)

            DataSettingsView()
                .tabItem { Label("Data", systemImage: "externaldrive") }
                .tag(SettingsTab.data)
        }
        // One fixed size for every tab (sized to the tallest, Prompts) —
        // per-tab heights made the window visibly jump when switching tabs.
        .frame(width: DS.Layout.settingsWindow.width, height: DS.Layout.settingsWindow.height)
    }
}

#Preview {
    SettingsView()
}
