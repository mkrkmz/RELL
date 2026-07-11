//
//  SettingsView.swift
//  Reader for Language Learner
//
//  Root of the macOS Settings scene (⌘,).
//  Four tabs: General · LLM · Prompts · Appearance
//

import SwiftUI

/// Tab identifiers — persisted so in-app shortcuts (e.g. the LLM status
/// popover) can deep-link to a specific pane before opening Settings.
enum SettingsTab: String {
    case general, llm, prompts, appearance
}

struct SettingsView: View {
    @AppStorage("settingsSelectedTab") private var selectedTabRaw = SettingsTab.general.rawValue

    private var selectedTab: Binding<SettingsTab> {
        Binding(
            get: { SettingsTab(rawValue: selectedTabRaw) ?? .general },
            set: { selectedTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            LLMSettingsView()
                .tabItem { Label("LLM", systemImage: "cpu") }
                .tag(SettingsTab.llm)

            PromptSettingsView()
                .tabItem { Label("Prompts", systemImage: "text.bubble") }
                .tag(SettingsTab.prompts)

            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)
        }
        // One fixed size for every tab (sized to the tallest, Prompts) —
        // per-tab heights made the window visibly jump when switching tabs.
        .frame(width: DS.Layout.settingsWindow.width, height: DS.Layout.settingsWindow.height)
    }
}

#Preview {
    SettingsView()
}
