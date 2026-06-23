import Foundation

/// A single outbound HTTP request. Kept minimal and value-typed so the transport
/// can be faked in tests (this is the app's only outbound network path).
public struct HTTPRequestSpec: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data

    public init(url: URL, method: String = "POST", headers: [String: String] = [:], body: Data = Data()) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponseHead: Sendable, Equatable {
    public var statusCode: Int
    public init(statusCode: Int) { self.statusCode = statusCode }
}

/// Sends a request and streams the response body back as UTF-8 lines
/// (newline-delimited — sufficient for SSE, whose framing is line based).
/// Injectable so tests drive canned responses with no real network.
public protocol HTTPTransport: Sendable {
    func stream(_ request: HTTPRequestSpec) async throws -> (head: HTTPResponseHead, lines: AsyncThrowingStream<String, Error>)
}

public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func stream(_ request: HTTPRequestSpec) async throws -> (head: HTTPResponseHead, lines: AsyncThrowingStream<String, Error>) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (bytes, response) = try await session.bytes(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let lines = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (HTTPResponseHead(statusCode: status), lines)
    }
}
