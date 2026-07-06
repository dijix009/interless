import Foundation
import Testing
import Shared
@testable import CloudInference

struct AnthropicModelClientTests {

    @Test func resolverDistinguishesCloudFromLocal() {
        #expect(CloudModelResolver.resolve("anthropic/claude-opus-4-8")
            == CloudModelID(provider: .anthropic, model: "claude-opus-4-8"))
        // Hugging Face repo ids and bare ids stay local.
        #expect(CloudModelResolver.resolve("mlx-community/gemma-2-2b-it-4bit") == nil)
        #expect(CloudModelResolver.resolve("claude") == nil)
        #expect(CloudModelResolver.isCloud("anthropic/claude-haiku-4-5"))
        #expect(!CloudModelResolver.isCloud("mlx-community/x"))
    }

    @Test func streamsTextDeltasThenToolUseThenFinal() async throws {
        let transport = FakeHTTPTransport(status: 200, lines: [
            "event: message_start",
            #"data: {"type":"message_start","message":{"usage":{"input_tokens":10}}}"#,
            "",
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            "",
            "event: content_block_start",
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tu_1","name":"read_file"}}"#,
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\":\"a.txt\"}"}}"#,
            "event: content_block_stop",
            #"data: {"type":"content_block_stop","index":1}"#,
            "event: message_delta",
            #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":5}}"#,
            "event: message_stop",
            #"data: {"type":"message_stop"}"#,
        ])
        let client = AnthropicModelClient(transport: transport, keyProvider: StubKeyProvider(key: "k"))
        let chunks = try await collect(client.stream(model: "claude-opus-4-8", request: .prompt("hi")))

        // Ascending index, exactly one terminal chunk.
        #expect(chunks.map(\.index) == Array(0..<chunks.count))
        #expect(chunks.filter(\.isFinal).count == 1)
        #expect(chunks.last?.isFinal == true)

        #expect(chunks.compactMap { $0.text.isEmpty ? nil : $0.text } == ["Hello"])
        let toolCalls = chunks.compactMap(\.toolCall)
        #expect(toolCalls == [ModelToolCall(name: "read_file", arguments: ["path": .string("a.txt")])])
        #expect(chunks.last?.info?.stopReason == "tool_use")
        #expect(chunks.last?.info?.promptTokenCount == 10)
        #expect(chunks.last?.info?.generationTokenCount == 5)
    }

    @Test func mapsRequestToAnthropicBody() async throws {
        let transport = FakeHTTPTransport(status: 200, lines: [])
        let client = AnthropicModelClient(transport: transport, keyProvider: StubKeyProvider(key: "k"))
        let request = GenerationRequest(
            role: .orchestrator,
            input: .messages([
                .init(role: .system, content: "You are helpful."),
                .init(role: .user, content: "hi"),
                .init(role: .tool, content: "r1"),
                .init(role: .tool, content: "r2"),
            ]),
            maxTokens: 256,
            temperature: 0.3,
            tools: [ToolDefinition(
                name: "read_file",
                description: "Read a file",
                parameters: .object(["type": .string("object")]))])

        _ = try await collect(client.stream(model: "claude-opus-4-8", request: request))

        let body = try #require(await transport.capturedRequest()?.body)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: body)
        let object = try #require(decoded.objectValue)

        #expect(object["model"]?.stringValue == "claude-opus-4-8")
        #expect(object["system"]?.stringValue == "You are helpful.")
        #expect(object["max_tokens"] == .int(256))
        #expect(object["stream"] == .bool(true))

        // system is hoisted out; tool turns become user text and merge with the
        // preceding user turn → a single alternating user message.
        let messages = try #require(object["messages"]?.arrayValueForTest)
        #expect(messages.count == 1)
        let first = try #require(messages.first?.objectValue)
        #expect(first["role"]?.stringValue == "user")
        let content = try #require(first["content"]?.stringValue)
        #expect(content.contains("hi"))
        #expect(content.contains("[tool result]"))
        #expect(content.contains("r1"))
        #expect(content.contains("r2"))

        // tools map to {name, description, input_schema}.
        let tools = try #require(object["tools"]?.arrayValueForTest)
        let tool = try #require(tools.first?.objectValue)
        #expect(tool["name"]?.stringValue == "read_file")
        #expect(tool["input_schema"] == .object(["type": .string("object")]))

        // x-api-key header is set from the key provider.
        #expect(await transport.capturedRequest()?.headers["x-api-key"] == "k")
    }

    @Test func nonOKStatusThrowsWithMessage() async throws {
        let transport = FakeHTTPTransport(status: 401, lines: [
            #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#,
        ])
        let client = AnthropicModelClient(transport: transport, keyProvider: StubKeyProvider(key: "bad"))
        do {
            _ = try await collect(client.stream(model: "claude-opus-4-8", request: .prompt("hi")))
            Issue.record("expected the 401 response to throw")
        } catch {
            let message = "\(error)"
            #expect(message.contains("401"))
            #expect(message.contains("invalid x-api-key"))
        }
    }

    @Test func missingKeyThrowsClearError() async throws {
        let client = AnthropicModelClient(transport: FakeHTTPTransport(status: 200, lines: []),
                                          keyProvider: StubKeyProvider(key: nil))
        await #expect(throws: InferenceError.self) { try await client.validate() }
        do {
            _ = try await collect(client.stream(model: "claude-opus-4-8", request: .prompt("hi")))
            Issue.record("expected a missing-key error")
        } catch {
            #expect("\(error)".contains("API key not set"))
        }
    }
}

// MARK: - Helpers

private func collect(_ stream: AsyncThrowingStream<TokenChunk, Error>) async throws -> [TokenChunk] {
    var result: [TokenChunk] = []
    for try await chunk in stream { result.append(chunk) }
    return result
}

private struct StubKeyProvider: CloudKeyProvider {
    let key: String?
    func apiKey(for provider: CloudProvider) async -> String? { key }
}

private actor FakeHTTPTransport: HTTPTransport {
    let status: Int
    let scriptedLines: [String]
    private var captured: HTTPRequestSpec?

    init(status: Int, lines: [String]) {
        self.status = status
        self.scriptedLines = lines
    }

    func stream(_ request: HTTPRequestSpec) async throws -> (head: HTTPResponseHead, lines: AsyncThrowingStream<String, Error>) {
        captured = request
        let scripted = scriptedLines
        let lines = AsyncThrowingStream<String, Error> { continuation in
            for line in scripted { continuation.yield(line) }
            continuation.finish()
        }
        return (HTTPResponseHead(statusCode: status), lines)
    }

    func capturedRequest() -> HTTPRequestSpec? { captured }
}

private extension JSONValue {
    /// Array accessor for tests (the Shared type exposes object/string/stringArray
    /// but not a plain array getter).
    var arrayValueForTest: [JSONValue]? {
        if case let .array(values) = self { return values }
        return nil
    }
}
