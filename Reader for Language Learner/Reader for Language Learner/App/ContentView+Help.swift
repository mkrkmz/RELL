//
//  ContentView+Help.swift
//  Reader for Language Learner
//
//  Help ▸ Check for Updates… and Diagnostic Report… (Roadmap v17 Sprint 3):
//  the key window shows the sheet, like What's New.
//

import SwiftUI

extension ContentView {

    func withHelpSheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: Bindable(model).showUpdateCheck) {
                UpdateSheet { model.showUpdateCheck = false }
            }
            .sheet(isPresented: Bindable(model).showDiagnosticReport) {
                DiagnosticReportSheet { model.showDiagnosticReport = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: .checkForUpdatesCommand)) { _ in
                guard isFrontWindow else { return }
                model.showUpdateCheck = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .diagnosticReportCommand)) { _ in
                guard isFrontWindow else { return }
                model.showDiagnosticReport = true
            }
    }

    /// The key window, or the first visible one when none is key.
    private var isFrontWindow: Bool {
        model.hostWindow?.isKeyWindow == true
            || NSApp.keyWindow == nil && model.hostWindow == NSApp.windows.first(where: \.isVisible)
    }
}
