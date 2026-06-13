import Foundation
import Shared
import SwiftUI

public enum ComposerModelPickerModel {
    public static let suggestedDownloadModelIDs = ["mlx-community/gemma-2-2b-it-4bit"]

    public static func filteredModelIDs(_ modelIDs: [String], query: String) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return uniqueNonEmpty(modelIDs) }
        return uniqueNonEmpty(modelIDs).filter {
            $0.localizedCaseInsensitiveContains(trimmedQuery)
                || displayName(for: $0).localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    public static func downloadCandidate(from query: String, availableModels: [String]) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains("/") else { return nil }
        guard ModelCompatibility.unsupportedReason(for: trimmed) == nil else { return nil }
        return uniqueNonEmpty(availableModels).contains(trimmed) ? nil : trimmed
    }

    public static func downloadCandidateValidationMessage(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("/") else { return nil }
        return ModelCompatibility.unsupportedReason(for: trimmed)
    }

    public static func displayName(for id: String) -> String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    private static func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}

struct ComposerModelPickerSheet: View {
    var selectedModelID: String
    var modelStatus: ModelLoadStatus
    var availableModels: [String]
    var suggestedModels: [String]
    var onSelectModelID: @MainActor (String) -> Void
    var onOpenSettings: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""

    private var filteredAvailableModels: [String] {
        ComposerModelPickerModel.filteredModelIDs(availableModels, query: searchQuery)
    }

    private var searchDownloadCandidate: String? {
        ComposerModelPickerModel.downloadCandidate(from: searchQuery, availableModels: availableModels)
    }

    private var searchValidationMessage: String? {
        ComposerModelPickerModel.downloadCandidateValidationMessage(searchQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: .space3) {
                searchField
                modelList
            }
            .padding(.space4)
            Divider()
            footer
        }
        .frame(width: 520)
        .frame(minHeight: 460)
        .background(Theme.C.surface)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: .space2) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Select Model")
                    .font(.titleS)
                    .foregroundStyle(Theme.C.textPrimary)
                Text(modelStatus.isBusy ? "Model load is in progress." : "Search downloaded models or paste an MLX model ID.")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.controlGlyph)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, .space4)
        .padding(.vertical, .space3)
    }

    private var searchField: some View {
        HStack(spacing: .space2) {
            Image(systemName: "magnifyingglass")
                .font(.controlGlyph)
                .foregroundStyle(Theme.C.textTertiary)
            TextField("Search or paste owner/model", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.bodyS)
        }
        .padding(.horizontal, .space3)
        .frame(height: 36)
        .background(Theme.C.surface2, in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: .radiusSm, style: .continuous)
                .stroke(Theme.C.border, lineWidth: 1))
    }

    private var modelList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .space3) {
                if let searchValidationMessage {
                    validationMessage(searchValidationMessage)
                }
                modelSection(
                    title: "Downloaded",
                    emptyText: "No matching downloaded models.",
                    models: filteredAvailableModels,
                    symbolName: "cpu")
                if let searchDownloadCandidate {
                    downloadCandidateSection(searchDownloadCandidate)
                }
                let visibleSuggestions = suggestedModels.filter { !availableModels.contains($0) }
                if searchDownloadCandidate == nil, !visibleSuggestions.isEmpty {
                    modelSection(
                        title: "Download",
                        emptyText: "",
                        models: visibleSuggestions,
                        symbolName: "arrow.down.circle")
                }
            }
        }
        .frame(minHeight: 220, maxHeight: 280)
    }

    private func validationMessage(_ message: String) -> some View {
        Text(message)
            .font(.metaMono)
            .foregroundStyle(Theme.C.danger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, .space1)
    }

    private func downloadCandidateSection(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: .space1) {
            Text("DOWNLOAD")
                .font(.labelMono)
                .foregroundStyle(Theme.C.textTertiary)
                .padding(.horizontal, .space1)
            modelRow(id: id, symbolName: "arrow.down.circle", actionTitle: "Download and load")
        }
    }

    private func modelSection(
        title: String,
        emptyText: String,
        models: [String],
        symbolName: String
    ) -> some View {
        VStack(alignment: .leading, spacing: .space1) {
            Text(title.uppercased())
                .font(.labelMono)
                .foregroundStyle(Theme.C.textTertiary)
                .padding(.horizontal, .space1)
            if models.isEmpty {
                if !emptyText.isEmpty {
                    Text(emptyText)
                        .font(.metaMono)
                        .foregroundStyle(Theme.C.textSecondary)
                        .padding(.horizontal, .space1)
                        .padding(.vertical, .space2)
                }
            } else {
                ForEach(models, id: \.self) { id in
                    modelRow(id: id, symbolName: symbolName)
                }
            }
        }
    }

    private func modelRow(id: String, symbolName: String, actionTitle: String? = nil) -> some View {
        Button {
            selectModel(id)
        } label: {
            HStack(spacing: .space2) {
                Image(systemName: id == selectedModelID ? "checkmark.circle.fill" : symbolName)
                    .font(.controlGlyph)
                    .foregroundStyle(id == selectedModelID ? Theme.C.accent : Theme.C.textSecondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ComposerModelPickerModel.displayName(for: id))
                        .font(.bodyS.weight(.semibold))
                        .foregroundStyle(Theme.C.textPrimary)
                        .lineLimit(1)
                    Text(id)
                        .font(.metaMono)
                        .foregroundStyle(Theme.C.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if let actionTitle {
                    Text(actionTitle)
                        .font(.metaMono)
                        .foregroundStyle(Theme.C.accent)
                }
            }
            .padding(.horizontal, .space2)
            .frame(height: 48)
            .background(rowBackground(for: id), in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(modelStatus.isBusy)
        .help(modelStatus.isBusy ? "Wait for the current model operation to finish." : "Select \(id)")
    }

    private var footer: some View {
        HStack(spacing: .space2) {
            Button("Model & Context Settings...") {
                openSettings()
            }
            Spacer()
            Button("Close") {
                dismiss()
            }
        }
        .padding(.space4)
    }

    private func rowBackground(for id: String) -> Color {
        id == selectedModelID ? Theme.C.accent.opacity(0.12) : Theme.C.surface2.opacity(0.55)
    }

    @MainActor
    private func selectModel(_ id: String) {
        let selected = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty,
              ComposerModelPickerModel.downloadCandidateValidationMessage(selected) == nil,
              !modelStatus.isBusy
        else { return }
        dismiss()
        DispatchQueue.main.async {
            Task { @MainActor in
                onSelectModelID(selected)
            }
        }
    }

    @MainActor
    private func openSettings() {
        dismiss()
        DispatchQueue.main.async {
            Task { @MainActor in
                onOpenSettings()
            }
        }
    }
}
