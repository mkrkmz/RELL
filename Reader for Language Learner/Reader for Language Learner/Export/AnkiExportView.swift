//
//  AnkiExportView.swift
//  Reader for Language Learner
//
//  Created by Codex on 13.02.2026.
//

import SwiftUI

struct AnkiExportView: View {
    let selectedText: String
    let mode: ExplainMode
    let domain: DomainPreference
    let outputs: [ModuleType: String]
    let pdfFilename: String?
    let pageNumber: Int?
    let contextSentence: String?

    @Environment(AnkiModulePreferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    @State private var exportResult: ExportResult?

    private enum ExportResult {
        case success
        case cancelled
    }

    var body: some View {
        @Bindable var prefs = prefs
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.tint)
                Text("Export to Anki")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Front preview
                    frontPreview

                    Divider()

                    // Module selection
                    moduleSelectionSection

                    Divider()

                    // Tags
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags")
                            .font(.subheadline.weight(.medium))
                        TextField("e.g. rell medical vocab", text: $prefs.tags)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                    }

                    // Source toggle
                    Toggle(isOn: $prefs.includeSource) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Include Source")
                                    .font(.subheadline)
                                if let filename = pdfFilename {
                                    Text(filename + (pageNumber.map { " (p. \($0))" } ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .padding()
            }

            Divider()

            // Footer with actions
            HStack {
                if let result = exportResult {
                    Label(
                        result == .success ? "Saved!" : "Cancelled",
                        systemImage: result == .success ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(result == .success ? .green : .secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save TSV") {
                    Task { await exportTSV() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedModules.isEmpty)
            }
            .padding()
        }
        .frame(width: 340, height: 580)
    }

    // MARK: - Front Preview

    private var frontPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Front (Card Question)")
                .font(.subheadline.weight(.medium))

            HStack(spacing: 8) {
                Image(systemName: "text.quote")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(selectedText)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.tail)
                if domain != .general {
                    Text("[\(domain.rawValue)]")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Module Selection

    private var moduleSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Back (Card Answer)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(availableCount) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(ModuleType.allCases) { module in
                moduleRow(module, isOn: prefs.binding(for: module))
            }
        }
    }

    private func moduleRow(_ module: ModuleType, isOn: Binding<Bool>) -> some View {
        let hasOutput = hasOutput(for: module)
        return Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Image(systemName: module.iconName)
                    .frame(width: 16)
                    .foregroundStyle(hasOutput ? .primary : .tertiary)
                Text(module.title)
                    .font(.callout)
                if !hasOutput {
                    Text("(no data)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!hasOutput)
    }

    // MARK: - Logic

    private var selectedModules: Set<ModuleType> {
        prefs.selectedModules(from: outputs)
    }

    private func hasOutput(for module: ModuleType) -> Bool {
        guard let output = outputs[module] else { return false }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var availableCount: Int {
        ModuleType.allCases.filter { hasOutput(for: $0) }.count
    }

    @MainActor
    private func exportTSV() async {
        let note = AnkiExporter.buildNote(
            selectedText: selectedText,
            mode: mode,
            domain: domain,
            selectedModules: selectedModules,
            outputs: outputs,
            includeSource: prefs.includeSource,
            pdfFilename: pdfFilename,
            pageNumber: pageNumber,
            contextSentence: contextSentence,
            tags: prefs.tags
        )
        let content = AnkiExporter.tsvDocument(from: note)
        let saved = await AnkiExporter.saveTSV(content: content)

        withAnimation(.easeInOut(duration: 0.2)) {
            exportResult = saved ? .success : .cancelled
        }

        if saved {
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
        }
    }
}
