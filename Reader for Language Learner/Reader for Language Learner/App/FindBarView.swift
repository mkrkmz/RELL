//
//  FindBarView.swift
//  Reader for Language Learner
//
//  Extracted from ContentView.swift
//

import SwiftUI

struct FindBarView: View {
    var searchManager: PDFSearchManager
    let onClose: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(DS.Color.textSecondary)

            TextField("Find in PDF…", text: Binding(
                get: { searchManager.query },
                set: { searchManager.query = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($isFieldFocused)
            .onSubmit { searchManager.next() }
            .onAppear { isFieldFocused = true }

            Button { searchManager.previous() } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(searchManager.totalCount == 0)
            .keyboardShortcut(.return, modifiers: [.shift])
            .help("Previous Match (⇧↩)")

            Button { searchManager.next() } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(searchManager.totalCount == 0)
            .keyboardShortcut(.return, modifiers: [])
            .keyboardShortcut("g", modifiers: [.command])
            .help("Next Match (↩)")

            Text(searchManager.currentPositionLabel)
                .font(DS.Typography.mono)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(minWidth: 60)

            if searchManager.isSearching {
                ProgressView().controlSize(.small)
            }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Close Find (Esc)")
        }
        .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }
}
