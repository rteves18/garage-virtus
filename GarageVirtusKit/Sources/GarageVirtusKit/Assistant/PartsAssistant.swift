import Foundation
import Observation

/// A chat about one catalogue section. Claude answers and, for "what do I need" questions, calls `build_parts_list`;
/// the app prices the list and sends the computed totals back.
@MainActor
@Observable
public final class PartsAssistant {
    public enum Entry: Equatable, Sendable {
        case user(String)
        case assistant(String)
        case partsList(PartsList)
        /// Errors, refusals, and other app messages.
        case notice(String)
    }

    public private(set) var entries: [Entry] = []
    public private(set) var isSending = false

    @ObservationIgnored private let client: ClaudeClient
    @ObservationIgnored private let system: String
    @ObservationIgnored private let builder: PartsListBuilder
    @ObservationIgnored private var messages: [JSONValue] = []
    private let maxToolRounds = 6

    public init(client: ClaudeClient, context: String, parts: [PartsListBuilder.CataloguePart]) {
        self.client = client
        builder = PartsListBuilder(parts: parts)
        system = Self.instructions + "\n\n" + context
    }

    /// Sends Ryan's message and runs the tool loop until Claude finishes. Errors become notices in the chat.
    public func send(_ text: String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        entries.append(.user(question))
        messages.append(.object(["role": .string("user"), "content": .string(question)]))

        do {
            for _ in 0..<maxToolRounds {
                let reply = try await client.send(system: system, messages: messages, tools: [Self.buildPartsListTool])
                // Sent back unchanged on the next request (thinking blocks included).
                messages.append(.object(["role": .string("assistant"), "content": .array(reply.content)]))
                if !reply.text.isEmpty { entries.append(.assistant(reply.text)) }

                switch reply.stopReason {
                case "refusal":
                    entries.append(.notice("Claude declined to answer that. Try asking about the parts in a different way."))
                    return
                case "max_tokens":
                    entries.append(.notice("The answer was cut off because it got too long. Ask for a shorter list."))
                    return
                case "tool_use":
                    messages.append(.object(["role": .string("user"), "content": .array(reply.toolUses.map(runTool))]))
                default:
                    return
                }
            }
            entries.append(.notice("Stopped after \(maxToolRounds) tool rounds without a final answer."))
        } catch {
            entries.append(.notice(error.localizedDescription))
        }
    }

    private func runTool(_ call: (id: String, name: String, input: JSONValue)) -> JSONValue {
        guard call.name == "build_parts_list" else {
            return Self.toolResult(id: call.id, content: "Unknown tool \(call.name).", isError: true)
        }
        let items = (call.input["items"]?.array ?? []).compactMap { item -> PartsListBuilder.Item? in
            guard let oem = item["oem"]?.string else { return nil }
            return .init(oem: oem, quantity: max(Int(item["quantity"]?.number ?? 1), 1), reason: item["reason"]?.string)
        }
        let list = builder.build(title: call.input["title"]?.string ?? "Parts list", items: items)
        entries.append(.partsList(list))
        return Self.toolResult(id: call.id, content: Self.summary(of: list), isError: false)
    }

    private static func summary(of list: PartsList) -> String {
        let lines: [JSONValue] = list.lines.map { line in
            .object([
                "oem": .string(line.oem), "name": .string(line.name), "quantity": .number(Double(line.quantity)),
                "line_total": line.lineTotal.map { .string("\($0)") } ?? .null,
                "status": line.status.map { .string($0) } ?? .null,
                "in_section": .bool(line.isInSection),
            ])
        }
        let summary = JSONValue.object([
            "total": .string("\(list.total)"), "currency": .string(list.currency),
            "unpriced_lines": .number(Double(list.unpricedCount)), "lines": .array(lines),
        ])
        let data = (try? JSONEncoder().encode(summary)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func toolResult(id: String, content: String, isError: Bool) -> JSONValue {
        var block: [String: JSONValue] = ["type": .string("tool_result"), "tool_use_id": .string(id), "content": .string(content)]
        if isError { block["is_error"] = .bool(true) }
        return .object(block)
    }

    static let instructions = """
    You help Ryan restore his 1997 Nissan 180SX (KRPS13). Answer questions about the catalogue section below: its \
    diagrams, callouts, part numbers, quantities, prices, and what Ryan already has or needs (the "my garage" fields).

    When he asks what parts he needs or wants a list (for example "all the hardware": bolts, nuts, washers, clips, \
    which usually have part numbers starting 01 or 08), call build_parts_list with part numbers from this section and \
    the quantity for one car. The app prices the list and shows it to him with a total; use the total it returns and \
    don't calculate prices yourself. Only use part numbers that appear in the section. Where a part has a replacement, \
    prefer the replacement part number. If a part only applies to another engine or date range, leave it out and say so.

    Keep answers short and practical.
    """

    static let buildPartsListTool: JSONValue = .object([
        "name": .string("build_parts_list"),
        "description": .string("Show Ryan a priced list of parts from this section. The app looks up each part number, prices it, and returns line totals and the grand total."),
        "input_schema": .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object(["type": .string("string"), "description": .string("Short title, e.g. 'Rear suspension hardware'")]),
                "items": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "oem": .object(["type": .string("string"), "description": .string("Part number exactly as listed in the section")]),
                            "quantity": .object(["type": .string("integer"), "description": .string("How many one car needs")]),
                            "reason": .object(["type": .string("string"), "description": .string("Where it goes, e.g. 'lower arm to subframe'")]),
                        ]),
                        "required": .array([.string("oem"), .string("quantity")]),
                    ]),
                ]),
            ]),
            "required": .array([.string("title"), .string("items")]),
        ]),
    ])
}
