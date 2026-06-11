import SwiftUI
import Shared

public struct ModelSettingsView: View {
    @Binding private var settings: ModelSettingsViewState
    public var status: ModelLoadStatus
    public var onboarding: ModelOnboardingViewState
    public var availableModelIDs: [String]
    public var configStatus: ConfigStatusViewState
    public var effectiveSettings: ModelSettingsViewState?
    public var onLoad: @MainActor () -> Void
    public var onUnload: @MainActor () -> Void
    public var onCancel: @MainActor () -> Void
    public var onDismissOnboarding: @MainActor () -> Void
    public var onApplyRecommendations: @MainActor () -> Void
    public var onSaveHuggingFaceToken: @MainActor (String) -> Void
    public var onDeleteHuggingFaceToken: @MainActor () -> Void
    private let headerTitle: String?
    private let headerSubtitle: String
    private let embedsInParentScroll: Bool
    private let showsRuntimeControls: Bool
    private let showsResourceProfileControl: Bool
    private let showsDangerZone: Bool
    @State private var huggingFaceToken = ""
    @State private var showAdvanced = false

    public init(
        settings: Binding<ModelSettingsViewState>,
        status: ModelLoadStatus,
        onboarding: ModelOnboardingViewState = ModelOnboardingViewState(),
        availableModelIDs: [String] = [],
        configStatus: ConfigStatusViewState = ConfigStatusViewState(),
        effectiveSettings: ModelSettingsViewState? = nil,
        onLoad: @escaping @MainActor () -> Void,
        onUnload: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onDismissOnboarding: @escaping @MainActor () -> Void = {},
        onApplyRecommendations: @escaping @MainActor () -> Void = {},
        onSaveHuggingFaceToken: @escaping @MainActor (String) -> Void = { _ in },
        onDeleteHuggingFaceToken: @escaping @MainActor () -> Void = {},
        headerTitle: String? = "Providers",
        headerSubtitle: String = "Local MLX model setup and native tool-call compatibility.",
        embedsInParentScroll: Bool = false,
        showsRuntimeControls: Bool = true,
        showsResourceProfileControl: Bool = true,
        showsDangerZone: Bool = true
    ) {
        self._settings = settings
        self.status = status
        self.onboarding = onboarding
        self.availableModelIDs = availableModelIDs
        self.configStatus = configStatus
        self.effectiveSettings = effectiveSettings
        self.onLoad = onLoad
        self.onUnload = onUnload
        self.onCancel = onCancel
        self.onDismissOnboarding = onDismissOnboarding
        self.onApplyRecommendations = onApplyRecommendations
        self.onSaveHuggingFaceToken = onSaveHuggingFaceToken
        self.onDeleteHuggingFaceToken = onDeleteHuggingFaceToken
        self.headerTitle = headerTitle
        self.headerSubtitle = headerSubtitle
        self.embedsInParentScroll = embedsInParentScroll
        self.showsRuntimeControls = showsRuntimeControls
        self.showsResourceProfileControl = showsResourceProfileControl
        self.showsDangerZone = showsDangerZone
    }

    public var body: some View {
        if embedsInParentScroll {
            modelSettingsContent
        } else {
            ScrollView {
                modelSettingsContent
                    .padding(.horizontal, 96)
                    .padding(.vertical, 56)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .background(Theme.C.surface)
        }
    }

    private var modelSettingsContent: some View {
        let singleAgentMode = settings.usesSingleAgentMode()
        let validationSettings = effectiveSettings ?? settings
        return VStack(alignment: .leading, spacing: .space5) {
                if let headerTitle {
                    pageHeader(headerTitle, headerSubtitle)
                }
                if !onboarding.isDismissed {
                    onboardingSection
                }
                if configStatus.hasLoadedConfig {
                    ConfigStatusView(state: configStatus)
                }
                modelSection(singleAgentMode: singleAgentMode, validationSettings: validationSettings)
                if !validationSettings.validationErrors.isEmpty {
                    validationSection(validationSettings.validationErrors)
                }
                advancedSection(singleAgentMode: singleAgentMode)
                if showsDangerZone {
                    dangerSection
                }
        }
    }

    private var onboardingSection: some View {
        settingsCard(title: "Model Setup", symbolName: "cpu") {
            Text(onboarding.guidanceText)
                .font(.bodyS)
                .foregroundStyle(Theme.C.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            settingsDivider()
            ForEach(onboarding.recommendations) { recommendation in
                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.role.rawValue.capitalized)
                        .font(.bodyS.weight(.semibold))
                        .foregroundStyle(Theme.C.textPrimary)
                    Text(recommendation.modelID)
                        .font(.titleS)
                        .foregroundStyle(Theme.C.textPrimary)
                    Text("\(recommendation.purpose) \(recommendation.memoryNote)")
                        .font(.bodyS)
                        .foregroundStyle(Theme.C.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
                if recommendation.id != onboarding.recommendations.last?.id {
                    settingsDivider()
                }
            }
            HStack(spacing: .space2) {
                Button("Use Recommended Models", action: onApplyRecommendations)
                Button("Dismiss Guidance", action: onDismissOnboarding)
            }
            .font(.bodyS.weight(.semibold))
        }
    }

    private func modelSection(
        singleAgentMode: Bool,
        validationSettings: ModelSettingsViewState
    ) -> some View {
        settingsCard(title: "Model", symbolName: "cpu") {
            HStack {
                Text(status.label)
                    .font(.titleS)
                    .foregroundStyle(Theme.C.textSecondary)
                    .accessibilityLabel(AccessibilityCopy.modelStatusLabel(status))
                Spacer()
                if status.isBusy {
                    Button("Cancel", action: onCancel)
                }
                Button("Unload", action: onUnload)
                Button("Load", action: onLoad)
                    .buttonStyle(.borderedProminent)
                    .disabled(!validationSettings.validationErrors.isEmpty || status.isBusy)
            }
            settingsDivider()
            if !availableModelIDs.isEmpty {
                localModelPickerRow(
                    title: singleAgentMode ? "Downloaded chat model" : "Downloaded orchestrator model",
                    selection: $settings.orchestratorModelID)
            }
            controlRow(singleAgentMode ? "Chat model ID" : "Orchestrator model ID") {
                TextField("Model ID", text: $settings.orchestratorModelID)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                    .accessibilityLabel(singleAgentMode ? "Chat model identifier" : "Orchestrator model identifier")
            }
            controlRow(singleAgentMode ? "Chat quantization" : "Orchestrator quantization") {
                quantizationPicker(selection: $settings.orchestratorQuantization)
            }
            if singleAgentMode {
                Text("Small RAM mode uses one loaded chat model for every agent task. Utility and embedding side models are not loaded.")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func validationSection(_ errors: [String]) -> some View {
        settingsCard(title: "Validation", symbolName: "exclamationmark.triangle") {
            ForEach(errors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func advancedSection(singleAgentMode: Bool) -> some View {
        settingsCard(title: "Advanced", symbolName: "slider.horizontal.3") {
            DisclosureGroup("Advanced model roles and runtime controls", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: .space3) {
                    if singleAgentMode {
                        Text("Utility and embedding models are disabled while the resolved resource profile is Small RAM.")
                            .font(.bodyS)
                            .foregroundStyle(Theme.C.textSecondary)
                    } else {
                        if !availableModelIDs.isEmpty {
                            localModelPickerRow(title: "Downloaded utility model", selection: $settings.utilityModelID)
                        }
                        controlRow("Utility model ID") {
                            TextField("Utility model ID", text: $settings.utilityModelID)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 360)
                                .accessibilityLabel("Utility model identifier")
                        }
                        controlRow("Utility quantization") {
                            quantizationPicker(selection: $settings.utilityQuantization)
                        }
                        controlRow("Embedding model ID") {
                            TextField("Optional", text: $settings.embeddingsModelID)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 360)
                                .accessibilityLabel("Embedding model identifier")
                        }
                        controlRow("Embedding quantization") {
                            quantizationPicker(selection: $settings.embeddingsQuantization)
                        }
                        Text("Embeddings are optional and load only when an embedding model ID is set.")
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.textSecondary)
                    }
                    settingsDivider()
                    controlRow("Tool call format") {
                        Picker("", selection: Binding(
                            get: { settings.toolCallFormat?.rawValue ?? "auto" },
                            set: { settings.toolCallFormat = $0 == "auto" ? nil : ModelToolCallFormat(rawValue: $0) }
                        )) {
                            Text("Auto").tag("auto")
                            ForEach(ModelToolCallFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }
                    if showsRuntimeControls {
                        Stepper("Max tool iterations: \(settings.maxToolIterations)", value: $settings.maxToolIterations, in: 0...16)
                            .font(.bodyS)
                        Toggle("Persist local chat and prompt history", isOn: $settings.persistPromptHistory)
                            .font(.bodyS)
                        Text("History is stored locally in Application Support and remains excluded from diagnostics and recovery journals.")
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.textSecondary)
                        settingsDivider()
                    }
                    controlRow("Hugging Face token") {
                        SecureField("Token", text: $huggingFaceToken)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 360)
                    }
                    HStack(spacing: .space2) {
                        Button("Save Token") {
                            onSaveHuggingFaceToken(huggingFaceToken)
                            huggingFaceToken = ""
                        }
                        .disabled(huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Delete Token", action: onDeleteHuggingFaceToken)
                    }
                    .font(.bodyS.weight(.semibold))
                    Text("Tokens are stored only in Keychain.")
                        .font(.metaMono)
                        .foregroundStyle(Theme.C.textSecondary)
                    if showsResourceProfileControl {
                        settingsDivider()
                        controlRow("Resource profile") {
                            Picker("", selection: $settings.resourceProfile) {
                                ForEach(ResourceProfile.allCases, id: \.self) { profile in
                                    Text(profile.label).tag(profile)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }
                        Text("Automatic adapts budgets to the machine: strict on 8GB-class hardware, larger on high-memory Macs.")
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.textSecondary)
                        settingsDivider()
                        Toggle("Speculative decoding (draft model)", isOn: $settings.enableSpeculativeDecoding)
                            .font(.bodyS)
                        if settings.enableSpeculativeDecoding {
                            controlRow("Draft model ID") {
                                TextField("e.g. a small same-family MLX model", text: $settings.speculativeDraftModelID)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 320)
                            }
                            Text("Large RAM profile only. The draft must share the main model's tokenizer; incompatible drafts are rejected at load and chat falls back to normal decoding.")
                                .font(.metaMono)
                                .foregroundStyle(Theme.C.textSecondary)
                        }
                    }
                }
                .padding(.top, .space2)
            }
        }
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: .space3) {
            Label("Danger Zone", systemImage: "exclamationmark.shield")
                .font(.titleS)
                .foregroundStyle(Theme.C.danger)
            Toggle("Allow write tools", isOn: $settings.allowWrites)
                .font(.bodyS)
                .accessibilityHint("Enables the agent to modify files on disk")
            if let warning = settings.writeWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Allow trusted process and network tools", isOn: $settings.allowNetworkTools)
                .font(.bodyS)
                .accessibilityHint("Enables the agent to run processes and access the network")
            if let warning = settings.networkToolWarning {
                Label(warning, systemImage: "network.badge.shield.half.filled")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.C.danger.opacity(0.06), in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: .radiusSm, style: .continuous)
                .stroke(Theme.C.danger.opacity(0.4)))
    }

    private func pageHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: .space1) {
            Text(title)
                .font(.displayMd)
                .foregroundStyle(Theme.C.textPrimary)
            Text(subtitle)
                .font(.bodyS)
                .foregroundStyle(Theme.C.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        symbolName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: .space3) {
            Label(title, systemImage: symbolName)
                .font(.titleS)
                .foregroundStyle(Theme.C.textPrimary)
            content()
        }
        .padding(.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: .radiusSm)
    }

    private func controlRow<Control: View>(
        _ label: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: .space3) {
            Text(label)
                .font(.bodyS)
                .foregroundStyle(Theme.C.textPrimary)
            Spacer(minLength: .space3)
            control()
        }
    }

    private func settingsDivider() -> some View {
        Rectangle()
            .fill(Theme.C.border)
            .frame(height: 1)
    }

    private func localModelPickerRow(title: String, selection: Binding<String>) -> some View {
        controlRow(title) {
            Picker("", selection: selection) {
                Text("Manual").tag("")
                ForEach(localModelOptions(selection.wrappedValue), id: \.self) { id in
                    Text(id).tag(id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 360)
        }
    }

    private func quantizationPicker(selection: Binding<QuantizationLevel>) -> some View {
        Picker("", selection: selection) {
            ForEach(QuantizationLevel.allCases, id: \.self) { level in
                Text("q\(level.bitWidth)").tag(level)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 120)
    }

    private func localModelOptions(_ current: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let values = [current] + availableModelIDs
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}
