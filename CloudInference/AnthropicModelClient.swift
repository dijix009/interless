import Foundation
import Shared

/// Streams from Anthropic's Messages API and adapts it to Interless's
/// backend-agnostic `TokenChunk` stream. MLX-free; transport + key provider are
/// injected so it is fully unit-testable without network.
///
/// Tool calling is text-mode-consistent with the local path: prior tool results
/// are sent as plain user turns (no structured tool_use/tool_result id threading),
/// while `tools` are still advertised so the model can emit a fresh `tool_use`,
/// which is surfaced as a `ModelToolCall` chunk.
public struct AnthropicModelClient: CloudModelClient {
    private let transport: any HTTPTransport
    private let keyProvider: any CloudKeyProvider
    private let baseURL: URL
    private let apiVersion: String
    private let defaultMaxTokens: Int

    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        keyProvider: any CloudKeyProvider = KeychainCloudKeyProvider(),
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        apiVersion: String = "2023-06-01",
        defaultMaxTokens: Int = 4096
    ) {
        self.transport = transport
        self.keyProvider = keyProvider
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.defaultMaxTokens = defaultMaxTokens
    }

    public func validate() async throws {
        guard await keyProvider.apiKey(for: .anthropic) != nil else {
            throw InferenceError.generationFailed(Self.missingKeyMessage)
        }
    }

    public func stream(model: String, request: GenerationRequest) -> AsyncThrowingStream<TokenChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = await keyProvider.apiKey(for: .anthropic) else {
                        throw InferenceError.generationFailed(Self.missingKeyMessage)
                    }
                    let body = try Self.makeRequestBody(
                        model: model, request: request, defaultMaxTokens: defaultMaxTokens)
                    let spec = HTTPRequestSpec(
                        url: baseURL.appendingPathComponent("v1/messages"),
                        method: "POST",
                        headers: [
                            "x-api-key": key,
                            "anthropic-version": apiVersion,
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
                    var outputTokens = 0
                    var stopReason = ""
                    var pendingToolName: String?
                    var pendingToolJSON = ""

                    for try await line in lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty, payload != "[DONE]",
                              let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: data) else {
                            continue
                        }
                        switch event.type {
                        case "message_start":
                            promptTokens = event.message?.usage?.input_tokens ?? 0
                        case "content_block_start":
                            if event.content_block?.type == "tool_use" {
                                pendingToolName = event.content_block?.name
                                pendingToolJSON = ""
                            }
                        case "content_block_delta":
                            if event.delta?.type == "text_delta", let text = event.delta?.text, !text.isEmpty {
                                continuation.yield(TokenChunk(text: text, index: index, isFinal: false))
                                index += 1
                            } else if event.delta?.type == "input_json_delta", let partial = event.delta?.partial_json {
                                pendingToolJSON += partial
                            }
                        case "content_block_stop":
                            if let name = pendingToolName {
                                continuation.yield(TokenChunk(
                                    text: "",
                                    index: index,
                                    isFinal: false,
                                    toolCall: ModelToolCall(name: name, arguments: Self.parseToolArguments(pendingToolJSON))))
                                index += 1
                                pendingToolName = nil
                                pendingToolJSON = ""
                            }
                        case "message_delta":
                            if let stop = event.delta?.stop_reason { stopReason = stop }
                            if let out = event.usage?.output_tokens { outputTokens = out }
                        case "error":
                            throw InferenceError.generationFailed(event.error?.message ?? "Anthropic stream error")
                        default:
                            break
                        }
                    }

                    continuation.yield(TokenChunk(
                        text: "",
                        index: index,
                        isFinal: true,
                        info: TokenChunk.CompletionInfo(
                            promptTokenCount: promptTokens,
                            generationTokenCount: outputTokens,
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
        "Anthropic API key not set. Add it in Settings or set ANTHROPIC_API_KEY."

    static func makeRequestBody(model: String, request: GenerationRequest, defaultMaxTokens: Int) throws -> Data {
        let (system, messages) = mapMessages(request)
        var object: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .int(max(1, request.maxTokens ?? defaultMaxTokens)),
            "temperature": .double(Double(request.temperature)),
            "stream": .bool(true),
            "messages": .array(messages),
        ]
        if let system, !system.isEmpty {
            object["system"] = .string(system)
        }
        if !request.tools.isEmpty {
            object["tools"] = .array(request.tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "input_schema": normalizedSchema(tool.parameters),
                ])
            })
        }
        return try JSONEncoder().encode(JSONValue.object(object))
    }

    /// Maps the request into a top-level `system` string + alternating user/assistant
    /// messages. System turns are hoisted out (Anthropic takes system separately);
    /// `tool` turns become user text; consecutive same-role turns are merged so the
    /// transcript alternates as Anthropic expects.
    static func mapMessages(_ request: GenerationRequest) -> (system: String?, messages: [JSONValue]) {
        let chat: [GenerationRequest.ChatMessage]
        switch request.input {
        case let .prompt(text):
            chat = [.init(role: .user, content: text)]
        case let .messages(messages):
            chat = messages
        }

        var systemParts: [String] = []
        var turns: [(role: String, content: String)] = []
        for message in chat {
            switch message.role {
            case .system:
                systemParts.append(message.content)
            case .user:
                turns.append((role: "user", content: message.content))
            case .assistant:
                turns.append((role: "assistant", content: message.content))
            case .tool:
                turns.append((role: "user", content: "[tool result]\n" + message.content))
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

        let messages = merged.map { turn in
            JSONValue.object(["role": .string(turn.role), "content": .string(turn.content)])
        }
        let system = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
        return (system, messages)
    }

    /// Anthropic's `input_schema` must be a JSON Schema object. The registry already
    /// produces object schemas; wrap defensively if not.
    static func normalizedSchema(_ schema: JSONValue) -> JSONValue {
        if case .object = schema { return schema }
        return .object(["type": .string("object")])
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
           let parsed = try? JSONDecoder().decode(AnthropicErrorEnvelope.self, from: data),
           let message = parsed.error?.message {
            return "Anthropic request failed (\(status)): \(message)"
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? "Anthropic request failed (\(status))."
            : "Anthropic request failed (\(status)): \(trimmed.prefix(500))"
    }
}

// MARK: - Wire decoding

struct AnthropicStreamEvent: Decodable {
    let type: String
    let delta: Delta?
    let content_block: ContentBlock?
    let message: MessageStart?
    let usage: Usage?
    let error: ErrorBody?

    struct Delta: Decodable {
        let type: String?
        let text: String?
        let partial_json: String?
        let stop_reason: String?
    }
    struct ContentBlock: Decodable {
        let type: String?
        let name: String?
    }
    struct MessageStart: Decodable {
        let usage: Usage?
    }
    struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
    }
    struct ErrorBody: Decodable {
        let type: String?
        let message: String?
    }
}

struct AnthropicErrorEnvelope: Decodable {
    let error: AnthropicStreamEvent.ErrorBody?
}
