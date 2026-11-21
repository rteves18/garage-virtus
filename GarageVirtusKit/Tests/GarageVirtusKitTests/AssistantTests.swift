import Foundation
import Testing
@testable import GarageVirtusKit

/// Records requests and replies with canned JSON bodies, so no test touches the network.
final class StubTransport: ClaudeTransport, @unchecked Sendable {
    var replies: [String]
    private(set) var requests: [URLRequest] = []

    init(replies: [String]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body = replies.isEmpty ? "{}" : replies.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }

    func body(_ index: Int) throws -> [String: Any] {
        let data = try #require(requests[index].httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}

private let sectionParts: [PartsListBuilder.CataloguePart] = [
    .init(oem: "08911-6401A", name: "nut-hex", price: Price(status: "Available", amount: 1.2, currency: "USD", raw: "1.20")),
    .init(oem: "55501-50F00", name: "arm assembly-rear suspension", price: Price(status: "Available", amount: 120, currency: "USD", raw: "120.00")),
    .init(oem: "55020-50F10", name: "spring-rear suspension", price: Price(status: "Not available", amount: nil, currency: "USD", raw: nil)),
]

struct ClaudeClientTests {
    @Test func requestUsesCurrentModelHeadersAndFallback() async throws {
        let transport = StubTransport(replies: [#"{"content": [{"type": "text", "text": "hi"}], "stop_reason": "end_turn", "model": "claude-opus-5-5"}"#])
        let client = ClaudeClient(apiKey: "sk-test", transport: transport)
        let reply = try await client.send(system: "ctx", messages: [.object(["role": .string("user"), "content": .string("hello")])], tools: [])
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let body = try transport.body(0)
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "medium")
        let system = try #require((body["system"] as? [[String: Any]])?.first)
        #expect(system["text"] as? String == "ctx")
        #expect((system["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral")
        #expect(reply.stopReason == "end_turn")
        #expect(reply.text == "hi")
    }

    @Test func httpErrorSurfacesAPIMessage() async throws {
        final class Failing: ClaudeTransport, @unchecked Sendable {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                (Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8),
                 HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
            }
        }
        let client = ClaudeClient(apiKey: "bad", transport: Failing())
        await #expect(throws: ClaudeClient.Failure.http(status: 401, message: "invalid x-api-key")) {
            _ = try await client.send(system: "", messages: [], tools: [])
        }
    }
}

struct PartsListBuilderTests {
    @Test func totalsPricedLinesAndFlagsTheRest() {
        let list = PartsListBuilder(parts: sectionParts).build(title: "Rear suspension hardware", items: [
            .init(oem: "089116401A", quantity: 8, reason: "arm nuts"),
            .init(oem: "55501-50F00", quantity: 2, reason: nil),
            .init(oem: "55020-50F10", quantity: 2, reason: nil),
            .init(oem: "99999-XXXXX", quantity: 1, reason: nil),
        ])
        #expect(list.lines.map(\.oem) == ["08911-6401A", "55501-50F00", "55020-50F10", "99999-XXXXX"])
        #expect(list.lines[0].lineTotal == Decimal(string: "9.6"))
        #expect(list.total == Decimal(string: "249.6"))
        #expect(list.lines[2].lineTotal == nil)
        #expect(list.lines[2].status == "Not available")
        #expect(list.lines[3].isInSection == false)
        #expect(list.unpricedCount == 2)
    }
}

struct PartsAssistantTests {
    @MainActor @Test func toolCallBuildsListAndSendsComputedTotalBack() async throws {
        let toolUse = #"{"content": [{"type": "thinking", "thinking": "", "signature": "sig"}, {"type": "tool_use", "id": "toolu_1", "name": "build_parts_list", "input": {"title": "Hardware", "items": [{"oem": "08911-6401A", "quantity": 8, "reason": "arm nuts"}]}}], "stop_reason": "tool_use", "model": "claude-opus-5-5"}"#
        let done = #"{"content": [{"type": "text", "text": "You need 8 nuts, $9.60 total."}], "stop_reason": "end_turn", "model": "claude-opus-5-5"}"#
        let transport = StubTransport(replies: [toolUse, done])
        let assistant = PartsAssistant(client: ClaudeClient(apiKey: "k", transport: transport),
                                       context: "section", parts: sectionParts)
        await assistant.send("What hardware do I need?")

        #expect(assistant.entries.count == 3)
        guard case .user(let question) = assistant.entries[0], case .partsList(let list) = assistant.entries[1],
              case .assistant(let answer) = assistant.entries[2] else { Issue.record("unexpected entries \(assistant.entries)"); return }
        #expect(question == "What hardware do I need?")
        #expect(list.total == Decimal(string: "9.6"))
        #expect(answer == "You need 8 nuts, $9.60 total.")

        let second = try transport.body(1)
        let messages = try #require(second["messages"] as? [[String: Any]])
        #expect(messages.count == 3)
        let echoed = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(echoed.first?["type"] as? String == "thinking")          // assistant content sent back unchanged
        let result = try #require((messages[2]["content"] as? [[String: Any]])?.first)
        #expect(result["tool_use_id"] as? String == "toolu_1")
        #expect((result["content"] as? String)?.contains("\"total\"") == true)
    }

    @MainActor @Test func refusalIsShownAsAMessage() async throws {
        let transport = StubTransport(replies: [#"{"content": [], "stop_reason": "refusal", "model": "claude-opus-5-5"}"#])
        let assistant = PartsAssistant(client: ClaudeClient(apiKey: "k", transport: transport), context: "", parts: [])
        await assistant.send("hi")
        guard case .notice(let text) = assistant.entries.last else { Issue.record("no notice"); return }
        #expect(text.contains("declined"))
    }
}

struct SectionContextTests {
    @Test func contextListsCalloutsPartsAndCoverage() throws {
        let url = try #require(Bundle.module.url(forResource: "schema-group", withExtension: "json", subdirectory: "Fixtures"))
        let file = try CatalogueStore.makeDecoder().decode(SchemaGroupFile.self, from: Data(contentsOf: url))
        let text = SectionContext.describe(file: file, schemas: [file.schemas[1]],
                                           coverage: ["1010250FR2": Coverage(needed: 1, owned: 0)])
        #expect(text.contains("bearing & short engine assembly"))
        #expect(text.contains("R10102"))
        #expect(text.contains("10102-50FR2"))
        #expect(text.contains("need 1, have 0"))
        #expect(text.contains("101B_001_1"))
        #expect(text.contains("101B_001_0") == false)
    }
}
