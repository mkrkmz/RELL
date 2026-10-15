//
//  CustomModulesSection.swift
//  Reader for Language Learner
//
//  Settings ▸ Prompts ▸ Your Own Modules (Roadmap v18 Sprint 3, approved
//  mockup): the list, a new module from scratch or a template, and the
//  editor — name, icon, where it runs, the prompt with its placeholders,
//  the answer's language and length, the engine, where the text goes, and
//  a Try button. The Inspector's card and Edit Card… open it too.
//

import SwiftUI

struct CustomModulesSection: View {
    private var store: CustomModuleStore { .shared }
    @State private var editing: CustomModule?
    @State private var isNew = false

    /// Set by the Inspector before it opens Settings.
    @MainActor static var pending: CustomModuleEditorTarget?

    @MainActor
    static func requestEditor(_ target: CustomModuleEditorTarget) {
        pending = target
        NotificationCenter.default.post(name: .openCustomModuleEditor, object: nil)
    }

    var body: some View {
        Section {
            if store.modules.isEmpty {
                Text("Write a prompt of your own and it sits on the Inspector's card beside the built-in modules.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            ForEach(store.modules) { module in
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: module.icon)
                        .foregroundStyle(DS.Color.accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(module.name)
                        Text(summary(module))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    Spacer()
                    Text(isOnACard(module) ? String(localized: "on the card") : "•••")
                        .font(DS.Typography.caption2.weight(.semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                    Button("Edit…") { open(module, isNew: false) }
                        .controlSize(.small)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { open(module, isNew: false) }
            }
            HStack {
                Text("\(store.modules.count) of \(CustomModule.maxCount)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer()
                Menu("From Template") {
                    ForEach(CustomModule.templates, id: \.name) { template in
                        Button(template.name) { open(template, isNew: true) }
                    }
                }
                .fixedSize()
                .disabled(!store.canAdd)
                Button("New Module") {
                    open(CustomModule(name: "", icon: "sparkles", prompt: ""), isNew: true)
                }
                .disabled(!store.canAdd)
            }
        } header: {
            Text("Your Own Modules")
        } footer: {
            Text("Placeholders are filled in when you use the module. Your own modules don't take part in Fill Missing or the word-level estimate.")
                .foregroundStyle(DS.Color.textTertiary)
        }
        .sheet(item: $editing) { module in
            CustomModuleEditor(module: module, isNew: isNew) { editing = nil }
        }
        .onAppear(perform: takePending)
        .onReceive(NotificationCenter.default.publisher(for: .openCustomModuleEditor)) { _ in takePending() }
    }

    private func open(_ module: CustomModule, isNew: Bool) {
        var module = module
        if isNew { module.id = UUID() }
        self.isNew = isNew
        editing = module
    }

    private func takePending() {
        guard let target = Self.pending else { return }
        Self.pending = nil
        switch target {
        case .new:
            guard store.canAdd else { return }
            open(CustomModule(name: "", icon: "sparkles", prompt: ""), isNew: true)
        case .edit(let id):
            if let module = store.module(id) { open(module, isNew: false) }
        }
    }

    private func isOnACard(_ module: CustomModule) -> Bool {
        CardKind.allCases.contains { InspectorCardLayout.load($0).contains(.custom(module.id)) }
    }

    private func summary(_ module: CustomModule) -> String {
        let scope: String
        switch module.scope {
        case .word: scope = String(localized: "Word")
        case .sentence: scope = String(localized: "Sentence")
        case .both: scope = String(localized: "Word and sentence")
        }
        let language = module.answerIn == .native ? String(localized: "in your language") : String(localized: "in the language you study")
        let length = module.length == .short ? String(localized: "short") : String(localized: "long")
        let engine = module.engine == .apple ? String(localized: "Apple") : String(localized: "your provider")
        return [scope, language, length, engine].joined(separator: " · ")
    }
}

extension Notification.Name {
    nonisolated static let openCustomModuleEditor = Notification.Name("openCustomModuleEditor")
}

// MARK: - Editor

struct CustomModuleEditor: View {
    @State var module: CustomModule
    let isNew: Bool
    var onClose: () -> Void

    @State private var confirmDelete = false
    @State private var tryAnswer: String?
    @State private var tryFooter: AnswerFooter?
    @State private var isTrying = false

    private static let sampleWord = "ricochet"
    private static let sampleSentence = "The bullet ricocheted off the wall and struck the lamp."

    private var canSave: Bool {
        !module.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !module.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(isNew ? "New Module" : "Edit Module")
                .font(DS.Typography.headline)

            Form {
                TextField("Name", text: $module.name)
                LabeledContent("Icon") {
                    HStack(spacing: DS.Spacing.xxs) {
                        ForEach(CustomModule.icons, id: \.self) { icon in
                            Button { module.icon = icon } label: {
                                Label(icon, systemImage: icon)
                            }
                            .buttonStyle(.dsChipTile(isOn: module.icon == icon))
                            .labelStyle(.iconOnly)
                            .frame(width: 26, height: 26)
                            .accessibilityLabel(icon)
                        }
                    }
                }
                Picker("Runs on", selection: $module.scope) {
                    Text("Word").tag(CustomModule.Scope.word)
                    Text("Sentence").tag(CustomModule.Scope.sentence)
                    Text("Both").tag(CustomModule.Scope.both)
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Prompt")
                    TextEditor(text: $module.prompt)
                        .font(DS.Typography.monoCallout)
                        .frame(minHeight: 96, maxHeight: 140)
                        .onChange(of: module.prompt) { _, text in
                            if text.count > CustomModule.maxPromptLength {
                                module.prompt = String(text.prefix(CustomModule.maxPromptLength))
                            }
                        }
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(CustomPrompt.Placeholder.allCases, id: \.self) { placeholder in
                            Button(Self.insertable(placeholder)) {
                                module.prompt += (module.prompt.hasSuffix(" ") || module.prompt.isEmpty ? "" : " ")
                                    + Self.insertable(placeholder)
                            }
                            .buttonStyle(.dsChip(isOn: false))
                            .help("Insert at the end")
                        }
                    }
                    Text("\(module.prompt.count) / \(CustomModule.maxPromptLength)")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                Picker("Answer in", selection: $module.answerIn) {
                    Text("The language you study").tag(CustomModule.AnswerLanguage.target)
                    Text("Your language").tag(CustomModule.AnswerLanguage.native)
                }
                Picker("Length", selection: $module.length) {
                    Text("Short").tag(CustomModule.Length.short)
                    Text("Long").tag(CustomModule.Length.long)
                }
                .pickerStyle(.segmented)
                Picker("Engine", selection: $module.engine) {
                    Text("Your provider").tag(CustomModule.Engine.provider)
                    Text("Apple (on this Mac)").tag(CustomModule.Engine.apple)
                }
                .pickerStyle(.segmented)
                Label(destination, systemImage: "info.circle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .formStyle(.grouped)

            tryPanel

            HStack {
                if !isNew {
                    if confirmDelete {
                        Text("Delete this module?")
                            .font(DS.Typography.caption)
                        Button("Delete", role: .destructive) {
                            CustomModuleStore.shared.delete(module.id)
                            onClose()
                        }
                        Button("Keep") { confirmDelete = false }
                    } else {
                        Button("Delete…", role: .destructive) { confirmDelete = true }
                    }
                }
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if isNew { CustomModuleStore.shared.add(module) } else { CustomModuleStore.shared.update(module) }
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(DS.Spacing.xl)
        .frame(width: 560, height: 700)
    }

    private var tryPanel: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text("Try with “\(Self.sampleWord)”")
                    .font(DS.Typography.caption.weight(.semibold))
                Spacer()
                if isTrying { ProgressView().controlSize(.small) }
                Button("Try") { Task { await tryIt() } }
                    .disabled(isTrying || module.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let tryAnswer {
                ScrollView {
                    Text(InspectorView.markdown(tryAnswer))
                        .font(DS.Typography.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
                if let tryFooter {
                    AnswerFooterView(footer: tryFooter) {}
                }
            }
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.surfaceInset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    /// Where the module's text goes (approved: said in the editor).
    private var destination: String {
        if module.engine == .apple, AppleOnDevice.currentRoute(for: nil) == .appleOnDevice {
            return String(localized: "Answered on this Mac by Apple's model.")
        }
        let configuration = LLMConfiguration()
        let name = "\(configuration.providerType.localizedTitle) · \(configuration.model)"
        if configuration.runsOnThisMac {
            return String(localized: "The prompt, word and sentence go to \(name), on this Mac.")
        }
        return String(localized: "The prompt, word and sentence go to \(name) — a cloud service.")
    }

    private static func insertable(_ placeholder: CustomPrompt.Placeholder) -> String {
        // The editor's language decides which name it inserts; both work.
        Locale.current.language.languageCode?.identifier == "tr" ? placeholder.names[1] : placeholder.names[0]
    }

    private func tryIt() async {
        isTrying = true
        defer { isTrying = false }
        let native = Language.storedNative
        let target = Language.storedTarget
        let values: [CustomPrompt.Placeholder: String] = [
            .selection: Self.sampleWord, .sentence: Self.sampleSentence, .book: "",
            .native: native.nativeName, .target: target.nativeName,
            .level: CEFRLevel.storedLearnerLevel.rawValue,
        ]
        let useApple = module.engine == .apple && AppleOnDevice.currentRoute(for: nil) == .appleOnDevice
        let provider = LLMRequestLog.shared.recording(
            useApple ? AppleOnDevice.provider(for: nil) : LLMConfiguration().makeProvider(),
            origin: .custom, route: useApple ? .appleOnDevice : .configured
        )
        var answer = ""
        do {
            try await provider.stream(
                system: CustomPrompt.system(for: module, native: native, target: target,
                                            preamble: UserDefaults.standard.string(forKey: StorageKey.customSystemPreamble) ?? ""),
                user: CustomPrompt.render(module.prompt, values: values),
                temperature: 0.4, maxTokens: module.maxTokens, topP: 0.9
            ) { answer += $0 }
            tryAnswer = answer
        } catch {
            tryAnswer = LLMErrorMessage.userMessage(for: error)
        }
        tryFooter = LLMRequestLog.shared.record(provider.id).flatMap(AnswerFooter.make)
    }
}
