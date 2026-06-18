import Foundation
import Testing
import Shared
import Agents
import Tooling

struct AgentsTests {
    @Test func routesExplicitAndAutoTasksDeterministically() {
        let router = AgentRouter()

        #expect(router.route(for: AgentTask(prompt: "anything", kind: .architecture)) == .orchestrator)
        #expect(router.route(for: AgentTask(prompt: "run tests", kind: .test)) == .utility)
        #expect(router.route(for: AgentTask(prompt: "please plan a refactor", kind: .auto)) == .orchestrator)
        #expect(router.route(for: AgentTask(prompt: "summarize this file", kind: .auto)) == .utility)
    }

    @Test func forcedRouterUsesSingleAgentRouteForEveryTask() {
        let router = AgentRouter(forcedRoute: .utility)

        #expect(router.route(for: AgentTask(prompt: "design the architecture", kind: .architecture)) == .utility)
        #expect(router.route(for: AgentTask(prompt: "please plan a refactor", kind: .auto)) == .utility)
        #expect(router.route(for: AgentTask(prompt: "run tests", kind: .test)) == .utility)
    }

    @Test func contextBuilderBudgetsSearchHitsAndSnippets() async throws {
        let provider = FakeSearchProvider(hits: [
            SearchHit(relativePath: "A.swift", score: 0.1, snippet: String(repeating: "a", count: 80)),
            SearchHit(relativePath: "B.swift", score: 0.2, snippet: String(repeating: "b", count: 80)),
            SearchHit(relativePath: "C.swift", score: 0.3, snippet: "unused"),
        ])
        let builder = ContextBuilder(
            searchProvider: provider,
            maxSearchResults: 2,
            maxContextCharacters: 120,
            maxSnippetCharacters: 40)

        let context = try await builder.build(task: AgentTask(prompt: "find auth"))

        #expect(context.hits.map(\.relativePath) == ["A.swift", "B.swift"])
        #expect(context.truncated)
        #expect(context.rendered.contains("[truncated]"))
        #expect(!context.rendered.contains("C.swift"))
    }

    @Test func modelAgentsConvertTokenStreamToResult() async throws {
        let model = FakeModelClient(chunks: [
            TokenChunk(text: "hel", index: 0, isFinal: false),
            TokenChunk(text: "lo", index: 1, isFinal: false),
            TokenChunk(text: "", index: 2, isFinal: true, info: .init(generationTokenCount: 2)),
        ])
        let agent = OrchestratorAgent(model: model)

        let result = try await agent.execute(task: AgentTask(prompt: "plan", kind: .plan))

        #expect(result.route == .orchestrator)
        #expect(result.text == "hello")
        #expect(result.completionInfo?.generationTokenCount == 2)
        #expect(await model.requestRoles() == [.orchestrator])
    }

    @Test func orchestratorRunEmitsEventsInOrder() async throws {
        let temp = try TempAgentWorkspace()
        try temp.write("hello", to: "note.txt")
        let toolLoop = try ToolExecutionLoop(root: temp.url, policy: ToolExecutionPolicy(networkEnabled: true))
        let model = FakeModelClient(chunks: [
            TokenChunk(text: "done", index: 0, isFinal: false),
            TokenChunk(text: "", index: 1, isFinal: true),
        ])
        let agent = UtilityAgent(model: model)
        let orchestrator = AgentOrchestrator(
            orchestrator: OrchestratorAgent(model: model),
            utility: agent,
            contextBuilder: ContextBuilder(searchProvider: FakeSearchProvider(hits: [])),
            toolLoop: toolLoop)

        let stream = await orchestrator.run(task: AgentTask(
            prompt: "read note",
            kind: .search,
            toolRequests: [.readFile(path: "note.txt")]))
        let events = try await collect(stream)

        #expect(events.first == .routeSelected(.utility))
        #expect(events.contains { if case .toolStarted = $0 { true } else { false } })
        #expect(events.contains { if case .toolFinished = $0 { true } else { false } })
        #expect(events.contains { if case .contextBuilt = $0 { true } else { false } })
        #expect(events.contains(.token(TokenChunk(text: "done", index: 0, isFinal: false))))
        #expect(events.last.map { if case .completed = $0 { true } else { false } } == true)
    }

    @Test func retryPolicyRetriesTransientGenerationOnce() async throws {
        let model = FakeModelClient(
            chunks: [
                TokenChunk(text: "ok", index: 0, isFinal: false),
                TokenChunk(text: "", index: 1, isFinal: true),
            ],
            failuresBeforeSuccess: 1)
        let orchestrator = AgentOrchestrator(
            orchestrator: OrchestratorAgent(model: model),
            utility: UtilityAgent(model: model))

        let result = try await orchestrator.execute(task: AgentTask(prompt: "summarize", kind: .summarize))

        #expect(result.text == "ok")
        #expect(await model.attemptCount() == 2)
    }

    @Test func retryPolicyDoesNotRetryCancellation() async throws {
        let model = FakeModelClient(error: InferenceError.cancelled)
        let orchestrator = AgentOrchestrator(
            orchestrator: OrchestratorAgent(model: model),
            utility: UtilityAgent(model: model))

        do {
            _ = try await orchestrator.execute(task: AgentTask(prompt: "summarize", kind: .summarize))
            Issue.record("expected cancellation failure")
        } catch {
            #expect(await model.attemptCount() == 1)
        }
    }

    @Test func deniedWriteToolFailsBeforeModelGeneration() async throws {
        let temp = try TempAgentWorkspace()
        let toolLoop = try ToolExecutionLoop(root: temp.url)
        let model = FakeModelClient(chunks: [TokenChunk(text: "unused", index: 0, isFinal: true)])
        let orchestrator = AgentOrchestrator(
            orchestrator: OrchestratorAgent(model: model),
            utility: UtilityAgent(model: model),
            toolLoop: toolLoop)

        do {
            _ = try await orchestrator.execute(task: AgentTask(
                prompt: "write",
                kind: .simpleQuestion,
                toolRequests: [.writeFile(path: "a.txt", contents: "blocked")]))
            Issue.record("expected tool failure")
        } catch let error as AgentError {
            if case .toolFailed = error {
                #expect(await model.attemptCount() == 0)
            } else {
                Issue.record("unexpected error \(error)")
            }
        }
    }

    @Test func fakeEndToEndAgentFlowUsesSearchToolsAndModel() async throws {
        let temp = try TempAgentWorkspace()
        try await temp.run(["git", "init"])
        try temp.write("content", to: "file.txt")
        try FileManager.default.createDirectory(at: temp.url.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try temp.write("#!/usr/bin/env bash\necho ok\n", to: "scripts/test.sh")
        try await temp.run(["chmod", "+x", "scripts/test.sh"])

        let trustedPolicy = ToolExecutionPolicy(networkEnabled: true)
        let toolLoop = try ToolExecutionLoop(root: temp.url, policy: trustedPolicy)
        let model = FakeModelClient(chunks: [
            TokenChunk(text: "stable", index: 0, isFinal: false),
            TokenChunk(text: "", index: 1, isFinal: true),
        ])
        let orchestrator = AgentOrchestrator(
            orchestrator: OrchestratorAgent(model: model),
            utility: UtilityAgent(model: model),
            contextBuilder: ContextBuilder(searchProvider: FakeSearchProvider(hits: [
                SearchHit(relativePath: "file.txt", score: 0.1, snippet: "content"),
            ])),
            toolLoop: toolLoop)

        let result = try await orchestrator.execute(task: AgentTask(
            prompt: "summarize file",
            kind: .summarize,
            toolRequests: [.readFile(path: "file.txt"), .gitStatus, .runTests(arguments: [])]))

        #expect(result.route == .utility)
        #expect(result.text == "stable")
        #expect(result.toolResults.count == 3)
        #expect(result.toolResults[0].stdout == "content")
        #expect(result.toolResults[2].stdout.contains("ok"))
    }

    @Test func nativeToolCallRunsThenRegeneratesFinalAnswer() async throws {
        let temp = try TempAgentWorkspace()
        try temp.write("secret", to: "note.txt")
        let toolLoop = try ToolExecutionLoop(root: temp.url)
        let model = FakeModelClient(streams: [
            [
                TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                    name: "read_file",
                    arguments: ["path": .string("note.txt")])),
                TokenChunk(text: "", index: 1, isFinal: true),
            ],
            [
                TokenChunk(text: "saw secret", index: 0, isFinal: false),
                TokenChunk(text: "", index: 1, isFinal: true),
            ],
        ])
        let agent = UtilityAgent(model: model, toolLoop: toolLoop)

        let result = try await agent.execute(task: AgentTask(prompt: "read note", kind: .search))

        #expect(result.text == "saw secret")
        #expect(result.toolResults.map(\.request) == [.readFile(path: "note.txt")])
        #expect(await model.requestCount() == 2)
        #expect(await model.requests().first?.tools.map(\.name).contains("read_file") == true)
        #expect(await model.requests().last?.input.containsToolMessage(containing: "secret") == true)
    }

    @Test func functionSchemaTextLeakRetriesWithoutAdvertisedTools() async throws {
        let leakedSchema = """
        {
          "function" : {
            "description" : "Describe a project.",
            "name" : "describe_project",
            "parameters" : {
              "additionalProperties" : false,
              "properties" : {
                "name" : {
                  "description" : "Project name.",
                  "type" : "string"
                }
              },
              "required" : [
                "name"
              ],
              "type" : "object"
            }
          },
          "type" : "function"
        }
        """
        let model = FakeModelClient(streams: [
            [
                TokenChunk(text: leakedSchema, index: 0, isFinal: false),
                TokenChunk(text: "", index: 1, isFinal: true),
            ],
            [
                TokenChunk(text: "This project is a native local AI coding workspace.", index: 0, isFinal: false),
                TokenChunk(text: "", index: 1, isFinal: true),
            ],
        ])
        let agent = UtilityAgent(model: model, toolRegistry: WorkspaceToolRegistry())

        let result = try await agent.execute(task: AgentTask(prompt: "What is this project about?", kind: .simpleQuestion))

        #expect(result.text == "This project is a native local AI coding workspace.")
        let requests = await model.requests()
        #expect(requests.count == 2)
        #expect(requests[0].tools.isEmpty == false)
        #expect(requests[1].tools.isEmpty)
    }

    @Test func nativeLoopSupportsMultipleToolCallsInOneIteration() async throws {
        let temp = try TempAgentWorkspace()
        try await temp.run(["git", "init"])
        try temp.write("hello", to: "file.txt")
        let trustedPolicy = ToolExecutionPolicy(networkEnabled: true)
        let toolLoop = try ToolExecutionLoop(root: temp.url, policy: trustedPolicy)
        let model = FakeModelClient(streams: [
            [
                TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                    name: "read_file",
                    arguments: ["path": .string("file.txt")])),
                TokenChunk(text: "", index: 1, isFinal: false, toolCall: ModelToolCall(name: "git_status")),
                TokenChunk(text: "", index: 2, isFinal: true),
            ],
            [
                TokenChunk(text: "done", index: 0, isFinal: false),
                TokenChunk(text: "", index: 1, isFinal: true),
            ],
        ])
        let agent = UtilityAgent(model: model, toolLoop: toolLoop)

        let result = try await agent.execute(task: AgentTask(prompt: "inspect", kind: .search))

        #expect(result.text == "done")
        #expect(result.toolResults.count == 2)
        #expect(result.toolResults.map(\.request) == [.readFile(path: "file.txt"), .gitStatus])
    }

    @Test func explicitPreToolsAndNativeToolsAreBothReturned() async throws {
        let temp = try TempAgentWorkspace()
        try temp.write("pre", to: "pre.txt")
        try temp.write("native", to: "native.txt")
        let toolLoop = try ToolExecutionLoop(root: temp.url)
        let model = FakeModelClient(streams: [
            [
                TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                    name: "read_file",
                    arguments: ["path": .string("native.txt")])),
                TokenChunk(text: "", index: 1, isFinal: true),
            ],
            [
                TokenChunk(text: "combined", index: 0, isFinal: false),
                TokenChunk(text: "", index: 1, isFinal: true),
            ],
        ])
        let orchestrator = AgentOrchestrator(
            orchestrator: OrchestratorAgent(model: model, toolLoop: toolLoop),
            utility: UtilityAgent(model: model, toolLoop: toolLoop),
            toolLoop: toolLoop)

        let result = try await orchestrator.execute(task: AgentTask(
            prompt: "combine",
            kind: .simpleQuestion,
            toolRequests: [.readFile(path: "pre.txt")]))

        #expect(result.text == "combined")
        #expect(result.toolResults.map(\.request) == [.readFile(path: "pre.txt"), .readFile(path: "native.txt")])
    }

    @Test func nativeLoopFailsAtMaxToolIterationsWithoutRetry() async throws {
        let temp = try TempAgentWorkspace()
        try temp.write("x", to: "x.txt")
        let toolLoop = try ToolExecutionLoop(root: temp.url)
        let model = FakeModelClient(streams: [[
            TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                name: "read_file",
                arguments: ["path": .string("x.txt")])),
            TokenChunk(text: "", index: 1, isFinal: true),
        ]])
        let agent = UtilityAgent(
            model: model,
            toolLoop: toolLoop,
            loopPolicy: AgentLoopPolicy(maxToolIterations: 0))

        await #expect(throws: AgentError.toolIterationLimitExceeded(0)) {
            _ = try await agent.execute(task: AgentTask(prompt: "loop", kind: .search))
        }
        #expect(await model.requestCount() == 1)
    }

    // MARK: - Autonomous verify→fix loop

    @Test func verifyLoopFeedsFailureBackThenCompletesGreen() async throws {
        let temp = try TempAgentWorkspace()
        try temp.write("alpha\n", to: "f.txt")
        let policy = ToolExecutionPolicy(allowsWrites: true)
        let toolLoop = try ToolExecutionLoop(root: temp.url, policy: policy)
        let spy = VerifierSpy([
            VerificationOutcome(passed: false, summary: "`swift build` failed (exit 1)", details: "error: expected ';'"),
            VerificationOutcome(passed: true, summary: "passed: swift build"),
        ])
        let verifier: WorkspaceVerifier = { paths in await spy.verify(paths) }
        let model = FakeModelClient(streams: [
            [TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                name: "edit_file",
                arguments: ["path": .string("f.txt"), "old": .string("alpha"), "new": .string("beta")])),
             TokenChunk(text: "", index: 1, isFinal: true)],
            [TokenChunk(text: "done v1", index: 0, isFinal: true)],
            [TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                name: "edit_file",
                arguments: ["path": .string("f.txt"), "old": .string("beta"), "new": .string("gamma")])),
             TokenChunk(text: "", index: 1, isFinal: true)],
            [TokenChunk(text: "done v2", index: 0, isFinal: true)],
        ])
        let agent = UtilityAgent(
            model: model,
            toolLoop: toolLoop,
            verifier: verifier,
            toolRegistry: WorkspaceToolRegistry(policy: policy),
            loopPolicy: AgentLoopPolicy(maxToolIterations: 4, maxVerifyAttempts: 2))

        let events = try await collectEvents(agent.run(task: AgentTask(prompt: "edit", kind: .auto)))

        #expect(await spy.callCount() == 2)
        #expect(verificationStarts(events) == 2)
        #expect(verificationOutcomes(events) == [false, true])
        #expect(completedResult(events)?.text.contains("done v2") == true)
        // The failure detail was handed back to the model on the retry pass.
        #expect(await model.requests().contains { request in
            requestMentions(request, "expected ';'")
        })
        #expect(try String(contentsOf: temp.url.appendingPathComponent("f.txt"), encoding: .utf8) == "gamma\n")
    }

    @Test func verifyLoopPassesFirstTryWithoutExtraIteration() async throws {
        let temp = try TempAgentWorkspace()
        try temp.write("alpha\n", to: "f.txt")
        let policy = ToolExecutionPolicy(allowsWrites: true)
        let toolLoop = try ToolExecutionLoop(root: temp.url, policy: policy)
        let spy = VerifierSpy([VerificationOutcome(passed: true, summary: "passed: swift build")])
        let model = FakeModelClient(streams: [
            [TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                name: "edit_file",
                arguments: ["path": .string("f.txt"), "old": .string("alpha"), "new": .string("beta")])),
             TokenChunk(text: "", index: 1, isFinal: true)],
            [TokenChunk(text: "all done", index: 0, isFinal: true)],
        ])
        let agent = UtilityAgent(
            model: model,
            toolLoop: toolLoop,
            verifier: { paths in await spy.verify(paths) },
            toolRegistry: WorkspaceToolRegistry(policy: policy),
            loopPolicy: AgentLoopPolicy(maxToolIterations: 4, maxVerifyAttempts: 2))

        let events = try await collectEvents(agent.run(task: AgentTask(prompt: "edit", kind: .auto)))

        #expect(await spy.callCount() == 1)
        #expect(verificationStarts(events) == 1)
        #expect(verificationOutcomes(events) == [true])
        #expect(completedResult(events)?.text.contains("all done") == true)
    }

    @Test func verifyLoopAbsentWhenVerifierNotWired() async throws {
        let temp = try TempAgentWorkspace()
        try temp.write("alpha\n", to: "f.txt")
        let policy = ToolExecutionPolicy(allowsWrites: true)
        let toolLoop = try ToolExecutionLoop(root: temp.url, policy: policy)
        let model = FakeModelClient(streams: [
            [TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                name: "edit_file",
                arguments: ["path": .string("f.txt"), "old": .string("alpha"), "new": .string("beta")])),
             TokenChunk(text: "", index: 1, isFinal: true)],
            [TokenChunk(text: "done", index: 0, isFinal: true)],
        ])
        let agent = UtilityAgent(
            model: model,
            toolLoop: toolLoop,
            toolRegistry: WorkspaceToolRegistry(policy: policy))

        let events = try await collectEvents(agent.run(task: AgentTask(prompt: "edit", kind: .auto)))

        #expect(verificationStarts(events) == 0)
        #expect(completedResult(events)?.text.contains("done") == true)
    }

    @Test func verifyLoopNoProgressGuardStopsAndReportsHonestly() async throws {
        let temp = try TempAgentWorkspace()
        try temp.write("alpha\n", to: "f.txt")
        let policy = ToolExecutionPolicy(allowsWrites: true)
        let toolLoop = try ToolExecutionLoop(root: temp.url, policy: policy)
        let spy = VerifierSpy([VerificationOutcome(passed: false, summary: "`swift build` failed (exit 1)", details: "boom")])
        let model = FakeModelClient(streams: [
            [TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                name: "edit_file",
                arguments: ["path": .string("f.txt"), "old": .string("alpha"), "new": .string("beta")])),
             TokenChunk(text: "", index: 1, isFinal: true)],
            [TokenChunk(text: "first done", index: 0, isFinal: true)],
            [TokenChunk(text: "I cannot fix this", index: 0, isFinal: true)],
        ])
        let agent = UtilityAgent(
            model: model,
            toolLoop: toolLoop,
            verifier: { paths in await spy.verify(paths) },
            toolRegistry: WorkspaceToolRegistry(policy: policy),
            loopPolicy: AgentLoopPolicy(maxToolIterations: 4, maxVerifyAttempts: 2))

        let events = try await collectEvents(agent.run(task: AgentTask(prompt: "edit", kind: .auto)))

        // A turn that wrote nothing after the failure does not re-trigger verification.
        #expect(await spy.callCount() == 1)
        #expect(verificationStarts(events) == 1)
        #expect(completedResult(events)?.text.contains("did not pass") == true)
    }

    @Test func verifyLoopReportsHonestlyWhenAttemptsExhausted() async throws {
        let temp = try TempAgentWorkspace()
        try temp.write("alpha\n", to: "f.txt")
        let policy = ToolExecutionPolicy(allowsWrites: true)
        let toolLoop = try ToolExecutionLoop(root: temp.url, policy: policy)
        let spy = VerifierSpy([
            VerificationOutcome(passed: false, summary: "fail #1", details: "e1"),
            VerificationOutcome(passed: false, summary: "fail #2", details: "e2"),
        ])
        let model = FakeModelClient(streams: [
            [TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                name: "edit_file",
                arguments: ["path": .string("f.txt"), "old": .string("alpha"), "new": .string("beta")])),
             TokenChunk(text: "", index: 1, isFinal: true)],
            [TokenChunk(text: "done a", index: 0, isFinal: true)],
            [TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                name: "edit_file",
                arguments: ["path": .string("f.txt"), "old": .string("beta"), "new": .string("gamma")])),
             TokenChunk(text: "", index: 1, isFinal: true)],
            [TokenChunk(text: "done b", index: 0, isFinal: true)],
        ])
        let agent = UtilityAgent(
            model: model,
            toolLoop: toolLoop,
            verifier: { paths in await spy.verify(paths) },
            toolRegistry: WorkspaceToolRegistry(policy: policy),
            loopPolicy: AgentLoopPolicy(maxToolIterations: 4, maxVerifyAttempts: 1))

        let events = try await collectEvents(agent.run(task: AgentTask(prompt: "edit", kind: .auto)))

        #expect(await spy.callCount() == 2)
        #expect(verificationOutcomes(events) == [false, false])
        #expect(completedResult(events)?.text.contains("did not pass after 1 fix attempt") == true)
    }

    // MARK: - Sub-agent delegation

    @Test func subagentDispatcherRunsSubagentAndReturnsSummary() async throws {
        let model = FakeModelClient(chunks: [
            TokenChunk(text: "X is set in Config.swift:42", index: 0, isFinal: true),
        ])
        let dispatcher = SubagentDispatcher(catalog: .default, agent: UtilityAgent(model: model))
        let result = try await dispatcher.dispatch(prompt: "where is X configured", agentID: "explore")
        #expect(result.text == "X is set in Config.swift:42")
    }

    @Test func subagentDispatcherRejectsNonSubagentID() async throws {
        let model = FakeModelClient(chunks: [TokenChunk(text: "unused", index: 0, isFinal: true)])
        let dispatcher = SubagentDispatcher(catalog: .default, agent: UtilityAgent(model: model))
        await #expect(throws: AgentCatalogError.notSubagent("build")) {
            _ = try await dispatcher.dispatch(prompt: "p", agentID: "build")
        }
    }

    private func collectEvents(_ stream: AsyncThrowingStream<AgentEvent, Error>) async throws -> [AgentEvent] {
        var events: [AgentEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private func verificationStarts(_ events: [AgentEvent]) -> Int {
        events.filter { if case .verificationStarted = $0 { return true } else { return false } }.count
    }

    private func verificationOutcomes(_ events: [AgentEvent]) -> [Bool] {
        events.compactMap { event in
            if case let .verificationFinished(passed, _) = event { return passed } else { return nil }
        }
    }

    private func completedResult(_ events: [AgentEvent]) -> AgentResult? {
        events.compactMap { event in
            if case let .completed(result) = event { return result } else { return nil }
        }.last
    }

    private func requestMentions(_ request: GenerationRequest, _ needle: String) -> Bool {
        guard case let .messages(messages) = request.input else { return false }
        return messages.contains { $0.content.contains(needle) }
    }

    @Test func nativeLoopRejectsUnknownAndMalformedToolCalls() async throws {
        let temp = try TempAgentWorkspace()
        let toolLoop = try ToolExecutionLoop(root: temp.url)
        let unknown = FakeModelClient(chunks: [
            TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(name: "unknown")),
            TokenChunk(text: "", index: 1, isFinal: true),
        ])
        let malformed = FakeModelClient(chunks: [
            TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(name: "read_file")),
            TokenChunk(text: "", index: 1, isFinal: true),
        ])

        await #expect(throws: ToolError.unknownTool("unknown")) {
            _ = try await UtilityAgent(model: unknown, toolLoop: toolLoop).execute(task: AgentTask(prompt: "bad"))
        }
        await #expect(throws: ToolError.invalidToolArguments(tool: "read_file", reason: "missing required string 'path'")) {
            _ = try await UtilityAgent(model: malformed, toolLoop: toolLoop).execute(task: AgentTask(prompt: "bad"))
        }
    }

    @Test func nonZeroToolResultIsFedBackToModel() async throws {
        let temp = try TempAgentWorkspace()
        let policy = ToolExecutionPolicy(
            networkEnabled: true,
            allowedCommands: [ToolCommandPattern(executable: "/bin/sh")])
        let toolLoop = try ToolExecutionLoop(root: temp.url, policy: policy)
        let model = FakeModelClient(streams: [
            [
                TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                    name: "shell",
                    arguments: ["command": .array([.string("/bin/sh"), .string("-c"), .string("echo bad >&2; exit 7")])])),
                TokenChunk(text: "", index: 1, isFinal: true),
            ],
            [
                TokenChunk(text: "saw failure", index: 0, isFinal: false),
                TokenChunk(text: "", index: 1, isFinal: true),
            ],
        ])
        let agent = UtilityAgent(
            model: model,
            toolLoop: toolLoop,
            toolRegistry: WorkspaceToolRegistry(policy: policy))

        let result = try await agent.execute(task: AgentTask(prompt: "run failing command"))

        #expect(result.toolResults.first?.exitCode == 7)
        #expect(await model.requests().last?.input.containsToolMessage(containing: "exit=7") == true)
    }

    @Test func utilityAgentAppliesResourceBudgetToGenerationRequest() async throws {
        let model = FakeModelClient(chunks: [
            TokenChunk(text: "ok", index: 0, isFinal: false),
            TokenChunk(text: "", index: 1, isFinal: true),
        ])
        let agent = UtilityAgent(model: model, resourceBudget: .smallRAM)

        _ = try await agent.execute(task: AgentTask(
            prompt: "summarize",
            maxTokens: 10_000,
            contextTokenBudget: 1_024))

        let request = try #require(await model.requests().first)
        #expect(request.maxTokens == ResourceBudget.smallRAM.utilityMaxTokens)
        #expect(request.contextTokenBudget == 1_024)
    }

    @Test func reasoningAgentRequestsUseReasoningAwareTokenBudget() async throws {
        let model = FakeModelClient(chunks: [
            TokenChunk(text: "ok", index: 0, isFinal: false),
            TokenChunk(text: "", index: 1, isFinal: true),
        ])
        let agent = UtilityAgent(model: model, resourceBudget: .smallRAM)

        _ = try await agent.execute(task: AgentTask(prompt: "think", maxTokens: 10_000, reasoningEffort: .low))

        let request = try #require(await model.requests().first)
        #expect(request.reasoningEffort == .low)
        #expect(request.maxTokens == ResourceBudget.smallRAM.maxTokens(for: .utility, reasoningEffort: .low))
    }

    @Test func utilityAgentIncludesObservationsWithoutPrebuiltContext() async throws {
        let model = FakeModelClient(chunks: [
            TokenChunk(text: "ok", index: 0, isFinal: false),
            TokenChunk(text: "", index: 1, isFinal: true),
        ])
        let agent = UtilityAgent(model: model)

        _ = try await agent.execute(task: AgentTask(
            prompt: "Tell me more.",
            observations: ["Previous conversation:\nAssistant: Priscilla is a parrot."]))

        let request = try #require(await model.requests().first)
        #expect(request.input.containsMessage(containing: "Previous conversation:"))
        #expect(request.input.containsMessage(containing: "Priscilla is a parrot."))
    }

    @Test func utilityAgentRequestsMarkdownResponseFormat() async throws {
        let model = FakeModelClient(chunks: [
            TokenChunk(text: "ok", index: 0, isFinal: false),
            TokenChunk(text: "", index: 1, isFinal: true),
        ])
        let agent = UtilityAgent(model: model)

        _ = try await agent.execute(task: AgentTask(prompt: "create an html file"))

        let request = try #require(await model.requests().first)
        #expect(request.input.containsMessage(containing: "Answer in Markdown by default."))
        #expect(request.input.containsMessage(containing: "Use fenced code blocks with language tags"))
        #expect(request.input.containsMessage(containing: "Latest request"))
    }

    @Test func agentsDoNotReusePersistentKVCacheAcrossRuns() async throws {
        let model = FakeModelClient(chunks: [
            TokenChunk(text: "ok", index: 0, isFinal: false),
            TokenChunk(text: "", index: 1, isFinal: true),
        ])
        let agent = OrchestratorAgent(model: model)

        _ = try await agent.execute(task: AgentTask(prompt: "describe project", kind: .architecture))

        let request = try #require(await model.requests().first)
        #expect(request.role == .orchestrator)
        #expect(request.reuseKVCache == false)
    }

    @Test func nativeToolLoopCancellationStopsToolExecution() async throws {
        let temp = try TempAgentWorkspace()
        let policy = ToolExecutionPolicy(
            timeoutSeconds: 5,
            allowedCommands: [ToolCommandPattern(executable: "/bin/sleep", requiresNetworkPermission: false)])
        let toolLoop = try ToolExecutionLoop(root: temp.url, policy: policy)
        let model = FakeModelClient(chunks: [
            TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                name: "shell",
                arguments: ["command": .array([.string("/bin/sleep"), .string("2")])])),
            TokenChunk(text: "", index: 1, isFinal: true),
        ])
        let agent = UtilityAgent(
            model: model,
            toolLoop: toolLoop,
            toolRegistry: WorkspaceToolRegistry(policy: policy))

        let task = Task {
            try await agent.execute(task: AgentTask(prompt: "sleep"))
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch let error as ToolError {
            #expect(error == .cancelled)
        } catch let error as AgentError {
            #expect(error == .cancelled)
        } catch is CancellationError {
        }
    }

    @Test func fakeNativeEndToEndAgentFlowUsesSearchToolsAndModel() async throws {
        let temp = try TempAgentWorkspace()
        try await temp.run(["git", "init"])
        try temp.write("content", to: "file.txt")
        try FileManager.default.createDirectory(at: temp.url.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try temp.write("#!/usr/bin/env bash\necho ok\n", to: "scripts/test.sh")
        try await temp.run(["chmod", "+x", "scripts/test.sh"])

        let trustedPolicy = ToolExecutionPolicy(networkEnabled: true)
        let toolLoop = try ToolExecutionLoop(root: temp.url, policy: trustedPolicy)
        let model = FakeModelClient(streams: [
            [
                TokenChunk(text: "", index: 0, isFinal: false, toolCall: ModelToolCall(
                    name: "read_file",
                    arguments: ["path": .string("file.txt")])),
                TokenChunk(text: "", index: 1, isFinal: false, toolCall: ModelToolCall(name: "git_status")),
                TokenChunk(text: "", index: 2, isFinal: false, toolCall: ModelToolCall(
                    name: "run_tests",
                    arguments: ["arguments": .array([])])),
                TokenChunk(text: "", index: 3, isFinal: true),
            ],
            [
                TokenChunk(text: "stable", index: 0, isFinal: false),
                TokenChunk(text: "", index: 1, isFinal: true),
            ],
        ])
        let orchestrator = AgentOrchestrator(
            orchestrator: OrchestratorAgent(
                model: model,
                toolLoop: toolLoop,
                toolRegistry: WorkspaceToolRegistry(policy: trustedPolicy)),
            utility: UtilityAgent(
                model: model,
                toolLoop: toolLoop,
                toolRegistry: WorkspaceToolRegistry(policy: trustedPolicy)),
            contextBuilder: ContextBuilder(searchProvider: FakeSearchProvider(hits: [
                SearchHit(relativePath: "file.txt", score: 0.1, snippet: "content"),
            ])),
            toolLoop: toolLoop)

        let result = try await orchestrator.execute(task: AgentTask(prompt: "summarize file", kind: .summarize))

        #expect(result.text == "stable")
        #expect(result.toolResults.count == 3)
        #expect(result.toolResults[2].stdout.contains("ok"))
    }
}

private func collect(_ stream: AsyncThrowingStream<AgentEvent, Error>) async throws -> [AgentEvent] {
    var events: [AgentEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

private struct FakeSearchProvider: WorkspaceSearchProviding {
    var hits: [SearchHit]
    func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        Array(hits.prefix(limit))
    }
}

private actor VerifierSpy {
    private let outcomes: [VerificationOutcome?]
    private(set) var receivedPaths: [[String]] = []

    init(_ outcomes: [VerificationOutcome?]) {
        self.outcomes = outcomes
    }

    func verify(_ paths: [String]) -> VerificationOutcome? {
        let index = receivedPaths.count
        receivedPaths.append(paths)
        if index < outcomes.count { return outcomes[index] }
        return outcomes.last ?? nil
    }

    func callCount() -> Int { receivedPaths.count }
}

private actor FakeModelClient: AgentModelClient {
    private var streams: [[TokenChunk]]
    private var failuresBeforeSuccess: Int
    private var error: Error?
    private var attempts = 0
    private var roles: [ModelRole] = []
    private var recordedRequests: [GenerationRequest] = []

    init(chunks: [TokenChunk] = [], failuresBeforeSuccess: Int = 0, error: Error? = nil) {
        self.streams = [chunks]
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.error = error
    }

    init(streams: [[TokenChunk]], failuresBeforeSuccess: Int = 0, error: Error? = nil) {
        self.streams = streams
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.error = error
    }

    func stream(request: GenerationRequest) async -> AsyncThrowingStream<TokenChunk, Error> {
        attempts += 1
        roles.append(request.role)
        recordedRequests.append(request)
        if let error {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AgentError.generationFailed("transient"))
            }
        }
        let chunks: [TokenChunk]
        if streams.count > 1 {
            chunks = streams.removeFirst()
        } else {
            chunks = streams.first ?? []
        }
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    func attemptCount() -> Int { attempts }
    func requestCount() -> Int { attempts }
    func requestRoles() -> [ModelRole] { roles }
    func requests() -> [GenerationRequest] { recordedRequests }
}

private extension GenerationRequest.Input {
    func containsMessage(containing text: String) -> Bool {
        guard case let .messages(messages) = self else { return false }
        return messages.contains { $0.content.contains(text) }
    }

    func containsToolMessage(containing text: String) -> Bool {
        guard case let .messages(messages) = self else { return false }
        return messages.contains { $0.role == .tool && $0.content.contains(text) }
    }
}

private final class TempAgentWorkspace {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("if-agents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ text: String, to path: String) throws {
        let fileURL = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func run(_ command: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = url
        try process.run()
        process.waitUntilExit()
    }
}
