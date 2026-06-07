import Shared
import SwiftUI

private enum ModelContextMode: String, CaseIterable, Identifiable {
    case chat
    case code

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .code: return "Code"
        }
    }

    var isPlainChat: Bool { self == .chat }
}

public struct SettingsHubView: View {
    @Binding private var settings: ModelSettingsViewState
    public var state: WorkspaceViewState
    public var onLoadModels: @MainActor () -> Void
    public var onUnloadModels: @MainActor () -> Void
    public var onCancelModelLoad: @MainActor () -> Void
    public var onDismissOnboarding: @MainActor () -> Void
    public var onApplyRecommendations: @MainActor () -> Void
    public var onSaveHuggingFaceToken: @MainActor (String) -> Void
    public var onDeleteHuggingFaceToken: @MainActor () -> Void
    public var onOpenHealth: @MainActor () -> Void
    public var onExportDiagnostics: @MainActor () -> Void
    public var onUpdateModelContextSettings: @MainActor (ModelContextSettingsViewState) -> Void
    @State private var selectedSection: SettingsHubSection = .chat
    @State private var selectedModelContextMode: ModelContextMode = .chat

    public init(
        settings: Binding<ModelSettingsViewState>,
        state: WorkspaceViewState,
        onLoadModels: @escaping @MainActor () -> Void,
        onUnloadModels: @escaping @MainActor () -> Void,
        onCancelModelLoad: @escaping @MainActor () -> Void,
        onDismissOnboarding: @escaping @MainActor () -> Void,
        onApplyRecommendations: @escaping @MainActor () -> Void,
        onSaveHuggingFaceToken: @escaping @MainActor (String) -> Void,
        onDeleteHuggingFaceToken: @escaping @MainActor () -> Void,
        onOpenHealth: @escaping @MainActor () -> Void,
        onExportDiagnostics: @escaping @MainActor () -> Void,
        onUpdateModelContextSettings: @escaping @MainActor (ModelContextSettingsViewState) -> Void
    ) {
        self._settings = settings
        self.state = state
        self.onLoadModels = onLoadModels
        self.onUnloadModels = onUnloadModels
        self.onCancelModelLoad = onCancelModelLoad
        self.onDismissOnboarding = onDismissOnboarding
        self.onApplyRecommendations = onApplyRecommendations
        self.onSaveHuggingFaceToken = onSaveHuggingFaceToken
        self.onDeleteHuggingFaceToken = onDeleteHuggingFaceToken
        self.onOpenHealth = onOpenHealth
        self.onExportDiagnostics = onExportDiagnostics
        self.onUpdateModelContextSettings = onUpdateModelContextSettings
    }

    public var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 230)
            Divider()
            detail(for: selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.C.surface)
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(SettingsHubSection.visibleCases) { section in
                        settingsSidebarButton(section)
                    }
                }
                .padding(.space3)
            }
            Divider()
            Button(action: onExportDiagnostics) {
                Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                    .font(.bodyS.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .space3)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.C.textSecondary)
        }
        .background(Theme.C.sidebar)
    }

    private func settingsSidebarButton(_ section: SettingsHubSection) -> some View {
        let availability = availability(for: section)
        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: .space2) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(section.title)
                    .font(.bodyS.weight(selectedSection == section ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !availability.isAvailable {
                    Text("soon")
                        .font(.metaMono)
                        .foregroundStyle(Theme.C.accent)
                }
            }
            .foregroundStyle(selectedSection == section ? Theme.C.textPrimary : Theme.C.textSecondary)
            .padding(.horizontal, .space2)
            .padding(.vertical, 8)
            .background(
                selectedSection == section ? Theme.C.surface3 : Color.clear,
                in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!availability.isAvailable)
        .help(availability.reason ?? section.title)
        .accessibilityLabel(section.title)
    }

    private func availability(for section: SettingsHubSection) -> SettingsSectionAvailability {
        if let explicit = state.settingsSectionAvailability.first(where: { $0.sectionID == section.id }) {
            return explicit
        }
        switch section {
        case .notifications, .magicPrompts, .skillsCatalog:
            return SettingsSectionAvailability(
                sectionID: section.id,
                isAvailable: false,
                reason: "Native settings surface is not implemented yet.")
        default:
            return SettingsSectionAvailability(sectionID: section.id)
        }
    }

    @ViewBuilder
    private func detail(for section: SettingsHubSection) -> some View {
        switch section {
        case .appearance:
            settingsScroll { appearanceSection }
        case .chat:
            settingsScroll { chatSection }
        case .modelContext:
            settingsScroll { modelContextSection }
        case .notifications:
            settingsScroll { disabledSection(section) }
        case .sessions:
            settingsScroll { sessionsSection }
        case .shortcuts:
            settingsScroll { shortcutsSection }
        case .git:
            settingsScroll { gitSection }
        case .magicPrompts:
            settingsScroll { disabledSection(section) }
        case .projects:
            settingsScroll { projectsSection }
        case .agents:
            settingsScroll { agentsSection }
        case .behavior:
            settingsScroll { behaviorSection }
        case .commands:
            settingsScroll { commandsSection }
        case .mcp:
            settingsScroll { mcpSection }
        case .providers:
            ModelSettingsView(
                settings: $settings,
                status: state.modelStatus,
                onboarding: state.modelOnboarding,
                availableModelIDs: state.availableChatModelIDs,
                configStatus: state.configStatus,
                effectiveSettings: state.effectiveSettings,
                onLoad: onLoadModels,
                onUnload: onUnloadModels,
                onCancel: onCancelModelLoad,
                onDismissOnboarding: onDismissOnboarding,
                onApplyRecommendations: onApplyRecommendations,
                onSaveHuggingFaceToken: onSaveHuggingFaceToken,
                onDeleteHuggingFaceToken: onDeleteHuggingFaceToken)
        case .usage:
            settingsScroll { usageSection }
        case .skills:
            settingsScroll { skillsSection }
        case .skillsCatalog:
            settingsScroll { disabledSection(section) }
        }
    }

    private func settingsScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .space5) {
                content()
            }
            .padding(.horizontal, 96)
            .padding(.vertical, 56)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Appearance", "Native macOS density, typography, and surface defaults.")
            settingsCard(title: "Workspace Density", symbolName: "rectangle.3.group") {
                settingsRow("Theme", value: "System")
                settingsRow("Density", value: "Compact")
                settingsRow("Typography", value: "SF Pro + SF Mono")
                settingsRow("Accent", value: "Warm orange")
            }
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Chat", "Rendering, tools, and diff presentation for the native chat surface.")
            VStack(alignment: .leading, spacing: .space3) {
                Text("Chat Render Mode")
                    .font(.titleS)
                HStack(spacing: .space3) {
                    renderModeCard("Sorted", isSelected: state.chatSurfacePreferences.renderMode == .sorted)
                    renderModeCard("Live", isSelected: state.chatSurfacePreferences.renderMode == .live)
                }
            }
            settingsCard(title: "Message Stream", symbolName: "dot.radiowaves.left.and.right") {
                settingsRow("Transport", value: "Native AsyncSequence")
                Toggle("Show Bash tools opened by default", isOn: .constant(state.chatSurfacePreferences.expandBashToolsByDefault))
                    .disabled(true)
                Toggle("Show Edit tools opened by default", isOn: .constant(state.chatSurfacePreferences.expandEditToolsByDefault))
                    .disabled(true)
            }
            HStack(alignment: .top, spacing: .space4) {
                settingsCard(title: "User Message Rendering", symbolName: "text.alignleft") {
                    radioRow("Markdown", selected: state.chatSurfacePreferences.userMessageRendering == .markdown)
                    radioRow("Plain text", selected: state.chatSurfacePreferences.userMessageRendering == .plainText)
                }
                settingsCard(title: "Diff Layout", symbolName: "plus.forwardslash.minus") {
                    radioRow("Dynamic", selected: state.chatSurfacePreferences.diffLayout == .dynamic)
                    radioRow("Always inline", selected: state.chatSurfacePreferences.diffLayout == .inline)
                    radioRow("Always side-by-side", selected: state.chatSurfacePreferences.diffLayout == .sideBySide)
                }
            }
            settingsCard(title: "Chat Behavior", symbolName: "sparkles") {
                Toggle("Show Reasoning Traces", isOn: .constant(state.chatSurfacePreferences.showReasoningTraces))
                    .disabled(true)
                Toggle("Sticky User Header", isOn: .constant(state.chatSurfacePreferences.stickyUserHeader))
                    .disabled(true)
                Toggle("Wide Chat Layout", isOn: .constant(state.chatSurfacePreferences.wideChatLayout))
                    .disabled(true)
            }
        }
    }

    private var modelContextSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Model & Context", "Local MLX model setup, generation limits, and context budgets.")
            settingsCard(title: "Resource Profile", symbolName: "memorychip") {
                Picker("Resource profile", selection: $settings.resourceProfile) {
                    ForEach(ResourceProfile.allCases, id: \.self) { profile in
                        Text(profile.label).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
            }
            settingsCard(title: "Run Limits", symbolName: "slider.horizontal.3") {
                Picker("Mode", selection: $selectedModelContextMode) {
                    ForEach(ModelContextMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                steppedTokenSlider(
                    "Max answer tokens",
                    value: answerTokenBinding(for: selectedModelContextMode),
                    range: 0...ModelContextSettingsViewState.maximumAnswerTokens,
                    step: ModelContextSettingsViewState.answerTokenStep,
                    detail: selectedModelContextMode == .chat
                        ? "Plain chat conversations."
                        : "Workspace/code agent sessions.")
                steppedTokenSlider(
                    "Max context window",
                    value: contextWindowBinding(for: selectedModelContextMode),
                    range: 0...ModelContextSettingsViewState.maximumContextWindowTokens,
                    step: ModelContextSettingsViewState.contextTokenStep,
                    detail: "The active resource profile still applies as a safety cap.")
                settingsRow("Effective context cap", value: effectiveContextCapLabel(isPlainChat: selectedModelContextMode.isPlainChat))
            }
            ModelSettingsView(
                settings: $settings,
                status: state.modelStatus,
                onboarding: state.modelOnboarding,
                availableModelIDs: state.availableChatModelIDs,
                configStatus: state.configStatus,
                effectiveSettings: state.effectiveSettings,
                onLoad: onLoadModels,
                onUnload: onUnloadModels,
                onCancel: onCancelModelLoad,
                onDismissOnboarding: onDismissOnboarding,
                onApplyRecommendations: onApplyRecommendations,
                onSaveHuggingFaceToken: onSaveHuggingFaceToken,
                onDeleteHuggingFaceToken: onDeleteHuggingFaceToken,
                headerTitle: nil,
                embedsInParentScroll: true,
                showsRuntimeControls: false,
                showsResourceProfileControl: false,
                showsDangerZone: false)
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Sessions", "Durable native sessions and local chat history.")
            settingsCard(title: "History", symbolName: "clock.arrow.circlepath") {
                Toggle("Persist local chat and prompt history", isOn: $settings.persistPromptHistory)
                settingsRow("Workspace sessions", value: "\(state.chatThreads.count)")
                settingsRow("Plain chats", value: "\(state.globalChatThreads.count)")
                settingsRow("Timeline events", value: "\(state.sessionTimelineItems.count)")
            }
        }
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Agents", "Configured native agents and routing surfaces.")
            settingsCard(title: "Available Agents", symbolName: "person.2") {
                if state.agentSwitcherItems.isEmpty {
                    settingsRow("Configured agents", value: "\(state.configStatus.agentCount)")
                } else {
                    ForEach(state.agentSwitcherItems) { agent in
                        settingsRow(agent.title, value: agent.subtitle.isEmpty ? (agent.isEnabled ? "Enabled" : "Disabled") : agent.subtitle)
                    }
                }
            }
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Behavior", "Tool safety, permissions, and iteration limits.")
            settingsCard(title: "Permissions", symbolName: "lock.shield") {
                Toggle("Allow write tools", isOn: $settings.allowWrites)
                Toggle("Allow trusted process and network tools", isOn: $settings.allowNetworkTools)
                Stepper("Max tool iterations: \(settings.maxToolIterations)", value: $settings.maxToolIterations, in: 0...16)
                settingsRow("Policy rules", value: "\(state.configStatus.policyCount)")
                if let prompt = state.permissionPrompt {
                    settingsRow("Pending permission", value: prompt.toolName)
                }
            }
        }
    }

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("MCP", "Native MCP configuration and trust status.")
            settingsCard(title: "Servers", symbolName: "point.3.connected.trianglepath.dotted") {
                settingsRow("Configured servers", value: "\(state.configStatus.mcpServerCount)")
                settingsRow("Trusted network", value: state.mcpSettings.trustedNetworkEnabled ? "Enabled" : "Disabled")
            }
            MCPSettingsView(state: state.mcpSettings)
        }
    }

    private var commandsSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Commands", "Native snippets and extension records.")
            settingsCard(title: "Command Surface", symbolName: "terminal") {
                settingsRow("Config extensions", value: "\(state.configStatus.extensionCount)")
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Projects", "Workspace metadata and local project history.")
            settingsCard(title: "Current Workspace", symbolName: "folder") {
                settingsRow("Path", value: state.workspacePath ?? "None")
                settingsRow("Indexed files", value: "\(state.fileTreeRows.count)")
                settingsRow("History", value: "\(state.workspaceHistory.count)")
            }
        }
    }

    private var gitSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Git", "Native status, diff, and commit presentation.")
            settingsCard(title: "Repository", symbolName: "point.3.filled.connected.trianglepath.dotted") {
                settingsRow("Status", value: state.gitSummary)
                settingsRow("Changed files", value: "\(state.inspectorGit.changedFiles.count)")
                settingsRow("Diff files", value: "\(state.inspectorDiff.fileCount)")
            }
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Shortcuts", "Native macOS commands and focus routing.")
            settingsCard(title: "Keyboard", symbolName: "keyboard") {
                settingsRow("Focus Search", value: "Toolbar / sidebar search")
                settingsRow("Focus Chat", value: "Chat composer")
                settingsRow("Toggle Sidebar", value: "Control-Command-S")
                settingsRow("Open Settings", value: "Command-,")
                settingsRow("Cancel", value: "Escape")
            }
        }
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Usage", "Health, diagnostics, and local resource status.")
            settingsCard(title: "Health", symbolName: "waveform.path.ecg") {
                settingsRow("Active tasks", value: "\(state.health.activeTasks.count)")
                settingsRow("Recent failures", value: "\(state.health.recentFailures.count)")
                settingsRow("Recovery", value: state.health.recoverySummary)
                HStack {
                    Button("Open Health", action: onOpenHealth)
                    Button("Export Diagnostics", action: onExportDiagnostics)
                }
            }
        }
    }

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Skills", "Declarative native skills discovered from configuration.")
            settingsCard(title: "Installed Skills", symbolName: "book") {
                settingsRow("Extensions", value: "\(state.configStatus.extensionCount)")
                settingsRow("Status", value: "Native catalog")
            }
        }
    }

    private func disabledSection(_ section: SettingsHubSection) -> some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader(section.title, availability(for: section).reason ?? "This native surface is not implemented yet.")
            settingsCard(title: "Unavailable", symbolName: section.symbolName) {
                settingsRow("State", value: "Deferred native surface")
            }
        }
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

    private func renderModeCard(_ title: String, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: .space3) {
            Text(title)
                .font(.titleS)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().frame(height: 6)
                Capsule().frame(width: 180, height: 6)
                Capsule().frame(width: 140, height: 6)
            }
            .foregroundStyle(Theme.C.textTertiary.opacity(0.45))
            .padding(.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.C.surface3.opacity(0.45), in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        }
        .foregroundStyle(isSelected ? Theme.C.textPrimary : Theme.C.textSecondary)
        .padding(.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.C.surface2, in: RoundedRectangle(cornerRadius: .radiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: .radiusSm, style: .continuous)
                .stroke(isSelected ? Theme.C.accent : Theme.C.border, lineWidth: 1.4)
        }
    }

    private func radioRow(_ label: String, selected: Bool) -> some View {
        HStack(spacing: .space2) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selected ? Theme.C.accent : Theme.C.textTertiary)
            Text(label)
                .font(.bodyS)
                .foregroundStyle(selected ? Theme.C.textPrimary : Theme.C.textSecondary)
            Spacer(minLength: 0)
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

    private func settingsRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.bodyS)
                .foregroundStyle(Theme.C.textPrimary)
            Spacer(minLength: .space3)
            Text(value)
                .font(.metaMono)
                .foregroundStyle(Theme.C.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
    }

    private func steppedTokenSlider(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: .space1) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.textPrimary)
                Spacer(minLength: .space3)
                Text(ModelContextSettingsViewState.displayTokenValue(value.wrappedValue))
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step))
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.C.textTertiary)
        }
    }

    private func answerTokenBinding(for mode: ModelContextMode) -> Binding<Int> {
        switch mode {
        case .chat:
            return modelContextBinding(\.plainChatMaxAnswerTokens)
        case .code:
            return modelContextBinding(\.codeChatMaxAnswerTokens)
        }
    }

    private func contextWindowBinding(for mode: ModelContextMode) -> Binding<Int> {
        switch mode {
        case .chat:
            return modelContextBinding(\.plainChatMaxContextWindowTokens)
        case .code:
            return modelContextBinding(\.codeChatMaxContextWindowTokens)
        }
    }

    private func modelContextBinding(_ keyPath: WritableKeyPath<ModelContextSettingsViewState, Int>) -> Binding<Int> {
        Binding(
            get: { state.modelContextSettings[keyPath: keyPath] },
            set: { newValue in
                var updated = state.modelContextSettings
                updated[keyPath: keyPath] = newValue
                onUpdateModelContextSettings(updated.normalized())
            })
    }

    private func effectiveContextCapLabel(isPlainChat: Bool) -> String {
        let budget = ResourceBudget.resolved(for: settings.resourceProfile)
        let role: ModelRole = settings.usesSingleAgentMode() ? .orchestrator : .utility
        let profileCap = budget.contextTokenBudget(for: role)
            ?? budget.contextTokenBudget(for: .orchestrator)
        let effective = [
            state.modelContextSettings.contextTokenBudgetOverride(isPlainChat: isPlainChat),
            profileCap,
        ].compactMap(\.self).min()
        guard let effective else { return "Automatic" }
        return ModelContextSettingsViewState.displayTokenValue(effective)
    }
}
