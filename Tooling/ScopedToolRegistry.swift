import Foundation
import Shared

public enum ToolScope: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
    case workspace
    case session
    case agent
    case extensionProvided
}

public struct ScopedToolRegistration: Sendable {
    public var definition: ToolDefinition
    public var scope: ToolScope
    public var generation: Int
    public var decode: @Sendable (ModelToolCall) throws -> ToolRequest

    public init(
        definition: ToolDefinition,
        scope: ToolScope,
        generation: Int,
        decode: @escaping @Sendable (ModelToolCall) throws -> ToolRequest
    ) {
        self.definition = definition
        self.scope = scope
        self.generation = generation
        self.decode = decode
    }
}

public struct ScopedToolRegistry: Sendable {
    public var generation: Int
    private var registrations: [String: ScopedToolRegistration]

    public init(generation: Int = 1, registrations: [ScopedToolRegistration] = []) {
        self.generation = generation
        self.registrations = Dictionary(uniqueKeysWithValues: registrations.map { ($0.definition.name, $0) })
    }

    public var definitions: [ToolDefinition] {
        registrations.values
            .sorted { lhs, rhs in lhs.definition.name < rhs.definition.name }
            .map(\.definition)
    }

    public func registration(name: String) -> ScopedToolRegistration? {
        registrations[name]
    }

    public func registering(
        definition: ToolDefinition,
        scope: ToolScope,
        decode: @escaping @Sendable (ModelToolCall) throws -> ToolRequest
    ) -> ScopedToolRegistry {
        var copy = self
        copy.registrations[definition.name] = ScopedToolRegistration(
            definition: definition,
            scope: scope,
            generation: generation,
            decode: decode)
        return copy
    }

    public func request(from call: ModelToolCall, generation actualGeneration: Int? = nil) throws -> ToolRequest {
        guard let registration = registrations[call.name] else {
            throw ToolError.unknownTool(call.name)
        }
        let actual = actualGeneration ?? registration.generation
        guard actual == registration.generation else {
            throw ToolError.staleToolCall(
                name: call.name,
                expectedGeneration: registration.generation,
                actualGeneration: actual)
        }
        return try registration.decode(call)
    }
}
