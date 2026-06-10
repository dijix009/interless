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
    @AppStorage("appearance.mode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    // Live chat-surface preferences. Shared by key with WorkspaceView, which
    // feeds them into the chat surface. Defaults match ChatSurfacePreferences().
    @AppStorage("chat.showReasoningTraces") private var showReasoningTraces = true
    @AppStorage("chat.wideChatLayout") private var wideChatLayout = false
    @AppStorage("chat.userMessageRendering") private var userMessageRenderingRaw = UserMessageRenderingMode.plainText.rawValue
    @AppStorage("chat.diffLayout") private var diffLayoutRaw = ChatDiffLayoutMode.inline.rawValue

    private var userMessageRendering: UserMessageRenderingMode {
        UserMessageRenderingMode(rawValue: userMessageRenderingRaw) ?? .plainText
    }

    private var diffLayout: ChatDiffLayoutMode {
        ChatDiffLayoutMode(rawValue: diffLayoutRaw) ?? .inline
    }

    private var appearanceModeBinding: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue })
    }

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
            .padding(.vertical, .space2)
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
            settingsCard(title: "Theme", symbolName: "circle.lefthalf.filled") {
                VStack(alignment: .leading, spacing: .space2) {
                    Text("Interless is designed dark-first; light mode stays clean and quiet.")
                        .font(.caption)
                        .foregroundStyle(Theme.C.textTertiary)
                    SegmentedToggle(
                        selection: appearanceModeBinding,
                        options: AppearanceMode.allCases.map { ($0, $0.label) })
                        .frame(maxWidth: 280)
                        .frame(height: 28)
                }
            }
            settingsCard(title: "Identity", symbolName: "paintpalette") {
                settingsRow("Accent", value: "Amber (brand) + green phosphor (live)")
                settingsRow("Typography", value: "SF Pro + SF Mono")
                settingsRow("Density", value: "Comfortable")
            }
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Chat", "Rendering, tools, and diff presentation for the native chat surface.")
            HStack(alignment: .top, spacing: .space4) {
                settingsCard(title: "User Message Rendering", symbolName: "text.alignleft") {
                    radioRow("Markdown", selected: userMessageRendering == .markdown) {
                        userMessageRenderingRaw = UserMessageRenderingMode.markdown.rawValue
                    }
                    radioRow("Plain text", selected: userMessageRendering == .plainText) {
                        userMessageRenderingRaw = UserMessageRenderingMode.plainText.rawValue
                    }
                }
                settingsCard(title: "Diff Layout", symbolName: "plus.forwardslash.minus") {
                    radioRow("Dynamic", selected: diffLayout == .dynamic) {
                        diffLayoutRaw = ChatDiffLayoutMode.dynamic.rawValue
                    }
                    radioRow("Always inline", selected: diffLayout == .inline) {
                        diffLayoutRaw = ChatDiffLayoutMode.inline.rawValue
                    }
                    radioRow("Always side-by-side", selected: diffLayout == .sideBySide) {
                        diffLayoutRaw = ChatDiffLayoutMode.sideBySide.rawValue
                    }
                }
            }
            settingsCard(title: "Message Stream", symbolName: "dot.radiowaves.left.and.right") {
                settingsRow("Transport", value: "Native AsyncSequence")
            }
            settingsCard(title: "Chat Behavior", symbolName: "sparkles") {
                Toggle("Show reasoning traces", isOn: $showReasoningTraces)
                Text("Display the model's reasoning effort label on assistant messages.")
                    .font(.caption)
                    .foregroundStyle(Theme.C.textTertiary)
                Toggle("Wide chat layout", isOn: $wideChatLayout)
                Text("Widen the conversation column for long code and diffs.")
                    .font(.caption)
                    .foregroundStyle(Theme.C.textTertiary)
            }
        }
    }

    private var modelContextSection: some View {
        VStack(alignment: .leading, spacing: .space4) {
            pageHeader("Model & Context", "Local MLX model setup, generation limits, and context budgets.")
            Picker("Configure", selection: $selectedModelContextMode) {
                ForEach(ModelContextMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360, alignment: .leading)
            settingsCard(title: "Resource Profile", symbolName: "memorychip") {
                Picker("Resource profile", selection: $settings.resourceProfile) {
                    ForEach(ResourceProfile.allCases, id: \.self) { profile in
                        Text(profile.label).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
            }
            settingsCard(title: "Conversation Context", symbolName: "text.bubble") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(selectedModelContextMode.title) strategy")
                            .font(.bodyS)
                            .foregroundStyle(Theme.C.textPrimary)
                        Text(contextModeDescription(for: selectedModelContextMode))
                            .font(.caption)
                            .foregroundStyle(Theme.C.textTertiary)
                    }
                    Spacer(minLength: .space3)
                    Picker("Context strategy", selection: contextModeBinding(for: selectedModelContextMode)) {
                        ForEach(ConversationContextMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                settingsRow("Effective mode", value: effectiveConversationContextLabel(isPlainChat: selectedModelContextMode.isPlainChat))
                Text("Simple is deterministic and only sends recent history for clear follow-ups. Smart ranks prior turns with local embeddings and falls back to Simple when embeddings are unavailable.")
                    .font(.caption)
                    .foregroundStyle(Theme.C.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            settingsCard(title: "Run Limits", symbolName: "slider.horizontal.3") {
                steppedTokenSlider(
                    "Max answer tokens",
                    value: answerTokenBinding(for: selectedModelContextMode),
                    range: 0...ModelContextSettingsViewState.maximumAnswerTokens,
                    step: ModelContextSettingsViewState.answerTokenStep,
                    steps: ModelContextSettingsViewState.classicAnswerTokenSteps,
                    snapDistance: ModelContextSettingsViewState.answerTokenSnapDistance,
                    detail: selectedModelContextMode == .chat
                        ? "Plain chat conversations."
                        : "Workspace/code agent sessions.")
                steppedTokenSlider(
                    "Max context window",
                    value: contextWindowBinding(for: selectedModelContextMode),
                    range: 0...ModelContextSettingsViewState.maximumContextWindowTokens,
                    step: ModelContextSettingsViewState.contextTokenStep,
                    steps: ModelContextSettingsViewState.classicContextWindowTokenSteps,
                    snapDistance: ModelContextSettingsViewState.contextWindowTokenSnapDistance,
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

    /// Interactive radio: keyboard/VoiceOver-operable, announces selected state.
    private func radioRow(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            radioRow(label, selected: selected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
        steps: [Int],
        snapDistance: Int,
        detail: String
    ) -> some View {
        return VStack(alignment: .leading, spacing: .space1) {
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
                    set: { newValue in
                        let rounded = Int(newValue.rounded())
                        value.wrappedValue = ModelContextSettingsViewState.snappedTokenValue(
                            rounded,
                            in: steps,
                            snapDistance: snapDistance)
                    }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step))
            .accessibilityValue(ModelContextSettingsViewState.displayTokenValue(value.wrappedValue))
            tokenSnapMarks(steps: steps, range: range)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.C.textTertiary)
        }
    }

    private func tokenSnapMarks(steps: [Int], range: ClosedRange<Int>) -> some View {
        Canvas { context, size in
            let span = max(range.upperBound - range.lowerBound, 1)
            let width = max(size.width, 1)
            for step in steps {
                let clamped = min(max(step, range.lowerBound), range.upperBound)
                let x = width * CGFloat(clamped - range.lowerBound) / CGFloat(span)
                let labelX = min(max(x, 12), width - 12)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 0))
                tick.addLine(to: CGPoint(x: x, y: 5))
                context.stroke(tick, with: .color(Theme.C.border), lineWidth: 1)
                context.draw(
                    Text(compactTokenStepLabel(step))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.C.textTertiary),
                    at: CGPoint(x: labelX, y: 14))
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    private func compactTokenStepLabel(_ value: Int) -> String {
        guard value > 0 else { return "Auto" }
        if value >= 1_024 {
            return "\(value / 1_024)k"
        }
        return "\(value)"
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

    private func contextModeBinding(for mode: ModelContextMode) -> Binding<ConversationContextMode> {
        Binding(
            get: {
                switch mode {
                case .chat:
                    return state.modelContextSettings.plainChatContextMode
                case .code:
                    return state.modelContextSettings.codeChatContextMode
                }
            },
            set: { newValue in
                var updated = state.modelContextSettings
                switch mode {
                case .chat:
                    updated.plainChatContextMode = newValue
                case .code:
                    updated.codeChatContextMode = newValue
                }
                onUpdateModelContextSettings(updated.normalized())
            })
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
        let role: ModelRole = settings.usesSingleAgentMode() ? .orchestrator : (isPlainChat ? .utility : .orchestrator)
        let profileCap = budget.contextTokenBudget(for: role)
            ?? budget.contextTokenBudget(for: .orchestrator)
        let effective = [
            state.modelContextSettings.contextTokenBudgetOverride(isPlainChat: isPlainChat),
            profileCap,
        ].compactMap(\.self).min()
        guard let effective else { return "Automatic" }
        return ModelContextSettingsViewState.displayTokenValue(effective)
    }

    private func effectiveConversationContextLabel(isPlainChat: Bool) -> String {
        let mode = state.modelContextSettings.conversationContextMode(isPlainChat: isPlainChat)
        guard mode == .smart else { return EffectiveConversationContextMode.simple.label }
        let embeddingConfigured = !settings.embeddingsModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let likelyLoaded = embeddingConfigured && state.modelStatus == .loaded && !settings.usesSingleAgentMode()
        return likelyLoaded
            ? EffectiveConversationContextMode.smart.label
            : EffectiveConversationContextMode.smartDegraded.label
    }

    private func contextModeDescription(for mode: ModelContextMode) -> String {
        switch mode {
        case .chat:
            return "Plain chat defaults to Simple to avoid pulling old topics into new messages."
        case .code:
            return "Code sessions default to Smart for relevant project and task follow-ups."
        }
    }
}
