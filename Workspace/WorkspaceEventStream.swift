import Foundation
import Shared

public enum WorkspaceEventKind: String, Sendable, Equatable, Codable {
    case created, modified, deleted, renamed, unknown
}

public struct WorkspaceEvent: Sendable, Equatable, Codable {
    public var relativePath: String?
    public var kind: WorkspaceEventKind
    public var isDirectory: Bool

    public init(relativePath: String?, kind: WorkspaceEventKind, isDirectory: Bool = false) {
        self.relativePath = relativePath
        self.kind = kind
        self.isDirectory = isDirectory
    }
}

public protocol WorkspaceEventStream: Sendable {
    func events(root: URL) -> AsyncStream<[WorkspaceEvent]>
}
