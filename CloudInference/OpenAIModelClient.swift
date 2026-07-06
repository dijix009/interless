import Foundation
import Shared

/// Streams from OpenAI's Chat Completions API and adapts it to Interless's
/// backend-agnostic `TokenChunk` stream. Sibling of `AnthropicModelClient` behind
/// the same `CloudModelClient` protocol; MLX-free, transport + key injected.
///
/// Tool calling is text-mode-consistent with the local path: prior tool results
/// are sent as plain user turns (no tool_call_id threading), while `tools` are
/// advertised so the model can emit fresh `tool_calls`, which stream
/// incrementally (name once, arguments across deltas) and are flushed as
/// `ModelToolCall` chunks when the turn finishes.
///
/// Note: `max_tokens` + `temperature` target the mainstream chat models
/// (gpt-4o / gpt-4.1 class). Reasoning models that require `max_completion_tokens`
/// or reject `temperature` are out of scope for this first cut.
public struct OpenAIModelClient: CloudModelClient {
    private let transport: any HTTPTransport
    private let keyProvider: any CloudKeyProvider
    private let baseURL: URL
    private let defaultMaxTokens: Int

    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        keyProvider: any CloudKeyProvider = KeychainCloudKeyProvider(),
        baseURL: URL = URL(string: "https://api.openai.com")!,
        defaultMaxTokens: Int = 4096
    ) {
        self.transport = transport
        self.keyProvider = keyProvider
        self.baseURL = baseURL
        self.defaultMaxTokens = defaultMaxTokens
    }

    public func validate() async throws {
        guard await keyProvider.apiKey(for: .openai) != nil else {
            throw InferenceError.generationFailed(Self.missingKeyMessage)
        }
    }

    public func stream(model: String, request: GenerationRequest) -> AsyncThrowingStream<TokenChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = await keyProvider.apiKey(for: .openai) else {
                        throw InferenceError.generationFailed(Self.missingKeyMessage)
                    }
                    let body = try Self.makeRequestBody(model: model, request: request, defaultMaxTokens: defaultMaxTokens)
                    let spec = HTTPRequestSpec(
                        url: baseURL.appendingPathComponent("v1/chat/completions"),
                        method: "POST",
                        headers: [
                            "authorization": "Bearer \(key)",
                            "content-type": "application/json",
                            "accept": "text/event-stream",
                        ],
                        body: body)
                    let (head, lines) = try await transport.stream(spec)
                    guard head.statusCode == 200 else {
                        var raw = ""
                        for try await line in lines { raw += line }
                        throw InferenceError.generationFailed(Self.errorMessage(status: head.statusCode, body: raw))
                    }

                    var index = 0
                    var promptTokens = 0
                    var completionTokens = 0
                    var stopReason = ""
                    // Tool calls stream incrementally, keyed by their position.
                    var toolNames: [Int: String] = [:]
                    var toolArguments: [Int: String] = [:]

                    for try await line in lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data) else {
                            continue
                        }
                        if let usage = chunk.usage {
                            promptTokens = usage.prompt_tokens ?? promptTokens
                            completionTokens = usage.completion_tokens ?? completionTokens
                        }
                        guard let choice = chunk.choices?.first else { continue }
                        if let reason = choice.finish_reason { stopReason = reason }
                        if let content = choice.delta?.content, !content.isEmpty {
                            continuation.yield(TokenChunk(text: content, index: index, isFinal: false))
                            index += 1
                        }
                        for call in choice.delta?.tool_calls ?? [] {
                            let slot = call.index ?? 0
                            if let name = call.function?.name, !name.isEmpty {
                                toolNames[slot] = name
                            }
                            if let args = call.function?.arguments {
                                toolArguments[slot, default: ""] += args
                            }
                        }
                    }

                    // Flush accumulated tool calls in slot order before completing.
                    for slot in toolNames.keys.sorted() {
                        guard let name = toolNames[slot] else { continue }
                        continuation.yield(TokenChunk(
                            text: "",
                            index: index,
                            isFinal: false,
                            toolCall: ModelToolCall(name: name, arguments: Self.parseToolArguments(toolArguments[slot] ?? ""))))
                        index += 1
                    }

                    continuation.yield(TokenChunk(
                        text: "",
                        index: index,
                        isFinal: true,
                        info: TokenChunk.CompletionInfo(
                            promptTokenCount: promptTokens,
                            generationTokenCount: completionTokens,
                            stopReason: stopReason.isEmpty ? "stop" : stopReason)))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: InferenceError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request mapping

    static let missingKeyMessage =
        "OpenAI API key not set. Add it in Settings or set OPENAI_API_KEY."

    static func makeRequestBody(model: String, request: GenerationRequest, defaultMaxTokens: Int) throws -> Data {
        var object: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .int(max(1, request.maxTokens ?? defaultMaxTokens)),
            "temperature": .double(Double(request.temperature)),
            "stream": .bool(true),
            "stream_options": .object(["include_usage": .bool(true)]),
            "messages": .array(mapMessages(request)),
        ]
        if !request.tools.isEmpty {
            // ToolDefinition.schema is already OpenAI's {type:"function", function:{…}}.
            object["tools"] = .array(request.tools.map(\.schema))
        }
        return try JSONEncoder().encode(JSONValue.object(object))
    }

    /// Chat messages with `system` kept inline (OpenAI takes it as a message).
    /// `tool` turns become user text and consecutive same-role turns are merged.
    static func mapMessages(_ request: GenerationRequest) -> [JSONValue] {
        let chat: [GenerationRequest.ChatMessage]
        switch request.input {
        case let .prompt(text):
            chat = [.init(role: .user, content: text)]
        case let .messages(messages):
            chat = messages
        }

        var turns: [(role: String, content: String)] = []
        for message in chat {
            switch message.role {
            case .system: turns.append((role: "system", content: message.content))
            case .user: turns.append((role: "user", content: message.content))
            case .assistant: turns.append((role: "assistant", content: message.content))
            case .tool: turns.append((role: "user", content: "[tool result]\n" + message.content))
            }
        }

        var merged: [(role: String, content: String)] = []
        for turn in turns {
            if var last = merged.last, last.role == turn.role {
                last.content += "\n\n" + turn.content
                merged[merged.count - 1] = last
            } else {
                merged.append(turn)
            }
        }

        return merged.map { JSONValue.object(["role": .string($0.role), "content": .string($0.content)]) }
    }

    static func parseToolArguments(_ json: String) -> [String: JSONValue] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              case let .object(object) = value else {
            return [:]
        }
        return object
    }

    static func errorMessage(status: Int, body: String) -> String {
        if let data = body.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data),
           let message = parsed.error?.message {
            return "OpenAI request failed (\(status)): \(message)"
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? "OpenAI request failed (\(status))."
            : "OpenAI request failed (\(status)): \(trimmed.prefix(500))"
    }
}

// MARK: - Wire decoding

struct OpenAIStreamChunk: Decodable {
    let choices: [Choice]?
    let usage: Usage?

    struct Choice: Decodable {
        let delta: Delta?
        let finish_reason: String?
    }
    struct Delta: Decodable {
        let content: String?
        let tool_calls: [ToolCallDelta]?
    }
    struct ToolCallDelta: Decodable {
        let index: Int?
        let function: FunctionDelta?
    }
    struct FunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }
    struct Usage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
    }
}

struct OpenAIErrorEnvelope: Decodable {
    let error: ErrorBody?
    struct ErrorBody: Decodable {
        let message: String?
    }
}
