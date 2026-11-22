import Foundation
import GarageVirtusKit
import MCP

// garage-virtus-mcp: an MCP server (stdio) that lets Claude Desktop / Claude Code use Ryan's Garage Virtus catalogue
// and My garage data on his Claude subscription.
//
//   garage-virtus-mcp --catalogue /path/to/garage-virtus/catalogue [--store /path/to/default.store]
//
// stdout carries the MCP protocol, so anything else goes to stderr.

func log(_ message: String) {
    FileHandle.standardError.write(Data("garage-virtus-mcp: \(message)\n".utf8))
}

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
    return args[index + 1]
}

let defaultStore = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Containers/com.rteves.GarageVirtus/Data/Library/Application Support/default.store")

guard let cataloguePath = argument("--catalogue") ?? ProcessInfo.processInfo.environment["GARAGE_VIRTUS_CATALOGUE"] else {
    log("pass --catalogue /path/to/garage-virtus/catalogue")
    exit(64)
}
let storeURL = argument("--store").map { URL(fileURLWithPath: $0) } ?? defaultStore
guard FileManager.default.fileExists(atPath: storeURL.path) else {
    log("no garage store at \(storeURL.path). Open the Garage Virtus app once to create it, or pass --store.")
    exit(66)
}

let catalogue = CatalogueStore(folder: URL(fileURLWithPath: cataloguePath, isDirectory: true))
let garage: GarageStore
do {
    garage = GarageStore(container: try GarageStore.makeContainer(url: storeURL))
} catch {
    log("couldn't open the garage store: \(error)")
    exit(74)
}
let tools = GarageTools(catalogue: catalogue, garage: garage)
log("catalogue: \(catalogue.scrapedCount) scraped groups, \(catalogue.indexedPartCount) part numbers; store: \(storeURL.path)")

// MARK: tool definitions

func schema(_ properties: [String: Value], required: [String] = []) -> Value {
    .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map { .string($0) })])
}

let itemsSchema: Value = .object([
    "type": .string("array"),
    "items": schema([
        "oem": .object(["type": .string("string"), "description": .string("Part number as listed, e.g. 10102-50FR2")]),
        "quantity": .object(["type": .string("integer"), "description": .string("How many one car needs")]),
        "reason": .object(["type": .string("string"), "description": .string("Where it goes, e.g. 'lower arm to subframe'")]),
    ], required: ["oem", "quantity"]),
])

let toolList: [Tool] = [
    Tool(name: "search_parts",
         description: "Find a Nissan part number (full or partial, any dashes) or an Amayama part link in the 180SX catalogue: which groups and diagram callouts use it, with one row per source (amayama is primary, megazip secondary) and that source's price, so you can compare providers.",
         inputSchema: schema(["query": .object(["type": .string("string")])], required: ["query"])),
    Tool(name: "list_groups",
         description: "List the catalogue's schema groups (code, name, category, whether scraped). Categories: engine, body, trans, electric, misc.",
         inputSchema: schema(["category": .object(["type": .string("string")])])),
    Tool(name: "get_section",
         description: "Everything in one schema group (e.g. 431 rear suspension): diagrams, callouts, part numbers, quantity per car, price or availability, replacements, and how many Ryan has / needs. Pass year (e.g. '1995' or '1995-03') to keep only diagrams for that build date; Ryan's car is a 1994+ SR20DET MT Type X. Data comes from the primary source (amayama) unless you pass source (e.g. 'megazip'); the reply lists available_sources.",
         inputSchema: schema(["group_code": .object(["type": .string("string")]), "year": .object(["type": .string("string")]),
                              "source": .object(["type": .string("string"), "description": .string("amayama (primary, default) or megazip")])], required: ["group_code"])),
    Tool(name: "build_parts_list",
         description: "Price a list of catalogue part numbers with quantities. Returns line totals and the grand total computed from catalogue prices; use this total rather than adding prices yourself. Prices come from each part's primary source (amayama) unless you pass source (e.g. 'megazip') to price the whole list from that provider.",
         inputSchema: schema(["title": .object(["type": .string("string")]), "items": itemsSchema,
                              "source": .object(["type": .string("string"), "description": .string("amayama (primary, default) or megazip")])], required: ["title", "items"])),
    Tool(name: "garage_status",
         description: "Ryan's My garage for the current car: parts per status (need, want, in storage, waiting to install, installed), total spent, and needs still short.",
         inputSchema: schema([:])),
    Tool(name: "add_to_garage",
         description: "Record parts in Ryan's My garage as needed (required for the restoration) or wanted (an upgrade) for the current car. Only do this when Ryan asks. The Garage Virtus app shows them after it's reopened.",
         inputSchema: schema(["status": .object(["type": .string("string"), "enum": .array([.string("need"), .string("want")])]), "items": itemsSchema], required: ["status", "items"])),
]

func items(_ value: Value?) -> [PartsListBuilder.Item] {
    (value?.arrayValue ?? []).compactMap { item in
        guard let oem = item.objectValue?["oem"]?.stringValue else { return nil }
        let quantity = item.objectValue?["quantity"]?.intValue ?? Int(item.objectValue?["quantity"]?.doubleValue ?? 1)
        return .init(oem: oem, quantity: max(quantity, 1), reason: item.objectValue?["reason"]?.stringValue)
    }
}

/// Maps MCP tool calls to GarageTools. Main-actor isolated, so the server's concurrent handlers can share it.
@MainActor
final class ToolRouter {
    let tools: GarageTools
    init(tools: GarageTools) { self.tools = tools }

    func run(_ name: String, _ arguments: [String: Value]) throws -> String {
    switch name {
    case "search_parts": try tools.searchParts(query: arguments["query"]?.stringValue ?? "")
    case "list_groups": try tools.listGroups(category: arguments["category"]?.stringValue)
    case "get_section":
        try tools.section(groupCode: arguments["group_code"]?.stringValue ?? "", year: arguments["year"]?.stringValue,
                          source: arguments["source"]?.stringValue)
    case "build_parts_list":
        try tools.buildPartsList(title: arguments["title"]?.stringValue ?? "Parts list", items: items(arguments["items"]),
                                 source: arguments["source"]?.stringValue)
    case "garage_status": try tools.garageStatus()
    case "add_to_garage":
        try tools.addToGarage(items: items(arguments["items"]),
                              status: arguments["status"]?.stringValue == "want" ? .want : .need)
    default: throw GarageTools.Failure.unknownGroup(name)
    }
    }
}

let router = ToolRouter(tools: tools)

// MARK: server

let server = Server(name: "garage-virtus", version: "1.0.0", capabilities: .init(tools: .init(listChanged: false)))

await server.withMethodHandler(ListTools.self) { _ in .init(tools: toolList) }
await server.withMethodHandler(CallTool.self) { params in
    do {
        let text = try await router.run(params.name, params.arguments ?? [:])
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)], isError: false)
    } catch {
        return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
    }
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
