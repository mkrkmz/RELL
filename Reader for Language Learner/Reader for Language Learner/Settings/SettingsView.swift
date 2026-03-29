//
//  SettingsView.swift
//  Reader for Language Learner
//
//  Root of the macOS Settings scene (⌘,).
//  Three tabs: General · LLM · Appearance
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            LLMSettingsView()
                .tabItem { Label("LLM", systemImage: "cpu") }

            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        // Fixed width keeps the window tidy; height adapts to the tallest tab
        .frame(width: 540)
    }
}

#Preview {
    SettingsView()
}
