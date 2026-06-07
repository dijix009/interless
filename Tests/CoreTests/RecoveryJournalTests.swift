import Foundation
import Testing
import Core

struct RecoveryJournalTests {
    @Test func journalPersistsAndRecoversUnfinishedPreviousRunOperations() async throws {
        let url = try journalURL()
        let oldRun = UUID()
        let newRun = UUID()
        let first = RecoveryJournal(fileURL: url, appRunID: oldRun)
        _ = try await first.beginOperation(
            kind: .indexing,
            title: "Full reindex",
            metadata: ["workspacePath": "/tmp/work", "prompt": "do not persist"])

        let second = RecoveryJournal(fileURL: url, appRunID: newRun)
        let recovered = try await second.recoverUnfinishedOperations()
        let record = try #require(recovered.first)

        #expect(record.status == .unfinishedPreviousRun)
        #expect(record.operationKind == .indexing)
        #expect(record.metadata["workspacePath"] == "/tmp/work")
        #expect(record.metadata["prompt"] == nil)
    }

    @Test func completedAndCancelledOperationsDoNotBecomeRecoveryItems() async throws {
        let url = try journalURL()
        let oldRun = UUID()
        let newRun = UUID()
        let first = RecoveryJournal(fileURL: url, appRunID: oldRun)
        let completed = try await first.beginOperation(kind: .search, title: "Search")
        try await first.finishOperation(completed, status: .completed)
        let cancelled = try await first.beginOperation(kind: .chat, title: "Chat")
        try await first.finishOperation(cancelled, status: .cancelled)

        let second = RecoveryJournal(fileURL: url, appRunID: newRun)
        let recovered = try await second.recoverUnfinishedOperations()

        #expect(recovered.isEmpty)
    }

    @Test func failureRecordsAcknowledgeAndClear() async throws {
        let url = try journalURL()
        let journal = RecoveryJournal(fileURL: url)
        let failure = try await journal.recordFailure(
            kind: .modelLoad,
            title: "Load models",
            message: String(repeating: "x", count: 320),
            metadata: ["modelID": "secret-token-model", "modelRole": "utility"])

        var snapshot = try await journal.snapshot()
        #expect(snapshot.recoveryItems.map(\.id) == [failure.id])
        #expect(snapshot.recoveryItems.first?.message?.count ?? 0 <= 243)
        #expect(snapshot.recoveryItems.first?.metadata["modelID"] == "[redacted]")

        try await journal.acknowledge(failure.id)
        snapshot = try await journal.snapshot()
        #expect(snapshot.recoveryItems.isEmpty)

        try await journal.clearAcknowledged()
        snapshot = try await journal.snapshot()
        #expect(snapshot.records.isEmpty)
    }

    @Test func journalRetentionIsBoundedAndFileIsValidJSON() async throws {
        let url = try journalURL()
        let journal = RecoveryJournal(fileURL: url, retentionLimit: 2)

        _ = try await journal.recordFailure(kind: .search, title: "one", message: "1")
        _ = try await journal.recordFailure(kind: .search, title: "two", message: "2")
        _ = try await journal.recordFailure(kind: .search, title: "three", message: "3")

        let snapshot = try await journal.snapshot()
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(snapshot.records.map(\.title) == ["two", "three"])
        #expect(object?["records"] != nil)
    }

    @Test func corruptJournalIsArchivedAndReplaced() async throws {
        let url = try journalURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let journal = RecoveryJournal(fileURL: url)

        let recovered = try await journal.recoverUnfinishedOperations()
        let snapshot = try await journal.snapshot()

        #expect(recovered.isEmpty)
        #expect(snapshot.corruptionArchiveURL != nil)
        #expect(FileManager.default.fileExists(atPath: snapshot.corruptionArchiveURL?.path ?? ""))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

private func journalURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("recovery-journal.json")
}
