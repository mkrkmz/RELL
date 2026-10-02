//
//  WhatsNewSheet.swift
//  Reader for Language Learner
//
//  The "What's new" page (v14 S3). See `WhatsNew`.
//

import SwiftUI

struct WhatsNewSheet: View {
    let page: WhatsNew
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("RELL \(page.version)")
                    .dsOverlineLabel()
                    .textCase(.uppercase)
                Text("In this version")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Color.textPrimary)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ForEach(page.items, id: \.title) { item in
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        Image(systemName: item.icon)
                            .font(DS.Typography.icon(15, weight: .medium))
                            .foregroundStyle(DS.Color.accent)
                            .frame(width: 32, height: 32)
                            .background(DS.Color.accentSubtle, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(DS.Typography.label)
                                .foregroundStyle(DS.Color.textPrimary)
                            Text(item.detail)
                                .font(DS.Typography.callout)
                                .foregroundStyle(DS.Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            HStack {
                Spacer()
                Button("Continue", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Spacing.xl)
        .frame(width: 440)
        .onExitCommand(perform: onDone)
    }
}
