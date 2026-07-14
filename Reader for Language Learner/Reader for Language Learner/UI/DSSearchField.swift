//
//  DSSearchField.swift
//  Reader for Language Learner
//
//  Shared chrome for the Library and Saved Words search fields — previously
//  two hand-rolled implementations that had drifted apart (one had a hairline
//  border but no clear button, the other a clear button but no border).
//  Not a `.searchable()` wrapper: both hosts are embedded panes without their
//  own toolbar/navigation context, so `.searchable()` would either hijack the
//  window's single toolbar or fail to render at all.
//

import SwiftUI

struct DSSearchField: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey = "Search"
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(DS.Typography.icon(11))
                .foregroundStyle(DS.Color.textTertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Typography.subhead)
                .focused(focused)
                // Esc clears the field first; an empty field lets Esc bubble
                // to the host's own handler (e.g. Library's Back-on-Esc).
                .onKeyPress(.escape) {
                    guard !text.isEmpty else { return .ignored }
                    text = ""
                    return .handled
                }

            if !text.isEmpty {
                Button {
                    withAnimation(DS.Animation.fast) { text = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 5)
        .background(DS.Color.surfaceInset)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Color.hairline, lineWidth: 0.7)
        )
        .animation(DS.Animation.fast, value: text.isEmpty)
    }
}
