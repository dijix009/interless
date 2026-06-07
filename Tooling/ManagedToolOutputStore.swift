import Foundation

public struct ManagedToolOutputRef: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var stdoutBytes: Int
    public var stderrBytes: Int
    public var isTruncated: Bool
    public var createdAt: Date
    public var preview: String

    public init(
        id: UUID = UUID(),
        stdoutBytes: Int,
        stderrBytes: Int,
        isTruncated: Bool,
        createdAt: Date = Date(),
        preview: String
    ) {
        self.id = id
        self.stdoutBytes = stdoutBytes
        self.stderrBytes = stderrBytes
        self.isTruncated = isTruncated
        self.createdAt = createdAt
        self.preview = preview
    }
}

public struct ManagedToolOutput: Sendable, Equatable, Codable {
    public var ref: ManagedToolOutputRef
    public var stdout: String
    public var stderr: String

    public init(ref: ManagedToolOutputRef, stdout: String, stderr: String) {
        self.ref = ref
        self.stdout = stdout
        self.stderr = stderr
    }
}

public actor ManagedToolOutputStore {
    private let maxEntries: Int
    private let maxBytesPerStream: Int
    private var order: [UUID] = []
    private var outputs: [UUID: ManagedToolOutput] = [:]

    public init(maxEntries: Int = 256, maxBytesPerStream: Int = 64 * 1024) {
        self.maxEntries = max(0, maxEntries)
        self.maxBytesPerStream = max(0, maxBytesPerStream)
    }

    @discardableResult
    public func store(result: ToolResult, createdAt: Date = Date()) -> ManagedToolOutputRef {
        let stdout = bounded(result.stdout)
        let stderr = bounded(result.stderr)
        let isTruncated = stdout.truncated || stderr.truncated
        let previewSource = stdout.text.isEmpty ? stderr.text : stdout.text
        let ref = ManagedToolOutputRef(
            stdoutBytes: result.stdout.utf8.count,
            stderrBytes: result.stderr.utf8.count,
            isTruncated: isTruncated,
            createdAt: createdAt,
            preview: String(previewSource.prefix(240)))
        outputs[ref.id] = ManagedToolOutput(ref: ref, stdout: stdout.text, stderr: stderr.text)
        order.append(ref.id)
        prune()
        return ref
    }

    public func output(id: UUID) -> ManagedToolOutput? {
        outputs[id]
    }

    public func allRefs() -> [ManagedToolOutputRef] {
        order.compactMap { outputs[$0]?.ref }
    }

    private func bounded(_ text: String) -> (text: String, truncated: Bool) {
        guard text.utf8.count > maxBytesPerStream else { return (text, false) }
        let prefix = text.utf8.prefix(maxBytesPerStream)
        return (String(decoding: prefix, as: UTF8.self), true)
    }

    private func prune() {
        while order.count > maxEntries, let oldest = order.first {
            order.removeFirst()
            outputs[oldest] = nil
        }
    }
}
