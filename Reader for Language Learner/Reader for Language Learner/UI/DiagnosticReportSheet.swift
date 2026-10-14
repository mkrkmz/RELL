//
//  DiagnosticReportSheet.swift
//  Reader for Language Learner
//
//  Help ▸ Diagnostic Report… (Roadmap v17 Sprint 3, approved decision 4):
//  the whole report on screen first, then Copy. Nothing is sent.
//

import AppKit
import SwiftUI

struct DiagnosticReportSheet: View {
    var onClose: () -> Void
    @State private var report: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Diagnostic Report")
                .font(DS.Typography.headline)
            Text("Paste it when you describe a problem. It holds no words, sentences, book titles or keys, and nothing is sent by itself.")
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView([.vertical, .horizontal]) {
                if let report {
                    Text(report)
                        .font(DS.Typography.mono)
                        .textSelection(.enabled)
                        .fixedSize()
                        .padding(DS.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ProgressView().padding(DS.Spacing.xl)
                }
            }
            .frame(height: 320)
            .background(DS.Color.surfaceInset, in: RoundedRectangle(cornerRadius: DS.Radius.md))

            HStack {
                Button("Close", action: onClose)
                Spacer()
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .foregroundStyle(DS.Color.success)
                        .font(DS.Typography.caption)
                }
                Button("Copy") {
                    guard let report else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copied = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(report == nil)
            }
        }
        .padding(DS.Spacing.xl)
        .frame(width: 600)
        .task { report = DiagnosticReport.text(await DiagnosticReport.gather()) }
    }
}
