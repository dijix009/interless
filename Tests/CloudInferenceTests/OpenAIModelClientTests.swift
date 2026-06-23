import Foundation
import Testing
import Shared
@testable import CloudInference

struct OpenAIModelClientTests {

    @Test func resolverHandlesOpenAIIds() {
        #expect(CloudModelResolver.resolve("openai/gpt-4o")
            == CloudModelID(provider: .openai, model: "gpt-4o"))
        #expect(CloudModelResolver.isCloud("openai/gpt-4.1"))
    }

    @Test func streamsContentThenToolCallThenFinal() async throws {
        let transport = OpenAIFakeTransport(status: 200, lines: [
            #"data: {"choices":[{"delta":{"role":"assistant","content":""},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":""}}]},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"path\":\"a.txt\"}"}}]},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            #"data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5}}"#,
            "data: [DONE]",
        ])
        let client = OpenAIModelClient(transport: transport, keyProvider: OpenAIStubKey(key: "k"))
        let chunks = try await collectOpenAI(client.stream(model: "gpt-4o", request: .prompt("hi")))

        #expect(chunks.map(\.index) == Array(0..<chunks.count))
        #expect(chunks.filter(\.isFinal).count == 1)
        #expect(chunks.compactMap { $0.text.isEmpty ? nil : $0.text } == ["Hello"])
        #expect(chunks.compactMap(\.toolCall)
            == [ModelToolCall(name: "read_file", arguments: ["path": .string("a.txt")])])
        #expect(chunks.last?.info?.stopReason == "tool_calls")
        #expect(chunks.last?.info?.promptTokenCount == 10)
        #expect(chunks.last?.info?.generationTokenCount == 5)
    }

    @Test func mapsRequestToOpenAIBody() async throws {
        let transport = OpenAIFakeTransport(status: 200, lines: ["data: [DONE]"])
        let client = OpenAIModelClient(transport: transport, keyProvider: OpenAIStubKey(key: "k"))
        let request = GenerationRequest(
            role: .orchestrator,
            input: .messages([
                .init(role: .system, content: "You are helpful."),
                .init(role: .user, content: "hi"),
                .init(role: .tool, content: "r1"),
                .init(role: .tool, content: "r2"),
            ]),
            maxTokens: 256,
            tools: [ToolDefinition(name: "read_file", description: "Read a file",
                                   parameters: .object(["type": .string("object")]))])

        _ = try await collectOpenAI(client.stream(model: "gpt-4o", request: request))

        let body = try #require(await transport.capturedRequest()?.body)
        let object = try #require(try JSONDecoder().decode(JSONValue.self, from: body).objectValue)
        #expect(object["model"]?.stringValue == "gpt-4o")
        #expect(object["max_tokens"] == .int(256))
        #expect(object["stream"] == .bool(true))

        // system stays inline as a message; tool turns become user text and merge.
        guard case let .array(messages)? = object["messages"] else { Issue.record("no messages"); return }
        #expect(messages.count == 2)
        #expect(messages.first?.objectValue?["role"]?.stringValue == "system")
        let user = try #require(messages.last?.objectValue)
        #expect(user["role"]?.stringValue == "user")
        let content = try #require(user["content"]?.stringValue)
        #expect(content.contains("hi") && content.contains("r1") && content.contains("r2"))

        // tools use OpenAI's {type:"function", function:{…}} shape.
        guard case let .array(tools)? = object["tools"] else { Issue.record("no tools"); return }
        let tool = try #require(tools.first?.objectValue)
        #expect(tool["type"]?.stringValue == "function")
        #expect(tool["function"]?.objectValue?["name"]?.stringValue == "read_file")

        #expect(await transport.capturedRequest()?.headers["authorization"] == "Bearer k")
    }

    @Test func nonOKStatusThrowsWithMessage() async throws {
        let transport = OpenAIFakeTransport(status: 401, lines: [
            #"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#,
        ])
        let client = OpenAIModelClient(transport: transport, keyProvider: OpenAIStubKey(key: "bad"))
        do {
            _ = try await collectOpenAI(client.stream(model: "gpt-4o", request: .prompt("hi")))
            Issue.record("expected the 401 response to throw")
        } catch {
            let message = "\(error)"
            #expect(message.contains("401"))
            #expect(message.contains("Incorrect API key"))
        }
    }

    @Test func missingKeyThrowsClearError() async throws {
        let client = OpenAIModelClient(transport: OpenAIFakeTransport(status: 200, lines: []),
                                       keyProvider: OpenAIStubKey(key: nil))
        await #expect(throws: InferenceError.self) { try await client.validate() }
        do {
            _ = try await collectOpenAI(client.stream(model: "gpt-4o", request: .prompt("hi")))
            Issue.record("expected a missing-key error")
        } catch {
            #expect("\(error)".contains("API key not set"))
        }
    }
}

private func collectOpenAI(_ stream: AsyncThrowingStream<TokenChunk, Error>) async throws -> [TokenChunk] {
    var result: [TokenChunk] = []
    for try await chunk in stream { result.append(chunk) }
    return result
}

private struct OpenAIStubKey: CloudKeyProvider {
    let key: String?
    func apiKey(for provider: CloudProvider) async -> String? { key }
}

private actor OpenAIFakeTransport: HTTPTransport {
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
