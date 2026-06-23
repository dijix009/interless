import Foundation
import Security

public enum KeychainSecretError: Error, Sendable, Equatable, CustomStringConvertible {
    case unexpectedStatus(OSStatus)
    case dataEncodingFailed

    public var description: String {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status \(status)."
        case .dataEncodingFailed:
            return "Secret could not be encoded as UTF-8."
        }
    }
}

public protocol SecretStore: Sendable {
    func save(_ secret: String, service: String, account: String) async throws
    func read(service: String, account: String) async throws -> String?
    func delete(service: String, account: String) async throws
}

public struct KeychainSecretStore: SecretStore {
    public let accessGroup: String?

    public init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup
    }

    public func save(_ secret: String, service: String, account: String) async throws {
        guard let data = secret.data(using: .utf8) else {
            throw KeychainSecretError.dataEncodingFailed
        }
        var query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw KeychainSecretError.unexpectedStatus(updateStatus)
        }
        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainSecretError.unexpectedStatus(addStatus)
        }
    }

    public func read(service: String, account: String) async throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainSecretError.unexpectedStatus(status)
        }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(service: String, account: String) async throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretError.unexpectedStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

public enum InterlessSecrets {
    public static let service = "dev.interless.secrets"
    public static let huggingFaceTokenAccount = "huggingface.token"
    public static let anthropicAPIKeyAccount = "anthropic.apiKey"
}
