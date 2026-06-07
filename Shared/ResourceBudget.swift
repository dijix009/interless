import Foundation

public enum ResourceProfile: String, Sendable, Equatable, Codable, CaseIterable {
    case automatic
    case smallRAM
    case balanced
    case largeRAM

    public static func resolvedProfile(
        for requested: ResourceProfile,
        physicalMemoryBytes: Int = Int(ProcessInfo.processInfo.physicalMemory)
    ) -> ResourceProfile {
        switch requested {
        case .automatic:
            let twelveGB = 12 * 1024 * 1024 * 1024
            let thirtyTwoGB = 32 * 1024 * 1024 * 1024
            if physicalMemoryBytes <= twelveGB { return .smallRAM }
            if physicalMemoryBytes <= thirtyTwoGB { return .balanced }
            return .largeRAM
        case .smallRAM, .balanced, .largeRAM:
            return requested
        }
    }

    public var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .smallRAM: return "Small RAM"
        case .balanced: return "Balanced"
        case .largeRAM: return "Large RAM"
        }
    }
}

public struct ResourceBudget: Sendable, Equatable, Codable {
    public var profile: ResourceProfile
    public var maxSearchResults: Int
    public var maxContextCharacters: Int
    public var maxSnippetCharacters: Int
    public var maxToolOutputBytes: Int
    public var maxIndexedFileSizeBytes: Int
    public var maxSearchSnippetReadBytes: Int
    public var orchestratorContextTokenBudget: Int?
    public var utilityContextTokenBudget: Int?
    public var orchestratorMaxTokens: Int?
    public var utilityMaxTokens: Int?
    public var mlxGPUCacheLimitBytes: Int
    public var chatTranscriptRetainedCharacters: Int
    public var chatToolEventRetainedCount: Int
    public var fileTreePathLimit: Int

    public init(
        profile: ResourceProfile,
        maxSearchResults: Int,
        maxContextCharacters: Int,
        maxSnippetCharacters: Int,
        maxToolOutputBytes: Int,
        maxIndexedFileSizeBytes: Int,
        maxSearchSnippetReadBytes: Int,
        orchestratorContextTokenBudget: Int?,
        utilityContextTokenBudget: Int?,
        orchestratorMaxTokens: Int?,
        utilityMaxTokens: Int?,
        mlxGPUCacheLimitBytes: Int,
        chatTranscriptRetainedCharacters: Int,
        chatToolEventRetainedCount: Int,
        fileTreePathLimit: Int
    ) {
        self.profile = profile
        self.maxSearchResults = max(0, maxSearchResults)
        self.maxContextCharacters = max(0, maxContextCharacters)
        self.maxSnippetCharacters = max(0, maxSnippetCharacters)
        self.maxToolOutputBytes = max(0, maxToolOutputBytes)
        self.maxIndexedFileSizeBytes = max(0, maxIndexedFileSizeBytes)
        self.maxSearchSnippetReadBytes = max(0, maxSearchSnippetReadBytes)
        self.orchestratorContextTokenBudget = orchestratorContextTokenBudget
        self.utilityContextTokenBudget = utilityContextTokenBudget
        self.orchestratorMaxTokens = orchestratorMaxTokens
        self.utilityMaxTokens = utilityMaxTokens
        self.mlxGPUCacheLimitBytes = max(0, mlxGPUCacheLimitBytes)
        self.chatTranscriptRetainedCharacters = max(0, chatTranscriptRetainedCharacters)
        self.chatToolEventRetainedCount = max(0, chatToolEventRetainedCount)
        self.fileTreePathLimit = max(0, fileTreePathLimit)
    }

    public static func resolved(
        for requested: ResourceProfile,
        physicalMemoryBytes: Int = Int(ProcessInfo.processInfo.physicalMemory)
    ) -> ResourceBudget {
        switch ResourceProfile.resolvedProfile(for: requested, physicalMemoryBytes: physicalMemoryBytes) {
        case .automatic:
            return resolved(for: .balanced, physicalMemoryBytes: physicalMemoryBytes)
        case .smallRAM:
            return .smallRAM
        case .balanced:
            return .balanced
        case .largeRAM:
            return .largeRAM
        }
    }

    public func reducedForMemoryPressure() -> ResourceBudget {
        var copy = self
        copy.maxSearchResults = max(2, maxSearchResults / 2)
        copy.maxContextCharacters = max(4_000, maxContextCharacters / 2)
        copy.maxSnippetCharacters = max(400, maxSnippetCharacters / 2)
        copy.maxToolOutputBytes = max(8 * 1024, maxToolOutputBytes / 2)
        copy.orchestratorContextTokenBudget = orchestratorContextTokenBudget.map { max(2_048, $0 / 2) }
        copy.utilityContextTokenBudget = utilityContextTokenBudget.map { max(1_024, $0 / 2) }
        copy.orchestratorMaxTokens = orchestratorMaxTokens.map { max(256, $0 / 2) }
        copy.utilityMaxTokens = utilityMaxTokens.map { max(192, $0 / 2) }
        return copy
    }

    public func contextTokenBudget(for role: ModelRole) -> Int? {
        switch role {
        case .orchestrator: return orchestratorContextTokenBudget
        case .utility: return utilityContextTokenBudget
        case .embeddings: return utilityContextTokenBudget
        }
    }

    public func maxTokens(for role: ModelRole) -> Int? {
        switch role {
        case .orchestrator: return orchestratorMaxTokens
        case .utility: return utilityMaxTokens
        case .embeddings: return utilityMaxTokens
        }
    }

    public func maxTokens(for role: ModelRole, reasoningEffort: ReasoningEffort?) -> Int? {
        let base = maxTokens(for: role)
        guard let reasoningEffort, reasoningEffort != .none else { return base }
        let floor = reasoningMaxTokenFloor(for: reasoningEffort)
        return max(base ?? floor, floor)
    }

    private func reasoningMaxTokenFloor(for effort: ReasoningEffort) -> Int {
        switch (profile, effort) {
        case (_, .none):
            return 0
        case (.smallRAM, .low):
            return 1_536
        case (.smallRAM, .medium):
            return 2_048
        case (.smallRAM, .high):
            return 3_072
        case (.balanced, .low):
            return 2_048
        case (.balanced, .medium):
            return 3_072
        case (.balanced, .high):
            return 4_096
        case (.largeRAM, .low):
            return 4_096
        case (.largeRAM, .medium):
            return 6_144
        case (.largeRAM, .high):
            return 8_192
        case (.automatic, _):
            return ResourceBudget.resolved(for: .automatic).reasoningMaxTokenFloor(for: effort)
        }
    }

    public static let smallRAM = ResourceBudget(
        profile: .smallRAM,
        maxSearchResults: 4,
        maxContextCharacters: 8_000,
        maxSnippetCharacters: 700,
        maxToolOutputBytes: 16 * 1024,
        maxIndexedFileSizeBytes: 256 * 1024,
        maxSearchSnippetReadBytes: 64 * 1024,
        orchestratorContextTokenBudget: 4_096,
        utilityContextTokenBudget: 2_048,
        orchestratorMaxTokens: 512,
        utilityMaxTokens: 384,
        mlxGPUCacheLimitBytes: 128 * 1024 * 1024,
        chatTranscriptRetainedCharacters: 40_000,
        chatToolEventRetainedCount: 80,
        fileTreePathLimit: 20_000)

    public static let balanced = ResourceBudget(
        profile: .balanced,
        maxSearchResults: 8,
        maxContextCharacters: 24_000,
        maxSnippetCharacters: 1_500,
        maxToolOutputBytes: 64 * 1024,
        maxIndexedFileSizeBytes: 1 * 1024 * 1024,
        maxSearchSnippetReadBytes: 256 * 1024,
        orchestratorContextTokenBudget: 8_192,
        utilityContextTokenBudget: 4_096,
        orchestratorMaxTokens: 1_024,
        utilityMaxTokens: 768,
        mlxGPUCacheLimitBytes: 256 * 1024 * 1024,
        chatTranscriptRetainedCharacters: 100_000,
        chatToolEventRetainedCount: 200,
        fileTreePathLimit: 80_000)

    public static let largeRAM = ResourceBudget(
        profile: .largeRAM,
        maxSearchResults: 12,
        maxContextCharacters: 48_000,
        maxSnippetCharacters: 2_500,
        maxToolOutputBytes: 128 * 1024,
        maxIndexedFileSizeBytes: 2 * 1024 * 1024,
        maxSearchSnippetReadBytes: 512 * 1024,
        orchestratorContextTokenBudget: 16_384,
        utilityContextTokenBudget: 8_192,
        orchestratorMaxTokens: 2_048,
        utilityMaxTokens: 1_024,
        mlxGPUCacheLimitBytes: 512 * 1024 * 1024,
        chatTranscriptRetainedCharacters: 250_000,
        chatToolEventRetainedCount: 400,
        fileTreePathLimit: 200_000)
}

public struct MemoryPolicyState: Sendable, Equatable {
    public var requestedProfile: ResourceProfile
    public var resolvedProfile: ResourceProfile
    public var budget: ResourceBudget
    public var snapshot: MemorySnapshot?
    public var activeActions: [String]
    public var evaluatedAt: Date

    public init(
        requestedProfile: ResourceProfile = .automatic,
        physicalMemoryBytes: Int = Int(ProcessInfo.processInfo.physicalMemory),
        snapshot: MemorySnapshot? = nil,
        activeActions: [String] = [],
        evaluatedAt: Date = Date()
    ) {
        self.requestedProfile = requestedProfile
        self.resolvedProfile = ResourceProfile.resolvedProfile(for: requestedProfile, physicalMemoryBytes: physicalMemoryBytes)
        let baseBudget = ResourceBudget.resolved(for: requestedProfile, physicalMemoryBytes: physicalMemoryBytes)
        self.budget = activeActions.contains("reduceContext") ? baseBudget.reducedForMemoryPressure() : baseBudget
        self.snapshot = snapshot
        self.activeActions = activeActions
        self.evaluatedAt = evaluatedAt
    }

    public var usedFraction: Double {
        snapshot?.usedFraction ?? 0
    }
}
