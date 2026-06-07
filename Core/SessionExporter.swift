import Foundation

public struct SessionExportOptions: Sendable, Equatable, Codable {
    public var includeMessages: Bool
    public var includeToolOutputs: Bool
    public var includePendingInputs: Bool
    public var includeFullPaths: Bool
    public var maxRecords: Int
    public var maxTextLength: Int

    public init(
        includeMessages: Bool = true,
        includeToolOutputs: Bool = false,
        includePendingInputs: Bool = false,
        includeFullPaths: Bool = false,
        maxRecords: Int = 500,
        maxTextLength: Int = 4_000
    ) {
        self.includeMessages = includeMessages
        self.includeToolOutputs = includeToolOutputs
        self.includePendingInputs = includePendingInputs
        self.includeFullPaths = includeFullPaths
        self.maxRecords = max(0, maxRecords)
        self.maxTextLength = max(32, maxTextLength)
    }
}

public struct SessionExportRedaction: Sendable, Equatable, Codable {
    public var fullPathsIncluded: Bool
    public var toolOutputsIncluded: Bool
    public var pendingInputsIncluded: Bool
    public var maxTextLength: Int
    public var rules: [String]

    public init(
        fullPathsIncluded: Bool,
        toolOutputsIncluded: Bool,
        pendingInputsIncluded: Bool,
        maxTextLength: Int,
        rules: [String]
    ) {
        self.fullPathsIncluded = fullPathsIncluded
        self.toolOutputsIncluded = toolOutputsIncluded
        self.pendingInputsIncluded = pendingInputsIncluded
        self.maxTextLength = maxTextLength
        self.rules = rules
    }
}

public struct SessionExportBundle: Sendable, Equatable, Codable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var session: SessionRecord
    public var pendingInputs: [SessionInputRecord]
    public var messageParts: [SessionMessagePart]
    public var todos: [SessionTodo]
    public var compaction: SessionCompactionCheckpoint?
    public var events: [SessionEvent]
    public var replay: DurableEventReplaySummary?
    public var redaction: SessionExportRedaction

    public init(
        schemaVersion: Int = 1,
        exportedAt: Date = Date(),
        session: SessionRecord,
        pendingInputs: [SessionInputRecord] = [],
        messageParts: [SessionMessagePart] = [],
        todos: [SessionTodo] = [],
        compaction: SessionCompactionCheckpoint? = nil,
        events: [SessionEvent] = [],
        replay: DurableEventReplaySummary? = nil,
        redaction: SessionExportRedaction
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.session = session
        self.pendingInputs = pendingInputs
        self.messageParts = messageParts
        self.todos = todos
        self.compaction = compaction
        self.events = events
        self.replay = replay
        self.redaction = redaction
    }
}

public struct SessionExporter: Sendable {
    public init() {}

    public func export(
        sessionID: UUID,
        from store: any SessionRuntimeStore,
        options: SessionExportOptions = SessionExportOptions()
    ) async throws -> SessionExportBundle {
        guard let session = try await store.session(id: sessionID) else {
            throw SessionRuntimeError.sessionNotFound(sessionID)
        }
        let redactor = DiagnosticsRedactor(
            includeFullPaths: options.includeFullPaths,
            maxMessageLength: options.maxTextLength)
        let events = try await store.events(sessionID: sessionID, after: nil, limit: options.maxRecords)
        let startCursor = DurableEventCursor(sessionID: sessionID, cursor: .init(sequence: 0))
        let endCursor = DurableEventCursor(
            sessionID: sessionID,
            cursor: events.last?.cursor ?? .init(sequence: 0),
            updatedAt: events.last?.createdAt ?? session.updatedAt)
        return SessionExportBundle(
            exportedAt: Date(),
            session: sanitized(session, redactor: redactor),
            pendingInputs: options.includePendingInputs
                ? try await store.pendingInputs(sessionID: sessionID, limit: options.maxRecords).map { sanitized($0, redactor: redactor) }
                : [],
            messageParts: options.includeMessages
                ? try await store.messageParts(sessionID: sessionID, limit: options.maxRecords).map { sanitized($0, redactor: redactor, includeToolOutputs: options.includeToolOutputs) }
                : [],
            todos: try await store.todos(sessionID: sessionID).prefix(options.maxRecords).map { sanitized($0, redactor: redactor) },
            compaction: try await store.latestCompaction(sessionID: sessionID).map { sanitized($0, redactor: redactor) },
            events: events.map { sanitized($0, redactor: redactor) },
            replay: DurableEventReplaySummary(
                streamID: DurableEventCursor.sessionStreamID(sessionID),
                startCursor: startCursor,
                endCursor: endCursor,
                replayedCount: events.count,
                isTruncated: events.count >= options.maxRecords),
            redaction: SessionExportRedaction(
                fullPathsIncluded: options.includeFullPaths,
                toolOutputsIncluded: options.includeToolOutputs,
                pendingInputsIncluded: options.includePendingInputs,
                maxTextLength: options.maxTextLength,
                rules: [
                    "absolute paths are hashed unless full paths are explicitly requested",
                    "secret/token/password/credential/authorization values are redacted",
                    "tool outputs are excluded unless explicitly requested",
                    "text fields are bounded by maxTextLength",
                ]))
    }

    public func importBundle(
        _ bundle: SessionExportBundle,
        into store: any SessionRuntimeStore
    ) async throws -> SessionRecord {
        let session = try await store.createSession(
            id: bundle.session.id,
            workspacePath: bundle.session.workspacePath,
            title: bundle.session.title)
        for input in bundle.pendingInputs {
            _ = try await store.admitInput(input)
        }
        for part in bundle.messageParts {
            try await store.appendMessagePart(part)
        }
        if !bundle.todos.isEmpty {
            try await store.replaceTodos(bundle.todos, sessionID: session.id)
        }
        if let compaction = bundle.compaction {
            try await store.saveCompaction(compaction)
        }
        for event in bundle.events {
            _ = try await store.appendEvent(event)
        }
        return session
    }

    private func sanitized(_ session: SessionRecord, redactor: DiagnosticsRedactor) -> SessionRecord {
        var copy = session
        copy.title = redactor.sanitize(session.title)
        copy.workspacePath = session.workspacePath.map(redactor.sanitize)
        return copy
    }

    private func sanitized(_ input: SessionInputRecord, redactor: DiagnosticsRedactor) -> SessionInputRecord {
        var copy = input
        copy.prompt = redactor.sanitize(input.prompt)
        return copy
    }

    private func sanitized(
        _ part: SessionMessagePart,
        redactor: DiagnosticsRedactor,
        includeToolOutputs: Bool
    ) -> SessionMessagePart {
        var copy = part
        if part.role == .tool && !includeToolOutputs {
            copy.text = "[tool output redacted]"
        } else {
            copy.text = redactor.sanitize(part.text)
        }
        return copy
    }

    private func sanitized(_ todo: SessionTodo, redactor: DiagnosticsRedactor) -> SessionTodo {
        var copy = todo
        copy.title = redactor.sanitize(todo.title)
        return copy
    }

    private func sanitized(
        _ checkpoint: SessionCompactionCheckpoint,
        redactor: DiagnosticsRedactor
    ) -> SessionCompactionCheckpoint {
        var copy = checkpoint
        copy.summary = redactor.sanitize(checkpoint.summary)
        copy.recentContext = redactor.sanitize(checkpoint.recentContext)
        return copy
    }

    private func sanitized(_ event: SessionEvent, redactor: DiagnosticsRedactor) -> SessionEvent {
        var copy = event
        copy.payload = redactor.sanitize(metadata: event.payload)
        return copy
    }
}
