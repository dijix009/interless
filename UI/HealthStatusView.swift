import SwiftUI

public struct HealthStatusView: View {
    public var state: HealthStatusViewState
    public var onRetryRecovery: @MainActor (UUID) -> Void
    public var onDismissRecovery: @MainActor (UUID) -> Void
    public var onClearRecovery: @MainActor () -> Void
    public var onExportDiagnostics: @MainActor () -> Void
    @State private var selectedSection: HealthPanelSection = .overview

    public init(
        state: HealthStatusViewState,
        onRetryRecovery: @escaping @MainActor (UUID) -> Void = { _ in },
        onDismissRecovery: @escaping @MainActor (UUID) -> Void = { _ in },
        onClearRecovery: @escaping @MainActor () -> Void = {},
        onExportDiagnostics: @escaping @MainActor () -> Void = {}
    ) {
        self.state = state
        self.onRetryRecovery = onRetryRecovery
        self.onDismissRecovery = onDismissRecovery
        self.onClearRecovery = onClearRecovery
        self.onExportDiagnostics = onExportDiagnostics
    }

    public var body: some View {
        HStack(spacing: 0) {
            healthSidebar
                .frame(width: 230)
            Divider()
            detail(for: selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.C.surface)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var healthSidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(HealthPanelSection.allCases) { section in
                        healthSidebarButton(section)
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

    private func healthSidebarButton(_ section: HealthPanelSection) -> some View {
        Button {
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
                if let badge = badge(for: section) {
                    Text(badge)
                        .font(.metaMono)
                        .foregroundStyle(Theme.C.textTertiary)
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
        .accessibilityLabel(section.title)
    }

    private func badge(for section: HealthPanelSection) -> String? {
        switch section {
        case .overview:
            return nil
        case .recovery:
            return state.recoveryItems.isEmpty ? nil : "\(state.recoveryItems.count)"
        case .diagnostics:
            return state.diagnosticsExport == nil ? nil : "ready"
        case .events:
            return state.recentEvents.isEmpty ? nil : "\(state.recentEvents.count)"
        case .tasks:
            return state.activeTasks.isEmpty ? "\(state.recentTasks.count)" : "\(state.activeTasks.count)"
        case .metrics:
            return state.metricSummaries.isEmpty ? nil : "\(state.metricSummaries.count)"
        }
    }

    @ViewBuilder
    private func detail(for section: HealthPanelSection) -> some View {
        switch section {
        case .overview:
            healthScroll {
                pageHeader("Health", "Runtime tasks, recovery state, durable event replay, and local diagnostics.")
                overviewSection
                eventSection
            }
        case .recovery:
            healthScroll {
                pageHeader("Recovery", "Acknowledged and retryable recovery records.")
                recoverySection
            }
        case .diagnostics:
            healthScroll {
                pageHeader("Diagnostics", "Redacted local bundles and durable replay cursors.")
                diagnosticsSection
                durableCursorSection
            }
        case .events:
            healthScroll {
                pageHeader("Events", "Recent presentation-safe app events.")
                eventSection
            }
        case .tasks:
            healthScroll {
                pageHeader("Tasks", "Active and recent background work.")
                activeTaskSection
                recentTaskSection
            }
        case .metrics:
            healthScroll {
                pageHeader("Metrics", "Memory and operation timing snapshots.")
                metricSection
            }
        }
    }

    private func healthScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .space5) {
                content()
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 44)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
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

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: .space3) {
            HStack(alignment: .top, spacing: .space3) {
                summaryCard("Active Tasks", value: "\(state.activeTasks.count)", symbolName: "clock")
                summaryCard("Recent Failures", value: "\(state.recentFailures.count)", symbolName: "xmark.octagon")
            }
            HStack(alignment: .top, spacing: .space3) {
                summaryCard("Recovery", value: state.recoverySummary, symbolName: "arrow.counterclockwise.circle")
                summaryCard("Event Replay", value: state.durableEventCursors.isEmpty ? "No cursors" : "\(state.durableEventCursors.count) cursors", symbolName: "timeline.selection")
            }
            metricSection
        }
    }

    private func summaryCard(_ title: String, value: String, symbolName: String) -> some View {
        VStack(alignment: .leading, spacing: .space2) {
            Label(title, systemImage: symbolName)
                .font(.bodyS.weight(.semibold))
                .foregroundStyle(Theme.C.textSecondary)
            Text(value)
                .font(.titleS)
                .foregroundStyle(Theme.C.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.space3)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .card(radius: .radiusSm)
    }

    private var diagnosticsSection: some View {
        healthCard(title: "Diagnostics", symbolName: "square.and.arrow.up") {
            HStack {
                Text("Redacted bundle")
                    .font(.bodyS.weight(.semibold))
                    .foregroundStyle(Theme.C.textPrimary)
                Spacer()
                Button("Export Diagnostics", action: onExportDiagnostics)
                    .font(.bodyS.weight(.semibold))
            }
            Text("Exports a local, redacted JSON bundle. Prompts, source bodies, tool output, and full paths are excluded by default.")
                .font(.bodyS)
                .foregroundStyle(Theme.C.textSecondary)
            if let export = state.diagnosticsExport {
                Text(export.summary)
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var recoverySection: some View {
        healthCard(title: "Recovery", symbolName: "arrow.counterclockwise.circle") {
            HStack {
                Text(state.recoverySummary)
                    .font(.bodyS.weight(.semibold))
                    .foregroundStyle(Theme.C.textPrimary)
                Spacer()
                Button("Clear Acknowledged", action: onClearRecovery)
                    .font(.bodyS.weight(.semibold))
            }
            if let warning = state.recoveryWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.accent)
            }
            if state.recoveryItems.isEmpty {
                Text("No recovery items")
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.textSecondary)
            } else {
                ForEach(state.recoveryItems) { item in
                    recoveryRow(item)
                }
            }
        }
    }

    private var durableCursorSection: some View {
        healthCard(title: "Event Replay", symbolName: "timeline.selection") {
            if state.durableEventCursors.isEmpty {
                Text("No durable session cursors")
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.textSecondary)
            } else {
                ForEach(state.durableEventCursors) { cursor in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cursor.title)
                            .font(.bodyS.weight(.semibold))
                            .foregroundStyle(Theme.C.textPrimary)
                        Text(cursor.summary)
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var metricSection: some View {
        healthCard(title: "Metrics", symbolName: "chart.xyaxis.line") {
            Text(state.memorySummary)
                .font(.bodyS)
                .foregroundStyle(Theme.C.textSecondary)
            if let policy = state.memoryPolicy {
                VStack(alignment: .leading, spacing: .space1) {
                    Text(policy.summary)
                        .font(.codeMono)
                        .foregroundStyle(Theme.C.textPrimary)
                    Text("Requested \(policy.requestedProfile.label) · GPU active \(HealthFormatting.format(Double(policy.gpuActiveBytes), unit: "bytes")) · cache \(HealthFormatting.format(Double(policy.gpuCacheBytes), unit: "bytes"))")
                        .font(.metaMono)
                        .foregroundStyle(Theme.C.textSecondary)
                    if !policy.activeActions.isEmpty {
                        Text("Actions: \(policy.activeActions.joined(separator: ", "))")
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.accent)
                    }
                }
            }
            if state.metricSummaries.isEmpty {
                Text("No metrics recorded yet")
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.textSecondary)
            } else {
                ForEach(state.metricSummaries) { metric in
                    Text(metric.summary)
                        .font(.codeMono)
                        .foregroundStyle(Theme.C.textPrimary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var eventSection: some View {
        healthCard(title: "Recent Events", symbolName: "list.bullet.rectangle") {
            if state.recentEvents.isEmpty {
                Text("No recent events")
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.textSecondary)
            } else {
                ForEach(state.recentEvents) { event in
                    eventRow(event)
                }
            }
        }
    }

    private var activeTaskSection: some View {
        healthCard(title: "Active Tasks", symbolName: "clock") {
            if state.activeTasks.isEmpty {
                Text("No active tasks")
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.textSecondary)
            } else {
                ForEach(state.activeTasks) { task in
                    taskRow(task)
                }
            }
        }
    }

    private var recentTaskSection: some View {
        healthCard(title: "Recent Tasks", symbolName: "checkmark.circle") {
            if state.recentTasks.isEmpty {
                Text("No recent tasks")
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.textSecondary)
            } else {
                ForEach(state.recentTasks) { task in
                    taskRow(task)
                }
            }
        }
    }

    private func taskRow(_ task: HealthTaskViewState) -> some View {
        HStack {
            Image(systemName: symbol(for: task.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.bodyS.weight(.semibold))
                    .foregroundStyle(Theme.C.textPrimary)
                Text("\(task.kind) · \(task.priority) · \(task.status.rawValue)")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textSecondary)
                if let message = task.message {
                    Text(message)
                        .font(.metaMono)
                        .foregroundStyle(Theme.C.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .accessibilityLabel("\(task.title), \(task.status.rawValue)")
    }

    private func recoveryRow(_ item: RecoveryItemViewState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .foregroundStyle(Theme.C.caution)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.bodyS.weight(.semibold))
                        .foregroundStyle(Theme.C.textPrimary)
                    Text(item.summary)
                        .font(.metaMono)
                        .foregroundStyle(Theme.C.textSecondary)
                    if let message = item.message {
                        Text(message)
                            .font(.metaMono)
                            .foregroundStyle(Theme.C.textSecondary)
                    }
                }
                Spacer()
            }
            HStack {
                Button(item.action.title) {
                    onRetryRecovery(item.id)
                }
                .disabled(item.action.disabledReason != nil)
                if let disabledReason = item.action.disabledReason {
                    Text(disabledReason)
                        .font(.metaMono)
                        .foregroundStyle(Theme.C.textSecondary)
                }
                Button("Dismiss") {
                    onDismissRecovery(item.id)
                }
            }
            .font(.bodyS)
        }
        .padding(.vertical, .space2)
        .accessibilityLabel("\(item.title), \(item.status), \(item.action.title)")
    }

    private func eventRow(_ event: HealthEventViewState) -> some View {
        HStack(alignment: .top) {
            Image(systemName: symbol(for: event.severity))
                .foregroundStyle(color(for: event.severity))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.bodyS)
                    .foregroundStyle(Theme.C.textPrimary)
                Text("\(event.kind) · \(event.severity.rawValue)")
                    .font(.metaMono)
                    .foregroundStyle(Theme.C.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .accessibilityLabel("\(event.kind), \(event.severity.rawValue), \(event.message)")
    }

    private func healthCard<Content: View>(
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

    private func symbol(for status: HealthTaskStatus) -> String {
        switch status {
        case .running: return "clock"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.octagon"
        case .cancelled: return "minus.circle"
        }
    }

    private func symbol(for severity: HealthEventSeverity) -> String {
        switch severity {
        case .debug: return "ladybug"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private func color(for severity: HealthEventSeverity) -> Color {
        switch severity {
        case .debug: return Theme.C.textTertiary
        case .info: return Theme.C.info
        case .warning: return Theme.C.caution
        case .error: return Theme.C.danger
        }
    }
}

private enum HealthPanelSection: String, CaseIterable, Identifiable {
    case overview
    case recovery
    case diagnostics
    case events
    case tasks
    case metrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .recovery: return "Recovery"
        case .diagnostics: return "Diagnostics"
        case .events: return "Events"
        case .tasks: return "Tasks"
        case .metrics: return "Metrics"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "waveform.path.ecg"
        case .recovery: return "arrow.counterclockwise.circle"
        case .diagnostics: return "square.and.arrow.up"
        case .events: return "list.bullet.rectangle"
        case .tasks: return "checkmark.circle"
        case .metrics: return "chart.xyaxis.line"
        }
    }
}
