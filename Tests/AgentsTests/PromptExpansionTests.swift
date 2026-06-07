import Foundation
import Testing
import Agents

struct PromptExpansionTests {
    @Test func promptExpanderResolvesMentionsAttachmentsAndDiagnostics() async {
        let files = ["README.md": "readme body"]
        let expander = PromptExpander(
            resolver: PromptExpansionResolver(
                readFile: { path, _ in files[path] },
                listDirectory: { path, _ in path == "Sources" ? ["Sources/App.swift"] : [] },
                resolveAgent: { id in id == "plan" ? "planning agent" : nil },
                resolveReference: { id in id == "docs" ? "reference docs" : nil },
                normalizeAttachment: { path, _ in
                    PromptAttachmentRecord(path: path, kind: "text", byteCount: 12)
                }),
            options: PromptExpansionOptions(maxMentionCharacters: 20, maxContextCharacters: 200))

        let expansion = await expander.expand(
            prompt: "Review @file:README.md @dir:Sources @reference:docs @agent:plan @missing.txt",
            attachments: ["notes.txt"])

        #expect(expansion.mentions.map(\.kind) == [.file, .directory, .reference, .agent])
        #expect(expansion.renderedContext.contains("readme body"))
        #expect(expansion.renderedContext.contains("Sources/App.swift"))
        #expect(expansion.renderedContext.contains("reference docs"))
        #expect(expansion.renderedContext.contains("planning agent"))
        #expect(expansion.attachments.map(\.path) == ["notes.txt"])
        #expect(expansion.diagnostics.contains { $0.contains("@file:missing.txt") })
    }

    @Test func contextEpochStoreReplacesCurrentEpochAndKeepsHistory() async {
        let store = ContextEpochStore()
        let sessionID = UUID()

        let first = await store.replace(sessionID: sessionID, agentID: "general", reason: .initial, context: "one")
        let second = await store.replace(sessionID: sessionID, agentID: "plan", reason: .agentSwitch, context: "two")

        #expect(first.revision == 1)
        #expect(second.revision == 2)
        #expect(second.contextHash != first.contextHash)
        #expect(await store.current(sessionID: sessionID) == second)
        #expect(await store.history(sessionID: sessionID).map(\.revision) == [1, 2])

        await store.clear(sessionID: sessionID)
        #expect(await store.current(sessionID: sessionID) == nil)
    }
}
