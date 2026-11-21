import Foundation

/// Sends HTTP requests. The app uses `URLSessionTransport`; tests use a stub so nothing touches the network.
public protocol ClaudeTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: ClaudeTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeClient.Failure.invalidResponse }
        return (data, http)
    }
}

/// A minimal Claude Messages API client (raw HTTP; there is no official Swift SDK).
public struct ClaudeClient: Sendable {
    public static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public enum Failure: Error, Equatable, LocalizedError {
        case http(status: Int, message: String)
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .http(let status, let message): "Claude API error \(status): \(message)"
            case .invalidResponse: "Claude API returned a response the app couldn't read."
            }
        }
    }

    /// One assistant turn, with its content blocks kept exactly as received.
    public struct Reply: Sendable {
        public let content: [JSONValue]
        public let stopReason: String?
        public let model: String?

        public var text: String {
            content.filter { $0["type"]?.string == "text" }.compactMap { $0["text"]?.string }.joined(separator: "\n")
        }

        public var toolUses: [(id: String, name: String, input: JSONValue)] {
            content.compactMap { block in
                guard block["type"]?.string == "tool_use", let id = block["id"]?.string,
                      let name = block["name"]?.string else { return nil }
                return (id, name, block["input"] ?? .object([:]))
            }
        }
    }

    private let apiKey: String
    private let transport: any ClaudeTransport

    public init(apiKey: String, transport: any ClaudeTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    /// Sends one Messages request. `system` is cached, so follow-up questions about the same section are cheap.
    public func send(system: String, messages: [JSONValue], tools: [JSONValue]) async throws -> Reply {
        var body: [String: JSONValue] = [
            "model": .string(Self.model),
            "max_tokens": .number(16000),
            "system": .array([.object(["type": .string("text"), "text": .string(system),
                                       "cache_control": .object(["type": .string("ephemeral")])])]),
            "messages": .array(messages),
            "output_config": .object(["effort": .string("medium")]),
            "fallbacks": .string("default"),
        ]
        if !tools.isEmpty { body["tools"] = .array(tools) }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

        let (data, response) = try await transport.send(request)
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        guard (200..<300).contains(response.statusCode) else {
            throw Failure.http(status: response.statusCode,
                               message: json?["error"]?["message"]?.string ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode))
        }
        guard let json else { throw Failure.invalidResponse }
        return Reply(content: json["content"]?.array ?? [], stopReason: json["stop_reason"]?.string, model: json["model"]?.string)
    }
}
