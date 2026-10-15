//
//  InspectorCardEditor.swift
//  Reader for Language Learner
//
//  Edit Card… (Roadmap v18 Sprint 2, approved mockup): which buttons the
//  Inspector's word or sentence card shows, in what order — the rest wait
//  in its ••• menu. Changes apply at once and are remembered. Opened from
//  ••• and a card button's right-click, and from Settings ▸ Reading.
//

import SwiftUI

struct InspectorCardEditor: View {
    var onDone: () -> Void
    /// v18 S3: writing your own module starts from here too.
    var onNewModule: (() -> Void)?

    @State private var kind: CardKind
    @State private var pinned: [CardItem]

    init(initialKind: CardKind = .word, onNewModule: (() -> Void)? = nil, onDone: @escaping () -> Void) {
        self.onDone = onDone
        self.onNewModule = onNewModule
        _kind = State(initialValue: initialKind)
        _pinned = State(initialValue: InspectorCardLayout.load(initialKind))
    }

    private var native: Language { Language.storedNative }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Edit Card")
                .font(DS.Typography.headline)
            Text("Choose what the Inspector's card shows and drag to reorder. What doesn't fit the column waits in its ••• menu.")
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Card", selection: $kind) {
                Text("Word").tag(CardKind.word)
                Text("Sentence").tag(CardKind.sentence)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: kind) { _, newKind in pinned = InspectorCardLayout.load(newKind) }

            preview

            HStack(alignment: .top, spacing: DS.Spacing.md) {
                list(title: "On the Card") {
                    List {
                        if kind == .word {
                            row(String(localized: "Save"), icon: "star", trailing: Text("always").foregroundStyle(DS.Color.textTertiary))
                        }
                        ForEach(pinned, id: \.self) { item in
                            row(title(item), icon: CardItem.icon(of: item)) {
                                Button("Move to •••", systemImage: "arrow.right") { change { InspectorCardLayout.unpin(item, in: $0) } }
                                    .buttonStyle(.dsIconSecondary)
                                    .help("Move to the ••• menu")
                            }
                        }
                        .onMove { from, to in change { var list = $0; list.move(fromOffsets: from, toOffset: to); return list } }
                    }
                }
                list(title: "In the ••• Menu") {
                    List {
                        ForEach(InspectorCardLayout.unpinned(kind, pinned: pinned), id: \.self) { item in
                            row(title(item), icon: CardItem.icon(of: item)) {
                                Button("Add to Card", systemImage: "arrow.left") { change { InspectorCardLayout.pin(item, in: $0) } }
                                    .buttonStyle(.dsIcon)
                                    .help("Add to the card")
                            }
                        }
                    }
                }
            }
            .frame(height: 300)

            HStack {
                Button("Restore Defaults") {
                    InspectorCardLayout.reset(kind)
                    pinned = InspectorCardLayout.load(kind)
                }
                if let onNewModule {
                    Button("New Module…", action: onNewModule)
                        .disabled(!CustomModuleStore.shared.canAdd)
                }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Spacing.xl)
        .frame(width: 520)
    }

    // MARK: Pieces

    /// The two rows as the card will show them (before fitting the width).
    private var preview: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xxs) {
                if kind == .word { previewButton(String(localized: "Save"), icon: "star") }
                ForEach(pinned.filter(\.isAction), id: \.self) { previewButton(title($0), icon: CardItem.icon(of: $0)) }
                Spacer(minLength: 0)
                Image(systemName: "ellipsis.circle").foregroundStyle(DS.Color.accent)
            }
            Rectangle().fill(DS.Color.accent.opacity(0.14)).frame(height: 1)
            HStack(spacing: DS.Spacing.xxs) {
                ForEach(pinned.filter { !$0.isAction }, id: \.self) { previewButton(title($0), icon: CardItem.icon(of: $0)) }
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .padding(DS.Spacing.sm)
        .background(DS.Gradient.accentWash, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of the card")
    }

    private func previewButton(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .labelStyle(DSQuietLabelStyle())
            .font(DS.Typography.caption.weight(.semibold))
            .padding(.horizontal, DS.Spacing.sm)
            .frame(height: 24)
    }

    private func list<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title).dsOverlineLabel()
            content()
                .listStyle(.bordered)
                .scrollContentBackground(.visible)
        }
        .frame(maxWidth: .infinity)
    }

    private func row<Trailing: View>(_ title: String, icon: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(DS.Color.accent)
                .frame(width: 18)
            Text(title)
            Spacer(minLength: 0)
            trailing()
        }
    }

    private func row(_ title: String, icon: String, trailing: some View) -> some View {
        row(title, icon: icon) { trailing }
    }

    private func title(_ item: CardItem) -> String {
        CardItem.title(of: item, kind: kind, native: native) ?? ""
    }

    private func change(_ edit: ([CardItem]) -> [CardItem]) {
        pinned = edit(pinned)
        InspectorCardLayout.save(pinned, for: kind)
    }
}
