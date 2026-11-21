import Foundation

/// Describes a schema group for the assistant: callouts, parts, quantities, prices and My garage coverage.
public enum SectionContext {
    public static func describe(file: SchemaGroupFile, schemas: [Schema], coverage: [String: Coverage]) -> String {
        let vehicle = file.vehicle
        var lines = [
            "Section: \(file.group.name) (group \(file.group.code), \(file.group.category))",
            "Vehicle: \([vehicle.model, vehicle.frame, vehicle.grade, vehicle.engine, vehicle.transmission].compactMap { $0 }.joined(separator: " "))",
        ]
        for schema in schemas {
            let applies = schema.applies.isEmpty ? "" : " · " + schema.applies.joined(separator: ", ")
            lines.append("")
            lines.append("Diagram \(schema.id) (schema \(schema.index)\(applies)\(schema.period.map { " · " + $0.display } ?? "")):")
            for callout in schema.callouts {
                lines.append("  Callout \(callout.pnc) \(callout.name ?? ""):")
                for part in callout.parts {
                    var fields = [part.oem]
                    if !part.applies.isEmpty { fields.append("applies: " + part.applies.joined(separator: ", ")) }
                    if let period = part.period { fields.append(period.display) }
                    if let qty = part.qty { fields.append("qty per car \(qty)") }
                    fields.append(part.price.amount.map { String(format: "$%.2f", $0) } ?? (part.price.status ?? "no price"))
                    if let covered = coverage[CatalogueStore.normalize(part.oem)] {
                        fields.append("my garage: need \(covered.needed), have \(covered.owned)")
                    }
                    if !part.replacements.isEmpty {
                        fields.append("replaced by " + part.replacements.map(\.oem).joined(separator: ", "))
                    }
                    lines.append("    - " + fields.joined(separator: " | "))
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
