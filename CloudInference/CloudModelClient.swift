import Foundation
import Shared
import InterlessSecurity

/// Hosted model providers Interless can route a role to. Local MLX is the
/// default; these are opt-in. (OpenAI is a planned sibling.)
public enum CloudProvider: String, Sendable, Equatable, CaseIterable {
    case anthropic
    case openai

    /// Keychain account holding this provider's API key.
    public var keychainAccount: String {
        switch self {
        case .anthropic: return InterlessSecrets.anthropicAPIKeyAccount
        case .openai: return InterlessSecrets.openAIAPIKeyAccount
        }
    }

    /// Environment variable consulted as a fallback (for the CLI / headless).
    public var environmentVariable: String {
        switch self {
        case .anthropic: return "ANTHROPIC_API_KEY"
        case .openai: return "OPENAI_API_KEY"
        }
    }
}

/// A model id resolved to a hosted provider, e.g. `anthropic/claude-opus-4-8`.
public struct CloudModelID: Sendable, Equatable {
    public var provider: CloudProvider
    public var model: String

    public init(provider: CloudProvider, model: String) {
        self.provider = provider
        self.model = model
    }
}

/// Resolves a role's model-id string to a hosted provider, or `nil` for a local
/// MLX model. The convention is `provider/model`; bare ids (incl. Hugging Face
/// repo ids like `mlx-community/…`) stay local because only known provider
/// prefixes match.
public enum CloudModelResolver {
    public static func resolve(_ id: String) -> CloudModelID? {
        let parts = id.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              let provider = CloudProvider(rawValue: parts[0].lowercased()),
              !parts[1].isEmpty else {
            return nil
        }
        return CloudModelID(provider: provider, model: parts[1])
    }

    public static func isCloud(_ id: String) -> Bool {
        resolve(id) != nil
    }
}

/// Streams generation from a hosted model. The model is passed explicitly (the
/// id is resolved from the role's loaded handle by the caller). A `nil`-key or
/// transport failure surfaces as a thrown `InferenceError` on the stream.
public protocol CloudModelClient: Sendable {
    func stream(model: String, request: GenerationRequest) -> AsyncThrowingStream<TokenChunk, Error>
    /// Cheap precondition check (e.g. an API key is present). Throws a clear
    /// `InferenceError` when the client cannot be used.
    func validate() async throws
}

/// Supplies provider API keys. Default reads the Keychain `SecretStore`, then
/// falls back to the provider's environment variable.
public protocol CloudKeyProvider: Sendable {
    func apiKey(for provider: CloudProvider) async -> String?
}

public struct KeychainCloudKeyProvider: CloudKeyProvider {
    private let secretStore: any SecretStore
    private let environment: [String: String]

    public init(
        secretStore: any SecretStore = KeychainSecretStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.secretStore = secretStore
        self.environment = environment
    }

    public func apiKey(for provider: CloudProvider) async -> String? {
        if let stored = (try? await secretStore.read(
            service: InterlessSecrets.service, account: provider.keychainAccount)) ?? nil,
           !stored.isEmpty {
            return stored
        }
        if let env = environment[provider.environmentVariable], !env.isEmpty {
            return env
        }
        return nil
    }
}
