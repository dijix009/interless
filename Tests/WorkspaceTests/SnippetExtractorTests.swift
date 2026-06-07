import Testing
import Foundation
import Workspace

struct SnippetExtractorTests {

    @Test func returnsLineContainingTerm() {
        let text = "first line\nfunc authenticate(user:)\nlast line"
        #expect(SnippetExtractor.snippet(from: text, query: "authenticate") == "func authenticate(user:)")
    }

    @Test func nilWhenNoTermMatches() {
        #expect(SnippetExtractor.snippet(from: "hello\nworld", query: "zzz") == nil)
    }

    @Test func truncatesLongLineWithEllipsis() {
        let line = String(repeating: "x", count: 50) + " needle " + String(repeating: "y", count: 200)
        let snippet = SnippetExtractor.snippet(from: line, query: "needle", maxChars: 40)
        #expect(snippet != nil)
        #expect((snippet?.count ?? 0) <= 41) // 40 chars + ellipsis
    }

    @Test func fileSnippetReadsOnlyBoundedPrefix() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try ("needle\n" + String(repeating: "x", count: 10_000)).write(to: url, atomically: true, encoding: .utf8)

        let result = try SnippetExtractor.snippet(fileAt: url, query: "needle", maxReadBytes: 32)

        #expect(result.bytesRead == 32)
        #expect(result.snippet == "needle")
    }
}
