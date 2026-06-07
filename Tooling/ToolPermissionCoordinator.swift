import Foundation

public enum ToolPermissionEffect: String, Sendable, Equatable, Codable, CaseIterable {
    case allow
    case ask
    case deny
}

public struct ToolPermissionDecision: Sendable, Equatable, Codable {
    public var effect: ToolPermissionEffect
    public var reason: String

    public init(effect: ToolPermissionEffect, reason: String = "") {
        self.effect = effect
        self.reason = reason
    }
}

public struct ToolPermissionCoordinator: Sendable, Equatable {
    public var policy: ToolExecutionPolicy

    public init(policy: ToolExecutionPolicy = .default) {
        self.policy = policy
    }

    public func evaluate(_ request: ToolRequest) -> ToolPermissionDecision {
        switch request {
        case .writeFile, .editFile, .applyPatch:
            return decision(
                effect: policy.writePermission,
                deniedReason: "writes are disabled",
                askReason: "\(request.displayName) wants to modify files in this workspace.")
        case let .runTests(arguments):
            return commandDecision(["./scripts/test.sh"] + arguments)
        case let .shell(command):
            return commandDecision(command)
        default:
            return ToolPermissionDecision(effect: .allow)
        }
    }

    public func assertAllowed(_ request: ToolRequest) throws {
        let decision = evaluate(request)
        switch decision.effect {
        case .allow:
            return
        case .ask:
            throw ToolError.permissionDenied(decision.reason.isEmpty ? "permission requires UI approval" : decision.reason)
        case .deny:
            if case .writeFile = request { throw ToolError.writeDenied }
            if case .editFile = request { throw ToolError.writeDenied }
            if case .applyPatch = request { throw ToolError.writeDenied }
            if case let .runTests(arguments) = request {
                try policy.validate(command: ["./scripts/test.sh"] + arguments)
            }
            if case let .shell(command) = request {
                try policy.validate(command: command)
            }
            throw ToolError.permissionDenied(decision.reason)
        }
    }

    public func authorize(_ request: ToolRequest, authorizer: ToolPermissionAuthorizer?) async throws {
        let decision = evaluate(request)
        switch decision.effect {
        case .allow:
            return
        case .deny:
            if case .writeFile = request { throw ToolError.writeDenied }
            if case .editFile = request { throw ToolError.writeDenied }
            if case .applyPatch = request { throw ToolError.writeDenied }
            if case let .runTests(arguments) = request {
                try policy.validate(command: ["./scripts/test.sh"] + arguments)
            }
            if case let .shell(command) = request {
                try policy.validate(command: command)
            }
            throw ToolError.permissionDenied(decision.reason)
        case .ask:
            guard let authorizer else {
                throw ToolError.permissionDenied(decision.reason.isEmpty ? "permission requires UI approval" : decision.reason)
            }
            let permissionRequest = ToolPermissionRequest(
                request: request,
                title: "Allow \(request.displayName)?",
                message: decision.reason)
            switch await authorizer(permissionRequest) {
            case .allowOnce:
                return
            case .deny:
                throw ToolError.permissionDenied(decision.reason.isEmpty ? "permission denied" : decision.reason)
            }
        }
    }

    private func commandDecision(_ command: [String]) -> ToolPermissionDecision {
        guard let pattern = policy.matchingPattern(for: command) else {
            return ToolPermissionDecision(effect: .deny, reason: String(describing: ToolError.commandDenied(command)))
        }
        guard pattern.requiresNetworkPermission else {
            return ToolPermissionDecision(effect: .allow)
        }
        return decision(
            effect: policy.networkPermission,
            deniedReason: String(describing: ToolError.networkDisabled(command)),
            askReason: "\(command.joined(separator: " ")) wants to run a trusted process command.")
    }

    private func decision(
        effect: ToolPermissionEffect,
        deniedReason: String,
        askReason: String
    ) -> ToolPermissionDecision {
        switch effect {
        case .allow:
            return ToolPermissionDecision(effect: .allow)
        case .ask:
            return ToolPermissionDecision(effect: .ask, reason: askReason)
        case .deny:
            return ToolPermissionDecision(effect: .deny, reason: deniedReason)
        }
    }
}
