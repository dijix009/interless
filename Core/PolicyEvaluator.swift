import Foundation

public enum PolicyEffect: String, Sendable, Equatable, Codable, CaseIterable {
    case allow
    case ask
    case deny
}

public struct PolicyStatement: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var effect: PolicyEffect
    public var action: String
    public var resource: String

    public init(
        id: UUID = UUID(),
        effect: PolicyEffect,
        action: String,
        resource: String
    ) {
        self.id = id
        self.effect = effect
        self.action = action
        self.resource = resource
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case effect
        case action
        case resource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        effect = try container.decode(PolicyEffect.self, forKey: .effect)
        action = try container.decode(String.self, forKey: .action)
        resource = try container.decode(String.self, forKey: .resource)
    }
}

public struct PolicyDecision: Sendable, Equatable {
    public var effect: PolicyEffect
    public var matchedStatement: PolicyStatement?

    public init(effect: PolicyEffect, matchedStatement: PolicyStatement? = nil) {
        self.effect = effect
        self.matchedStatement = matchedStatement
    }
}

public struct PolicyEvaluator: Sendable {
    public var statements: [PolicyStatement]

    public init(statements: [PolicyStatement] = []) {
        self.statements = statements
    }

    public func evaluate(
        action: String,
        resource: String,
        fallback: PolicyEffect = .allow
    ) -> PolicyDecision {
        var decision = PolicyDecision(effect: fallback)
        for statement in statements where
            Self.matches(action, pattern: statement.action)
                && Self.matches(resource, pattern: statement.resource) {
            decision = PolicyDecision(effect: statement.effect, matchedStatement: statement)
        }
        return decision
    }

    public static func matches(_ value: String, pattern: String) -> Bool {
        if pattern == "*" { return true }
        var regex = "^"
        for character in pattern {
            switch character {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            default:
                regex += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        regex += "$"
        return value.range(of: regex, options: [.regularExpression]) != nil
    }
}
