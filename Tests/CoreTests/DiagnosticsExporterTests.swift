import Foundation
import Testing
import Core
import Shared

struct DiagnosticsExporterTests {
    @Test func diagnosticsExportRedactsSensitiveMetadataAndAbsolutePaths() async throws {
        let request = DiagnosticsExportRequest(
            generatedAt: Date(timeIntervalSince1970: 123),
            workspacePath: "/Users/alice/PrivateProject",
            includeFullPaths: false,
            maxRecords: 10,
            maxMessageLength: 80,
            settings: [
                "apiToken": "secret-token-value",
                "workspacePath": "/Users/alice/PrivateProject",
                "resourceProfile": "smallRAM",
            ],
            events: [
                AppEvent(
                    kind: .chat,
                    message: "Failed at /Users/alice/PrivateProject/File.swift",
                    metadata: ["prompt": "private prompt", "relativePath": "File.swift"])
            ],
            taskSnapshot: TaskSchedulerSnapshot(active: [], recent: []),
            metricSummaries: [],
            metricSamples: [],
            memoryPolicyState: MemoryPolicyState(
                requestedProfile: .automatic,
                physicalMemoryBytes: 8 * 1024 * 1024 * 1024,
                snapshot: MemorySnapshot(
                    footprint: MemoryFootprint(processFootprintBytes: 512, totalUnifiedBytes: 1024)),
                activeActions: ["reduceContext"]),
            durableEventCursors: [
                DurableEventCursor(streamID: "session:abc", sequence: 4, updatedAt: Date(timeIntervalSince1970: 124))
            ],
            sessionEvents: [
                SessionEvent(
                    sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    sequence: 4,
                    kind: .toolCallSettled,
                    payload: ["stdout": "private output"])
            ])

        let bundle = try await DiagnosticsExporter().export(request: request)
        let data = try encoded(bundle)
        let raw = String(decoding: data, as: UTF8.self)

        #expect(bundle.schemaVersion == 2)
        #expect(bundle.workspace?.basename == "PrivateProject")
        #expect(bundle.workspace?.fullPath == nil)
        #expect(bundle.settings["apiToken"] == "[redacted]")
        #expect(bundle.settings["workspacePath"]?.contains("/Users/alice") == false)
        #expect(bundle.events.first?.metadata["prompt"] == "[redacted]")
        #expect(bundle.events.first?.message.contains("/Users/alice") == false)
        #expect(bundle.memoryPolicy?.resolvedProfile == "smallRAM")
        #expect(bundle.observability.durableCursors.first?.sequence == 4)
        #expect(bundle.observability.sessionEvents.first?.payload["stdout"] == "[redacted]")
        #expect(raw.contains("private prompt") == false)
        #expect(raw.contains("private output") == false)
        #expect(raw.contains("/Users/alice") == false)
    }

    @Test func diagnosticsExportCanIncludeFullPathsExplicitlyAndIsDeterministic() async throws {
        let date = Date(timeIntervalSince1970: 123)
        let request = DiagnosticsExportRequest(
            generatedAt: date,
            workspacePath: "/tmp/work",
            includeFullPaths: true,
            events: [AppEvent(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: date, kind: .workspace, message: "Opened /tmp/work")])

        let exporter = DiagnosticsExporter()
        let first = try await exporter.export(request: request)
        let second = try await exporter.export(request: request)

        #expect(first.workspace?.fullPath == "/tmp/work")
        #expect(try encoded(first) == encoded(second))
    }

    @Test func diagnosticsExportBoundsRecordsAndWritesJSON() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("diagnostics.json")
        let events = (0..<5).map { AppEvent(kind: .search, message: "event-\($0)") }
        let request = DiagnosticsExportRequest(maxRecords: 2, events: events)
        let exporter = DiagnosticsExporter()

        let bundle = try await exporter.export(request: request)
        try await exporter.write(bundle: bundle, to: url)
        let written = try Data(contentsOf: url)
        let decoded = try JSONDecoder.diagnosticsTestDecoder.decode(DiagnosticsBundle.self, from: written)

        #expect(bundle.events.map(\.message) == ["event-3", "event-4"])
        #expect(decoded.schemaVersion == 2)
    }

    private func encoded(_ bundle: DiagnosticsBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }
}

private extension JSONDecoder {
    static var diagnosticsTestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
