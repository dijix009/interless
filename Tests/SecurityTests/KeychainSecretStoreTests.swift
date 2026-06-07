import Foundation
import Testing
@testable import InterlessSecurity

@Suite("KeychainSecretStore")
struct KeychainSecretStoreTests {
    @Test func savesReadsAndDeletesSecretInIsolatedAccount() async throws {
        let store = KeychainSecretStore()
        let service = "dev.interless.tests.\(UUID().uuidString)"
        let account = "token"
        try await store.delete(service: service, account: account)

        try await store.save("secret-token", service: service, account: account)
        #expect(try await store.read(service: service, account: account) == "secret-token")

        try await store.delete(service: service, account: account)
        #expect(try await store.read(service: service, account: account) == nil)
    }

    @Test func accountsAreIsolated() async throws {
        let store = KeychainSecretStore()
        let service = "dev.interless.tests.\(UUID().uuidString)"
        defer {
            Task {
                try? await store.delete(service: service, account: "one")
                try? await store.delete(service: service, account: "two")
            }
        }

        try await store.save("first", service: service, account: "one")
        try await store.save("second", service: service, account: "two")

        #expect(try await store.read(service: service, account: "one") == "first")
        #expect(try await store.read(service: service, account: "two") == "second")
    }
}
