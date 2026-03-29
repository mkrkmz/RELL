//
//  PageIndicatorView.swift
//  Reader for Language Learner
//
//  Compact toolbar widget showing "11 / 28".
//  Tapping the page number switches to an editable field for direct navigation.
//

import SwiftUI

struct PageIndicatorView: View {
    let currentPageIndex: Int?   // 0-based
    let pageCount: Int
    let onNavigate: (Int) -> Void  // caller receives 0-based index

    @State private var isEditing = false
    @State private var editText  = ""

    private var displayPage: Int { (currentPageIndex ?? 0) + 1 }

    var body: some View {
        HStack(spacing: 2) {
            pageField
            Text("/")
                .font(DS.Typography.mono)
                .foregroundStyle(DS.Color.textTertiary)
            Text("\(pageCount)")
                .font(DS.Typography.mono)
                .foregroundStyle(DS.Color.textTertiary)
                .frame(minWidth: totalWidth)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 3)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(
                    isEditing ? DS.Color.accent : DS.Color.separator,
                    lineWidth: 0.5
                )
        )
        .animation(DS.Animation.springFast, value: isEditing)
    }

    // MARK: - Page field

    @ViewBuilder
    private var pageField: some View {
        if isEditing {
            TextField("", text: $editText)
                .font(DS.Typography.mono)
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .frame(width: currentWidth)
                .textFieldStyle(.plain)
                .onSubmit { commitEdit() }
                .onExitCommand { isEditing = false }
                .onAppear {
                    editText = "\(displayPage)"
                }
        } else {
            Text("\(displayPage)")
                .font(DS.Typography.mono.weight(.medium))
                .foregroundStyle(DS.Color.accent)
                .frame(width: currentWidth)
                .contentShape(Rectangle())
                .onTapGesture { enterEdit() }
                .help("Click to jump to page")
        }
    }

    // MARK: - Helpers

    /// Width wide enough for the current page number.
    private var currentWidth: CGFloat {
        let digits = max(1, "\(displayPage)".count)
        return CGFloat(digits) * 9 + 4
    }

    /// Width wide enough for the total page count (so layout stays stable).
    private var totalWidth: CGFloat {
        let digits = max(1, "\(pageCount)".count)
        return CGFloat(digits) * 9 + 4
    }

    private func enterEdit() {
        editText = "\(displayPage)"
        isEditing = true
    }

    private func commitEdit() {
        defer { isEditing = false }
        guard let number = Int(editText.trimmingCharacters(in: .whitespaces)),
              number >= 1, number <= pageCount
        else { return }
        onNavigate(number - 1)
    }
}

#Preview {
    PageIndicatorView(currentPageIndex: 10, pageCount: 28) { _ in }
        .padding()
}
