import Foundation
import Testing
import Workspace

struct InstructionDiscoveryTests {
    @Test func discoversConfiguredAndNestedAgentsFilesInDeterministicOrder() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write("configured", to: "CONFIG.md", in: root)
        try TempDir.write("root agents", to: "AGENTS.md", in: root)
        try TempDir.write("sources agents", to: "Sources/AGENTS.md", in: root)
        try TempDir.write("main", to: "Sources/App/Main.swift", in: root)

        let instructions = try InstructionDiscovery(root: root)
            .discover(for: "Sources/App/Main.swift", configuredPaths: ["CONFIG.md"])

        #expect(instructions.map(\.relativePath) == ["CONFIG.md", "AGENTS.md", "Sources/AGENTS.md"])
        #expect(instructions.map(\.kind) == [.configured, .agentsFile, .agentsFile])
        #expect(instructions.map(\.depth) == [-1, 0, 1])
    }

    @Test func rejectsEscapesAndBoundsInstructionContent() throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try TempDir.write("123456789", to: "AGENTS.md", in: root)

        let instruction = try #require(try InstructionDiscovery(root: root, maxInstructionBytes: 4).discover().first)
        #expect(instruction.text == "1234")
        #expect(instruction.isTruncated)

        #expect(throws: InstructionDiscoveryError.pathEscapesWorkspace("../outside.md")) {
            _ = try InstructionDiscovery(root: root).discover(configuredPaths: ["../outside.md"])
        }
    }
}
